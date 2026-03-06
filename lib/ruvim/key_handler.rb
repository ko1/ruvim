# frozen_string_literal: true

module RuVim
  class KeyHandler
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

      def initialize(editor:, dispatcher:, keymaps:, terminal:, screen:, completion:, stream_handler:)
        @editor = editor
        @dispatcher = dispatcher
        @keymaps = keymaps
        @terminal = terminal
        @screen = screen
        @completion = completion
        @stream_handler = stream_handler

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
          case name.to_sym
          when :normal_operator_start
            op = (kwargs[:name] || kwargs["name"]).to_sym
            return if op == :delete || op == :change
          when :normal_replace_pending_start, :normal_change_repeat
            return
          end
        end

        case name.to_sym
        when :normal_register_pending_start
          start_register_pending
        when :normal_operator_start
          start_operator_pending((kwargs[:name] || kwargs["name"]).to_sym)
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
          @stream_handler.ex_follow_toggle
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
        if buf && @stream_handler.follow_watchers[buf.id]
          @stream_handler.stop_follow!(buf)
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
        match = @keymaps.resolve_with_context(:normal, @pending_keys, editor: @editor)
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

      # --- Insert mode ---

      def handle_insert_key(key)
        case key
        when :escape
          finish_insert_change_group
          finish_dot_change_capture
          @completion.clear_insert_completion
          @editor.enter_normal_mode
          @editor.echo("")
        when :backspace
          @completion.clear_insert_completion
          return unless insert_backspace_allowed?
          insert_backspace_in_insert_mode
        when :ctrl_n
          @completion.insert_complete(+1)
        when :ctrl_p
          @completion.insert_complete(-1)
        when :ctrl_i
          @completion.clear_insert_completion
          insert_tab_in_insert_mode
        when :enter
          @completion.clear_insert_completion
          y, x = @editor.current_buffer.insert_newline(@editor.current_window.cursor_y, @editor.current_window.cursor_x)
          x = apply_insert_autoindent(y, x, previous_row: y - 1)
          @editor.current_window.cursor_y = y
          @editor.current_window.cursor_x = x
        when :left
          @completion.clear_insert_completion
          dispatch_insert_cursor_motion("cursor.left")
        when :right
          @completion.clear_insert_completion
          dispatch_insert_cursor_motion("cursor.right")
        when :up
          @completion.clear_insert_completion
          @editor.current_window.move_up(@editor.current_buffer, 1)
        when :down
          @completion.clear_insert_completion
          @editor.current_window.move_down(@editor.current_buffer, 1)
        when :pageup, :pagedown
          @completion.clear_insert_completion
          invoke_page_key(key)
        else
          return unless key.is_a?(String)

          @completion.clear_insert_completion
          @editor.current_buffer.insert_char(@editor.current_window.cursor_y, @editor.current_window.cursor_x, key)
          @editor.current_window.cursor_x += 1
          maybe_showmatch_after_insert(key)
          maybe_dedent_after_insert(key)
        end
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
        @terminal.suspend_for_tstp
        @screen.invalidate_cache! if @screen.respond_to?(:invalidate_cache!)
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

      def finish_insert_change_group
        @editor.current_buffer.end_change_group
      end

      # --- Insert editing helpers ---

      def insert_backspace_allowed?
        buf = @editor.current_buffer
        win = @editor.current_window
        row = win.cursor_y
        col = win.cursor_x
        return false if row.zero? && col.zero?

        opt = @editor.effective_option("backspace", window: win, buffer: buf).to_s
        allow = opt.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
        allow_all = allow.include?("2")
        allow_indent = allow_all || allow.include?("indent")

        if col.zero? && row.positive?
          return true if allow_all || allow.include?("eol")

          @editor.echo_error("backspace=eol required")
          return false
        end

        if @insert_start_location
          same_buf = @insert_start_location[:buffer_id] == buf.id
          if same_buf && (row < @insert_start_location[:row] || (row == @insert_start_location[:row] && col <= @insert_start_location[:col]))
            if allow_all || allow.include?("start")
              return true
            end

            if allow_indent && same_row_autoindent_backspace?(buf, row, col)
              return true
            end

            @editor.echo_error("backspace=start required")
            return false
          end
        end

        true
      end

      def insert_backspace_in_insert_mode
        buf = @editor.current_buffer
        win = @editor.current_window
        row = win.cursor_y
        col = win.cursor_x

        if row >= 0 && col.positive? && try_softtabstop_backspace(buf, win)
          return
        end

        y, x = buf.backspace(row, col)
        win.cursor_y = y
        win.cursor_x = x
      end

      def dispatch_insert_cursor_motion(id)
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: id, count: 1))
      rescue StandardError => e
        @editor.echo_error("Motion error: #{e.message}")
      end

      def try_softtabstop_backspace(buf, win)
        row = win.cursor_y
        col = win.cursor_x
        line = buf.line_at(row)
        return false unless line
        return false unless @editor.effective_option("expandtab", window: win, buffer: buf)

        sts = @editor.effective_option("softtabstop", window: win, buffer: buf).to_i
        sts = @editor.effective_option("tabstop", window: win, buffer: buf).to_i if sts <= 0
        return false if sts <= 0

        prefix = line[0...col].to_s
        m = prefix.match(/ +\z/)
        return false unless m

        run = m[0].length
        return false if run <= 1

        tabstop = effective_tabstop(win, buf)
        cur_screen = RuVim::TextMetrics.screen_col_for_char_index(line, col, tabstop:)
        target_screen = [cur_screen - sts, 0].max
        target_col = RuVim::TextMetrics.char_index_for_screen_col(line, target_screen, tabstop:, align: :floor)
        delete_cols = col - target_col
        delete_cols = [delete_cols, run, sts].min
        return false if delete_cols <= 1

        run_start = col - run
        target_col = [target_col, run_start].max
        delete_cols = col - target_col
        return false if delete_cols <= 1

        buf.delete_span(row, target_col, row, col)
        win.cursor_x = target_col
        true
      rescue StandardError
        false
      end

      def same_row_autoindent_backspace?(buf, row, col)
        return false unless @insert_start_location
        return false unless row == @insert_start_location[:row]
        return false unless col <= @insert_start_location[:col]

        line = buf.line_at(row)
        line[0...@insert_start_location[:col]].to_s.match?(/\A[ \t]*\z/)
      rescue StandardError
        false
      end

      def insert_tab_in_insert_mode
        buf = @editor.current_buffer
        win = @editor.current_window
        if @editor.effective_option("expandtab", window: win, buffer: buf)
          width = @editor.effective_option("softtabstop", window: win, buffer: buf).to_i
          width = @editor.effective_option("tabstop", window: win, buffer: buf).to_i if width <= 0
          width = 2 if width <= 0
          line = buf.line_at(win.cursor_y)
          current_col = RuVim::TextMetrics.screen_col_for_char_index(line, win.cursor_x, tabstop: effective_tabstop(win, buf))
          spaces = width - (current_col % width)
          spaces = width if spaces <= 0
          _y, x = buf.insert_text(win.cursor_y, win.cursor_x, " " * spaces)
          win.cursor_x = x
        else
          buf.insert_char(win.cursor_y, win.cursor_x, "\t")
          win.cursor_x += 1
        end
      end

      def apply_insert_autoindent(row, x, previous_row:)
        return x if @paste_batch
        buf = @editor.current_buffer
        win = @editor.current_window
        return x unless @editor.effective_option("autoindent", window: win, buffer: buf)
        return x if previous_row.negative?

        prev = buf.line_at(previous_row)
        indent = prev[/\A[ \t]*/].to_s
        if @editor.effective_option("smartindent", window: win, buffer: buf)
          trimmed = prev.rstrip
          needs_indent = trimmed.end_with?("{", "[", "(")
          if !needs_indent
            needs_indent = buf.lang_module.indent_trigger?(trimmed)
          end
          if needs_indent
            sw = @editor.effective_option("shiftwidth", window: win, buffer: buf).to_i
            sw = effective_tabstop(win, buf) if sw <= 0
            sw = 2 if sw <= 0
            indent += " " * sw
          end
        end
        return x if indent.empty?

        _y, new_x = buf.insert_text(row, x, indent)
        new_x
      end

      def maybe_showmatch_after_insert(key)
        return unless [")", "]", "}"].include?(key)
        return unless @editor.effective_option("showmatch")

        mt = @editor.effective_option("matchtime").to_i
        mt = 5 if mt <= 0
        @editor.echo_temporary("match", duration_seconds: mt * 0.1)
      end

      def maybe_dedent_after_insert(key)
        return unless @editor.effective_option("smartindent", window: @editor.current_window, buffer: @editor.current_buffer)

        buf = @editor.current_buffer
        lang_mod = buf.lang_module

        pattern = lang_mod.dedent_trigger(key)
        return unless pattern

        row = @editor.current_window.cursor_y
        line = buf.line_at(row)
        m = line.match(pattern)
        return unless m

        sw = @editor.effective_option("shiftwidth", buffer: buf).to_i
        sw = 2 if sw <= 0
        target_indent = lang_mod.calculate_indent(buf.lines, row, sw)
        return unless target_indent

        current_indent = m[1].length
        return if current_indent == target_indent

        stripped = line.to_s.strip
        buf.delete_span(row, 0, row, current_indent) if current_indent > 0
        buf.insert_text(row, 0, " " * target_indent) if target_indent > 0
        @editor.current_window.cursor_x = target_indent + stripped.length
      end

      def effective_tabstop(window = @editor.current_window, buffer = @editor.current_buffer)
        v = @editor.effective_option("tabstop", window:, buffer:).to_i
        v.positive? ? v : 2
      end

      # --- Operator pending ---

      def start_operator_pending(name)
        @operator_pending = { name:, count: @editor.pending_count }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo(name == :delete ? "d" : name.to_s)
      end

      def handle_operator_pending_key(token)
        op = @operator_pending
        if %w[i a g].include?(token) && !op[:motion_prefix]
          @operator_pending[:motion_prefix] = token
          @editor.echo("#{op[:name].to_s[0]}#{token}")
          return
        end

        motion = [op[:motion_prefix], token].compact.join
        @operator_pending = nil

        if token == "\e"
          @editor.clear_message
          return
        end

        if op[:name] == :delete && motion == "d"
          inv = CommandInvocation.new(id: "buffer.delete_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(op[:count], ["d", "d"]))
          return
        end

        if op[:name] == :delete
          inv = CommandInvocation.new(id: "buffer.delete_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(op[:count], ["d", *motion.each_char.to_a]))
          return
        end

        if op[:name] == :yank && motion == "y"
          inv = CommandInvocation.new(id: "buffer.yank_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :yank
          inv = CommandInvocation.new(id: "buffer.yank_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :indent && motion == "="
          inv = CommandInvocation.new(id: "buffer.indent_lines", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :indent
          inv = CommandInvocation.new(id: "buffer.indent_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :change && motion == "c"
          inv = CommandInvocation.new(id: "buffer.change_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          begin_dot_change_capture(count_prefixed_keys(op[:count], ["c", "c"])) if @editor.mode == :insert
          return
        end

        if op[:name] == :change
          inv = CommandInvocation.new(id: "buffer.change_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          begin_dot_change_capture(count_prefixed_keys(op[:count], ["c", *motion.each_char.to_a])) if @editor.mode == :insert
          return
        end

        @editor.echo_error("Unknown operator")
      end

      # --- Register / mark / jump pending ---

      def start_register_pending
        @register_pending = true
        @editor.echo('"')
      end

      def finish_register_pending(token)
        @register_pending = false
        if token.is_a?(String) && token.length == 1
          @editor.set_active_register(token)
          @editor.echo(%("#{token}))
        else
          @editor.echo_error("Invalid register")
        end
      end

      def start_mark_pending
        @mark_pending = true
        @editor.echo("m")
      end

      def finish_mark_pending(token)
        @mark_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && token.match?(/\A[A-Za-z]\z/)
          @editor.echo_error("Invalid mark")
          return
        end

        inv = CommandInvocation.new(id: "mark.set", kwargs: { mark: token })
        @dispatcher.dispatch(@editor, inv)
      end

      def start_jump_pending(linewise:, repeat_token:)
        @jump_pending = { linewise: linewise, repeat_token: repeat_token }
        @editor.echo(repeat_token)
      end

      def finish_jump_pending(token)
        pending = @jump_pending
        @jump_pending = nil
        return unless pending
        if token == "\e"
          @editor.clear_message
          return
        end

        if token == pending[:repeat_token]
          inv = CommandInvocation.new(id: "jump.older", kwargs: { linewise: pending[:linewise] })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        unless token.is_a?(String) && token.match?(/\A[A-Za-z]\z/)
          @editor.echo_error("Invalid mark")
          return
        end

        inv = CommandInvocation.new(id: "mark.jump", kwargs: { mark: token, linewise: pending[:linewise] })
        @dispatcher.dispatch(@editor, inv)
      end

      # --- Replace pending ---

      def start_replace_pending
        @replace_pending = { count: @editor.pending_count }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo("r")
      end

      def handle_replace_pending_key(token)
        pending = @replace_pending
        @replace_pending = nil
        if token == "\e"
          @editor.clear_message
          return
        end

        if token.is_a?(String) && !token.empty?
          inv = CommandInvocation.new(id: "buffer.replace_char", argv: [token], count: pending[:count])
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(pending[:count], ["r", token]))
        else
          @editor.echo("r expects one character")
        end
      end

      # --- Macro recording / playback ---

      def start_macro_record_pending
        @macro_record_pending = true
        @editor.echo("q")
      end

      def toggle_macro_recording_or_start_pending
        if @editor.macro_recording?
          stop_macro_recording
        else
          start_macro_record_pending
        end
      end

      def finish_macro_record_pending(token)
        @macro_record_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9]\z/)
          @editor.echo_error("Invalid macro register")
          return
        end

        unless @editor.start_macro_recording(token)
          @editor.echo("Failed to start recording")
          return
        end
        @skip_record_for_current_key = true
        @editor.echo("recording @#{token}")
      end

      def stop_macro_recording
        reg = @editor.macro_recording_name
        @editor.stop_macro_recording
        @editor.echo("recording @#{reg} stopped")
      end

      def start_macro_play_pending
        @macro_play_pending = true
        @editor.echo("@")
      end

      def finish_macro_play_pending(token)
        @macro_play_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        name =
          if token == "@"
            @last_macro_name
          elsif token.is_a?(String) && token.match?(/\A[A-Za-z0-9]\z/)
            token
          end
        unless name
          @editor.echo_error("Invalid macro register")
          return
        end

        count = @editor.pending_count
        @editor.pending_count = nil
        play_macro(name, count:)
      end

      def play_macro(name, count:)
        reg = name.to_s.downcase
        keys = @editor.macro_keys(reg)
        if keys.nil? || keys.empty?
          @editor.echo("Macro empty: #{reg}")
          return
        end

        @macro_play_stack ||= []
        if @macro_play_stack.include?(reg) || @macro_play_stack.length >= 20
          @editor.echo("Macro recursion blocked: #{reg}")
          return
        end

        @last_macro_name = reg
        @macro_play_stack << reg
        @suspend_macro_recording_depth = (@suspend_macro_recording_depth || 0) + 1
        [count.to_i, 1].max.times do
          keys.each { |k| handle(dup_macro_runtime_key(k)) }
        end
        @editor.echo("@#{reg}")
      ensure
        @suspend_macro_recording_depth = [(@suspend_macro_recording_depth || 1) - 1, 0].max
        @macro_play_stack.pop if @macro_play_stack && !@macro_play_stack.empty?
      end

      def record_macro_key_if_needed(key)
        return if @skip_record_for_current_key
        return unless @editor.macro_recording?
        return if (@suspend_macro_recording_depth || 0).positive?
        return if (@dot_replay_depth || 0).positive?

        @editor.record_macro_key(key)
      end

      def dup_macro_runtime_key(key)
        case key
        when String
          key.dup
        when Array
          key.map { |v| v.is_a?(String) ? v.dup : v }
        else
          key
        end
      end

      # --- Dot repeat ---

      def repeat_last_change
        keys = @last_change_keys
        if keys.nil? || keys.empty?
          @editor.echo("No previous change")
          return
        end

        @dot_replay_depth = (@dot_replay_depth || 0) + 1
        keys.each { |k| handle(dup_macro_runtime_key(k)) }
        @editor.echo(".")
      ensure
        @dot_replay_depth = [(@dot_replay_depth || 1) - 1, 0].max
      end

      def maybe_record_simple_dot_change(invocation, matched_keys, count)
        return if (@dot_replay_depth || 0).positive?

        case invocation.id
        when "buffer.delete_char", "buffer.delete_motion", "buffer.join_lines", "buffer.swapcase_char", "buffer.paste_after", "buffer.paste_before"
          record_last_change_keys(count_prefixed_keys(count, matched_keys))
        when "mode.insert", "mode.append", "mode.append_line_end", "mode.insert_nonblank", "mode.open_below", "mode.open_above", "buffer.substitute_char", "buffer.change_motion", "buffer.change_line"
          begin_dot_change_capture(count_prefixed_keys(count, matched_keys)) if @editor.mode == :insert
        end
      end

      def begin_dot_change_capture(prefix_keys)
        return if (@dot_replay_depth || 0).positive?

        @dot_change_capture_keys = Array(prefix_keys).map { |k| dup_macro_runtime_key(k) }
        @dot_change_capture_active = true
      end

      def append_dot_change_capture_key(key)
        return unless @dot_change_capture_active
        return if (@dot_replay_depth || 0).positive?

        @dot_change_capture_keys ||= []
        @dot_change_capture_keys << dup_macro_runtime_key(key)
      end

      def finish_dot_change_capture
        return unless @dot_change_capture_active

        keys = Array(@dot_change_capture_keys)
        @dot_change_capture_active = false
        @dot_change_capture_keys = nil
        record_last_change_keys(keys)
      end

      def record_last_change_keys(keys)
        return if (@dot_replay_depth || 0).positive?

        @last_change_keys = Array(keys).map { |k| dup_macro_runtime_key(k) }
      end

      def count_prefixed_keys(count, keys)
        c = count.to_i
        prefix = c > 1 ? c.to_s.each_char.to_a : []
        prefix + Array(keys)
      end

      # --- Find character on line ---

      def start_find_pending(token)
        @find_pending = {
          direction: (token == "f" || token == "t") ? :forward : :backward,
          till: (token == "t" || token == "T"),
          count: @editor.pending_count
        }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo(token)
      end

      def finish_find_pending(token)
        pending = @find_pending
        @find_pending = nil
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && !token.empty?
          @editor.echo("find expects one character")
          return
        end

        moved = perform_find_on_line(
          char: token,
          direction: pending[:direction],
          till: pending[:till],
          count: pending[:count]
        )
        if moved
          @editor.set_last_find(char: token, direction: pending[:direction], till: pending[:till])
        else
          @editor.echo("Char not found: #{token}")
        end
      end

      def repeat_last_find(reverse:)
        last = @editor.last_find
        unless last
          @editor.echo("No previous f/t")
          return
        end

        direction =
          if reverse
            last[:direction] == :forward ? :backward : :forward
          else
            last[:direction]
          end
        count = @editor.pending_count
        @editor.pending_count = nil
        @pending_keys = []
        moved = perform_find_on_line(char: last[:char], direction:, till: last[:till], count:)
        @editor.echo("Char not found: #{last[:char]}") unless moved
      end

      def perform_find_on_line(char:, direction:, till:, count:)
        win = @editor.current_window
        buf = @editor.current_buffer
        line = buf.line_at(win.cursor_y)
        pos = win.cursor_x
        target = nil

        [count.to_i, 1].max.times do
          idx =
            if direction == :forward
              line.index(char, pos + 1)
            else
              rindex_from(line, char, pos - 1)
            end
          return false if idx.nil?

          target = idx
          pos = idx
        end

        if till
          target =
            if direction == :forward
              RuVim::TextMetrics.previous_grapheme_char_index(line, target)
            else
              RuVim::TextMetrics.next_grapheme_char_index(line, target)
            end
        end

        win.cursor_x = target
        win.clamp_to_buffer(buf)
        true
      end

      def rindex_from(line, char, pos)
        return nil if pos.negative?

        line.rindex(char, pos)
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

