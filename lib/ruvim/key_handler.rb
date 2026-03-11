# frozen_string_literal: true

require_relative "key_handler/pending_state"
require_relative "key_handler/macro_dot"
require_relative "key_handler/insert_mode"

module RuVim
  class KeyHandler
      include PendingState
      include MacroDot
      include InsertMode

      # Rich mode: delegates to normal mode key handling but blocks mutating operations.
      RICH_MODE_BLOCKED_COMMANDS = %w[
        mode.insert mode.append mode.append_line_end mode.insert_nonblank
        mode.open_below mode.open_above
        buffer.delete_char buffer.delete_line buffer.delete_motion
        buffer.change_motion buffer.change_line
        buffer.paste_after buffer.paste_before
        buffer.replace_char
        buffer.visual_delete
      ].freeze

      attr_accessor :paste_batch
      attr_reader :completion

      def load_history!  = @completion.load_history!
      def save_history!  = @completion.save_history!

      def initialize(editor:, dispatcher:, completion:)
        @editor = editor
        @dispatcher = dispatcher
        @completion = completion

        @pending_key_deadline = nil
        @pending_ambiguous_invocation = nil
        @pending_keys = nil
        @insert_start_location = nil
        @paste_batch = false

        # Pending state flags
        @operator_pending = nil
        @register_pending = false
        @mark_pending = false
        @jump_pending = nil
        @find_pending = nil
        @replace_pending = nil
        @macro_record_pending = false
        @macro_play_pending = false
        @visual_pending = nil
        @skip_record_for_current_key = false
        @last_macro_name = nil
        @macro_play_stack = nil
        @suspend_macro_recording_depth = nil

        # Dot repeat state
        @dot_change_capture_active = false
        @dot_change_capture_keys = nil
        @last_change_keys = nil
        @dot_replay_depth = nil
      end

      # Returns true if redraw is needed due to timeout/transient message handling
      def handle_idle_timeout
        redraw = false
        if pending_key_timeout_expired?
          handle_pending_key_timeout
          redraw = true
        end
        redraw = true if @editor.clear_expired_transient_message!(now: monotonic_now)
        redraw
      end

      def pending_key_timeout_seconds
        return nil unless @pending_key_deadline

        [@pending_key_deadline - monotonic_now, 0.0].max
      end

      def loop_timeout_seconds
        now = monotonic_now
        timeouts = []
        if @pending_key_deadline
          timeouts << [@pending_key_deadline - now, 0.0].max
        end
        if (msg_to = @editor.transient_message_timeout_seconds(now:))
          timeouts << msg_to
        end
        timeouts.min
      end

      def escape_sequence_timeout_seconds
        ms = @editor.global_options["ttimeoutlen"].to_i
        ms = 50 if ms <= 0
        ms / 1000.0
      rescue StandardError
        0.005
      end

      # Returns true if redraw is needed
      def handle(key)
        mode_before = @editor.mode
        clear_stale_message_before_key(key)
        @skip_record_for_current_key = false
        append_dot_change_capture_key(key)
        if key == :ctrl_z
          suspend_to_shell
          track_mode_transition(mode_before)
          return true
        end
        if key == :ctrl_c && @editor.mode != :normal
          handle_ctrl_c
          track_mode_transition(mode_before)
          record_macro_key_if_needed(key)
          return false
        end

        case @editor.mode
        when :hit_enter
          handle_hit_enter_key(key)
        when :insert
          handle_insert_key(key)
        when :command_line
          handle_command_line_key(key)
        when :visual_char, :visual_line, :visual_block
          handle_visual_key(key)
        when :rich
          handle_rich_key(key)
        else
          handle_normal_key(key)
        end
        track_mode_transition(mode_before)
        record_macro_key_if_needed(key)
        false
      rescue RuVim::CommandError => e
        @editor.echo_error(e.message)
        false
      end

      def handle_editor_app_action(name, **kwargs)
        if @editor.rich_mode?
          case name
          when :normal_operator_start
            op = kwargs[:name] || kwargs["name"]
            return if op == :delete || op == :change
          when :normal_replace_pending_start, :normal_change_repeat
            return
          end
        end

        case name
        when :normal_register_pending_start
          start_register_pending
        when :normal_operator_start
          start_operator_pending(kwargs[:name] || kwargs["name"])
        when :normal_replace_pending_start
          start_replace_pending
        when :normal_find_pending_start
          start_find_pending((kwargs[:token] || kwargs["token"]).to_s)
        when :normal_find_repeat
          repeat_last_find(reverse: !!(kwargs[:reverse] || kwargs["reverse"]))
        when :normal_change_repeat
          repeat_last_change
        when :normal_macro_record_toggle
          toggle_macro_recording_or_start_pending
        when :normal_macro_play_pending_start
          start_macro_play_pending
        when :normal_mark_pending_start
          start_mark_pending
        when :normal_jump_pending_start
          start_jump_pending(
            linewise: !!(kwargs[:linewise] || kwargs["linewise"]),
            repeat_token: (kwargs[:repeat_token] || kwargs["repeat_token"]).to_s
          )
        when :follow_toggle
          @editor.follow_toggle!
        when :normal_ctrl_c
          handle_normal_ctrl_c
        else
          raise RuVim::CommandError, "Unknown app action: #{name}"
        end
      end

      def handle_normal_ctrl_c
        clear_pending_key_timeout
        @editor.pending_count = nil
        @pending_keys = []
        @operator_pending = nil
        @replace_pending = nil
        @register_pending = false
        @mark_pending = false
        @jump_pending = nil
        @macro_record_pending = false
        @macro_play_pending = false
        buf = @editor.current_buffer
        if buf && @editor.follow_active?(buf)
          @editor.stop_follow!(buf)
        else
          @editor.clear_message
        end
      end

      private

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue StandardError
        Time.now.to_f
      end

      def arm_pending_key_timeout
        ms = @editor.global_options["timeoutlen"].to_i
        ms = 1000 if ms <= 0
        @pending_key_deadline = monotonic_now + (ms / 1000.0)
      end

      def clear_pending_key_timeout
        @pending_key_deadline = nil
        @pending_ambiguous_invocation = nil
      end

      def pending_key_timeout_expired?
        @pending_key_deadline && monotonic_now >= @pending_key_deadline
      end

      def handle_pending_key_timeout
        inv = @pending_ambiguous_invocation
        clear_pending_key_timeout
        if inv
          @dispatcher.dispatch(@editor, dup_invocation(inv))
        elsif @pending_keys && !@pending_keys.empty?
          @editor.echo_error("Unknown key: #{@pending_keys.join}")
        end
        @editor.pending_count = nil
        @pending_keys = []
      end

      def clear_stale_message_before_key(key)
        return if @editor.message.to_s.empty?
        return if @editor.command_line_active?
        return if @editor.hit_enter_active?
        return if key == :ctrl_c

        @editor.clear_message
      end

      # --- Normal mode ---

      def handle_normal_key(key)
        case
        when handle_normal_key_pre_dispatch(key)
        when (token = normalize_key_token(key)).nil?
        when handle_normal_pending_state(token)
        when handle_normal_direct_token(token)
        else
          @pending_keys ||= []
          @pending_keys << token
          resolve_normal_key_sequence
        end
      end

      def handle_normal_key_pre_dispatch(key)
        case
        when key == :enter && handle_list_window_enter
        when digit_key?(key) && count_digit_allowed?(key)
          @editor.pending_count = (@editor.pending_count.to_s + key).to_i
          @editor.echo(@editor.pending_count.to_s)
          @pending_keys = []
        else
          return false
        end
        true
      end

      def handle_normal_pending_state(token)
        case
        when @pending_keys && !@pending_keys.empty?
          @pending_keys << token
          resolve_normal_key_sequence
        when @operator_pending
          handle_operator_pending_key(token)
        when @register_pending
          finish_register_pending(token)
        when @mark_pending
          finish_mark_pending(token)
        when @jump_pending
          finish_jump_pending(token)
        when @macro_record_pending
          finish_macro_record_pending(token)
        when @macro_play_pending
          finish_macro_play_pending(token)
        when @replace_pending
          handle_replace_pending_key(token)
        when @find_pending
          finish_find_pending(token)
        else
          return false
        end
        true
      end

      def handle_normal_direct_token(token)
        false
      end

      def resolve_normal_key_sequence
        match = @editor.keymap_manager.resolve_with_context(:normal, @pending_keys, editor: @editor)
        case match.status
        when :pending, :ambiguous
          if match.status == :ambiguous && match.invocation
            inv = dup_invocation(match.invocation)
            inv.count = @editor.pending_count
            @pending_ambiguous_invocation = inv
          else
            @pending_ambiguous_invocation = nil
          end
          arm_pending_key_timeout
          return
        when :match
          clear_pending_key_timeout
          matched_keys = @pending_keys.dup
          repeat_count = @editor.pending_count
          @pending_keys = []
          invocation = dup_invocation(match.invocation)
          invocation.count = repeat_count
          if @editor.rich_mode? && rich_mode_block_command?(invocation.id)
            @editor.pending_count = nil
            @pending_keys = []
            return
          end
          @dispatcher.dispatch(@editor, invocation)
          maybe_record_simple_dot_change(invocation, matched_keys, repeat_count)
        else
          clear_pending_key_timeout
          @editor.echo_error("Unknown key: #{@pending_keys.join}")
        end
        @editor.pending_count = nil
        @pending_keys = []
      end

      # --- Visual mode ---

      def handle_visual_key(key)
        if arrow_key?(key)
          invoke_arrow(key)
          return
        end

        if paging_key?(key)
          invoke_page_key(key)
          return
        end

        token = normalize_key_token(key)
        return if token.nil?

        case token
        when "\e"
          @register_pending = false
          @visual_pending = nil
          @editor.enter_normal_mode
        when "v"
          if @editor.mode == :visual_char
            @editor.enter_normal_mode
          else
            @editor.enter_visual(:visual_char)
          end
        when "V"
          if @editor.mode == :visual_line
            @editor.enter_normal_mode
          else
            @editor.enter_visual(:visual_line)
          end
        when "<C-v>"
          if @editor.mode == :visual_block
            @editor.enter_normal_mode
          else
            @editor.enter_visual(:visual_block)
          end
        when "y"
          @dispatcher.dispatch(@editor, CommandInvocation.new(id: "buffer.visual_yank"))
        when "d"
          @visual_pending = nil
          @dispatcher.dispatch(@editor, CommandInvocation.new(id: "buffer.visual_delete"))
        when "="
          @dispatcher.dispatch(@editor, CommandInvocation.new(id: "buffer.visual_indent"))
        when "\""
          start_register_pending
        when "i", "a"
          @visual_pending = token
        else
          if @register_pending
            finish_register_pending(token)
            return
          end
          if @visual_pending
            if @editor.mode == :visual_block
              @visual_pending = nil
              @editor.echo_error("text object in Visual block not supported yet")
              return
            end
            motion = "#{@visual_pending}#{token}"
            @visual_pending = nil
            inv = CommandInvocation.new(id: "buffer.visual_select_text_object", kwargs: { motion: motion })
            @dispatcher.dispatch(@editor, inv)
          else
            handle_visual_motion_token(token)
          end
        end
        @editor.pending_count = nil
        @pending_keys = []
      end

      def handle_visual_motion_token(token)
        id = {
          "h" => "cursor.left",
          "j" => "cursor.down",
          "k" => "cursor.up",
          "l" => "cursor.right",
          "0" => "cursor.line_start",
          "$" => "cursor.line_end",
          "^" => "cursor.first_nonblank",
          "w" => "cursor.word_forward",
          "b" => "cursor.word_backward",
          "e" => "cursor.word_end",
          "G" => "cursor.buffer_end"
        }[token]

        if token == "g"
          @pending_keys ||= []
          @pending_keys << token
          arm_pending_key_timeout
          return
        end

        if @pending_keys == ["g"] && token == "g"
          id = "cursor.buffer_start"
        end

        if id
          clear_pending_key_timeout
          count = @editor.pending_count
          @dispatcher.dispatch(@editor, CommandInvocation.new(id:, count: count))
        else
          clear_pending_key_timeout
          @editor.echo_error("Unknown visual key: #{token}")
        end
      ensure
        @pending_keys = [] unless token == "g"
      end

      # --- Command-line mode ---

      def handle_command_line_key(key)
        cmd = @editor.command_line
        case key
        when :escape
          @completion.clear_command_line_completion
          @completion.cancel_incsearch_preview_if_any
          @editor.cancel_command_line
        when :enter
          @completion.clear_command_line_completion
          line = cmd.text.dup
          @completion.push_history(cmd.prefix, line)
          handle_command_line_submit(cmd.prefix, line)
        when :backspace
          @completion.clear_command_line_completion
          if cmd.text.empty? && cmd.cursor.zero?
            @completion.cancel_incsearch_preview_if_any
            @editor.cancel_command_line
            return
          end
          cmd.backspace
        when :up
          @completion.clear_command_line_completion
          @completion.history_move(-1)
        when :down
          @completion.clear_command_line_completion
          @completion.history_move(1)
        when :left
          @completion.clear_command_line_completion
          cmd.move_left
        when :right
          @completion.clear_command_line_completion
          cmd.move_right
        else
          if key == :ctrl_i
            @completion.command_line_complete
          elsif key.is_a?(String)
            @completion.clear_command_line_completion
            @completion.reset_history_index!
            cmd.insert(key)
          end
        end
        @completion.update_incsearch_preview_if_needed
      end

      # --- Hit-enter, rich mode ---

      def handle_hit_enter_key(key)
        token = normalize_key_token(key)
        case token
        when ":"
          @editor.exit_hit_enter_mode
          @editor.enter_command_line_mode(":")
        when "/", "?"
          @editor.exit_hit_enter_mode
          @editor.enter_command_line_mode(token)
        else
          @editor.exit_hit_enter_mode
        end
      end

      def handle_rich_key(key)
        token = normalize_key_token(key)
        if token == "\e"
          RuVim::RichView.close!(@editor)
          return
        end

        handle_normal_key(key)
      end

      def rich_mode_block_command?(command_id)
        RICH_MODE_BLOCKED_COMMANDS.include?(command_id.to_s)
      end

      # --- Ctrl-C / suspend ---

      def handle_ctrl_c
        case @editor.mode
        when :hit_enter
          @editor.exit_hit_enter_mode
        when :insert
          finish_insert_change_group
          finish_dot_change_capture
          @completion.clear_insert_completion
          clear_pending_key_timeout
          @editor.enter_normal_mode
          @editor.echo("")
        when :command_line
          clear_pending_key_timeout
          @completion.cancel_incsearch_preview_if_any
          @editor.cancel_command_line
        when :visual_char, :visual_line, :visual_block
          @visual_pending = nil
          @register_pending = false
          @mark_pending = false
          @jump_pending = nil
          clear_pending_key_timeout
          @editor.enter_normal_mode
        when :rich
          clear_pending_key_timeout
          @editor.pending_count = nil
          @pending_keys = []
          @operator_pending = nil
          @replace_pending = nil
          @register_pending = false
          @mark_pending = false
          @jump_pending = nil
          @macro_record_pending = false
          @macro_play_pending = false
          RuVim::RichView.close!(@editor)
        else
          clear_pending_key_timeout
          @editor.pending_count = nil
          @pending_keys = []
          @operator_pending = nil
          @replace_pending = nil
          @register_pending = false
          @mark_pending = false
          @jump_pending = nil
          @macro_record_pending = false
          @macro_play_pending = false
          @editor.clear_message
        end
      end

      def suspend_to_shell
        handler = @editor.suspend_handler
        handler&.call
      rescue StandardError => e
        @editor.echo_error("suspend failed: #{e.message}")
      end

      # --- Command-line submit ---

      def handle_command_line_submit(prefix, line)
        @completion.clear_incsearch_preview_state(apply: false) if %w[/ ?].include?(prefix)
        case prefix
        when ":"
          @dispatcher.dispatch_ex(@editor, line)
        when "/"
          submit_search(line, direction: :forward)
        when "?"
          submit_search(line, direction: :backward)
        else
          @editor.echo_error("Unknown command-line prefix: #{prefix}")
          @editor.enter_normal_mode
        end
        @completion.reset_history_index!
      end

      # --- List/quickfix/filter enter handlers ---

      def handle_list_window_enter
        buffer = @editor.current_buffer
        return handle_filter_buffer_enter if buffer.kind == :filter
        return handle_git_status_enter if buffer.kind == :git_status
        return handle_git_diff_enter if buffer.kind == :git_diff || buffer.kind == :git_log
        return handle_git_grep_enter if buffer.kind == :git_grep
        return handle_git_branch_enter if buffer.kind == :git_branch
        return false unless buffer.kind == :quickfix || buffer.kind == :location_list

        item_index = @editor.current_window.cursor_y - 2
        if item_index.negative?
          @editor.echo_error("No list item on this line")
          return true
        end

        source_window_id = buffer.options["ruvim_list_source_window_id"]
        source_window_id = source_window_id.to_i if source_window_id
        source_window_id = nil unless source_window_id && @editor.windows.key?(source_window_id)

        item =
          if buffer.kind == :quickfix
            @editor.select_quickfix(item_index)
          else
            owner_window_id = source_window_id || @editor.current_window_id
            @editor.select_location_list(item_index, window_id: owner_window_id)
          end

        unless item
          @editor.echo_error("#{buffer.kind == :quickfix ? 'quickfix' : 'location list'} item not found")
          return true
        end

        if source_window_id
          @editor.current_window_id = source_window_id
        end
        @editor.jump_to_location(item)
        @editor.echo(
          if buffer.kind == :quickfix
            "qf #{@editor.quickfix_index.to_i + 1}/#{@editor.quickfix_items.length}"
          else
            owner_window_id = source_window_id || @editor.current_window_id
            list = @editor.location_list(owner_window_id)
            "ll #{list[:index].to_i + 1}/#{list[:items].length}"
          end
        )
        true
      end

      def handle_filter_buffer_enter
        buffer = @editor.current_buffer
        origins = buffer.options["filter_origins"]
        return false unless origins

        row = @editor.current_window.cursor_y
        origin = origins[row]
        unless origin
          @editor.echo_error("No filter item on this line")
          return true
        end

        target_buffer_id = origin[:buffer_id]
        target_row = origin[:row]
        filter_buf_id = buffer.id

        @editor.delete_buffer(filter_buf_id)
        target_buf = @editor.buffers[target_buffer_id]
        if target_buf
          @editor.switch_to_buffer(target_buffer_id) unless @editor.current_buffer.id == target_buffer_id
          @editor.current_window.cursor_y = [target_row, target_buf.lines.length - 1].min
          @editor.current_window.cursor_x = 0
        end
        true
      end

      def handle_git_status_enter
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "git.status.open_file"))
        true
      end

      def handle_git_diff_enter
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "git.diff.open_file"))
        true
      end

      def handle_git_grep_enter
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "git.grep.open_file"))
        true
      end

      def handle_git_branch_enter
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "git.branch.checkout"))
        true
      end

      # --- Key helpers ---

      def arrow_key?(key)
        %i[left right up down].include?(key)
      end

      def paging_key?(key)
        %i[pageup pagedown].include?(key)
      end

      def invoke_arrow(key)
        id = {
          left: "cursor.left",
          right: "cursor.right",
          up: "cursor.up",
          down: "cursor.down"
        }.fetch(key)
        inv = CommandInvocation.new(id:, count: @editor.pending_count)
        @dispatcher.dispatch(@editor, inv)
        @editor.pending_count = nil
        @pending_keys = []
      end

      def invoke_page_key(key)
        id = (key == :pageup ? "cursor.page_up" : "cursor.page_down")
        inv = CommandInvocation.new(
          id: id,
          count: @editor.pending_count,
          kwargs: { page_lines: current_page_step_lines }
        )
        @dispatcher.dispatch(@editor, inv)
        @editor.pending_count = nil
        @pending_keys = []
      end

      def digit_key?(key)
        key.is_a?(String) && key.match?(/\A\d\z/)
      end

      def count_digit_allowed?(key)
        return false unless @editor.mode == :normal
        return true unless @editor.pending_count.nil?

        key != "0"
      end

      def normalize_key_token(key)
        case key
        when String then key
        when :escape then "\e"
        when :ctrl_r then "<C-r>"
        when :ctrl_d then "<C-d>"
        when :ctrl_u then "<C-u>"
        when :ctrl_f then "<C-f>"
        when :ctrl_b then "<C-b>"
        when :ctrl_e then "<C-e>"
        when :ctrl_y then "<C-y>"
        when :ctrl_v then "<C-v>"
        when :ctrl_i then "<C-i>"
        when :ctrl_o then "<C-o>"
        when :ctrl_w then "<C-w>"
        when :ctrl_l then "<C-l>"
        when :ctrl_c then "<C-c>"
        when :ctrl_g then "<C-g>"
        when :left then "<Left>"
        when :right then "<Right>"
        when :up then "<Up>"
        when :down then "<Down>"
        when :home then "<Home>"
        when :end then "<End>"
        when :pageup then "<PageUp>"
        when :pagedown then "<PageDown>"
        when :shift_up then "<S-Up>"
        when :shift_down then "<S-Down>"
        when :shift_left then "<S-Left>"
        when :shift_right then "<S-Right>"
        else nil
        end
      end

      def dup_invocation(inv)
        CommandInvocation.new(
          id: inv.id,
          argv: inv.argv.dup,
          kwargs: inv.kwargs.dup,
          count: inv.count,
          bang: inv.bang,
          raw_keys: inv.raw_keys&.dup
        )
      end

      # --- Mode transition tracking ---

      def track_mode_transition(mode_before)
        mode_after = @editor.mode
        if mode_before != :insert && mode_after == :insert
          @insert_start_location = @editor.current_location
        elsif mode_before == :insert && mode_after != :insert
          @insert_start_location = nil
        end

        if mode_before != :command_line && mode_after == :command_line
          @completion.clear_incsearch_preview_state(apply: false) rescue nil
        end
      end

      def submit_search(line, direction:)
        inv = CommandInvocation.new(id: "__search_submit__", argv: [line], kwargs: { pattern: line, direction: direction })
        ctx = Context.new(editor: @editor, invocation: inv)
        GlobalCommands.instance.submit_search(ctx, pattern: line, direction: direction)
        @editor.enter_normal_mode
      rescue StandardError => e
        @editor.echo_error("Error: #{e.message}")
        @editor.enter_normal_mode
      end
  end
end
