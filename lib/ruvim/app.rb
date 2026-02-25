module RuVim
  class App
    def initialize(path: nil, paths: nil, stdin: STDIN, stdout: STDOUT, startup_actions: [], clean: false, skip_user_config: false, config_path: nil, readonly: false, nomodifiable: false, startup_open_layout: nil, startup_open_count: nil)
      @editor = Editor.new
      @terminal = Terminal.new(stdin:, stdout:)
      @input = Input.new(stdin:)
      @screen = Screen.new(terminal: @terminal)
      @dispatcher = Dispatcher.new
      @keymaps = KeymapManager.new
      @signal_r, @signal_w = IO.pipe
      @cmdline_history = Hash.new { |h, k| h[k] = [] }
      @cmdline_history_index = nil
      @needs_redraw = true
      @clean_mode = clean
      @skip_user_config = skip_user_config
      @config_path = config_path
      @startup_readonly = readonly
      @startup_nomodifiable = nomodifiable
      @startup_open_layout = startup_open_layout
      @startup_open_count = startup_open_count

      register_builtins!
      bind_default_keys!
      init_config_loader!
      load_user_config!
      install_signal_handlers

      @editor.ensure_bootstrap_buffer!
      startup_paths = Array(paths || path).compact
      if startup_paths.empty?
        @editor.show_intro_buffer_if_applicable!
      else
        open_startup_paths!(startup_paths)
      end
      load_current_ftplugin!
      run_startup_actions!(startup_actions)
    end

    def run
      @terminal.with_ui do
        loop do
          if @needs_redraw
            @screen.render(@editor)
            @needs_redraw = false
          end
          break unless @editor.running?

          key = @input.read_key(wakeup_ios: [@signal_r])
          next if key.nil?

          handle_key(key)
          @needs_redraw = true
        end
      end
    end

    def run_startup_actions!(actions)
      Array(actions).each do |action|
        run_startup_action!(action)
        break unless @editor.running?
      end
    end

    private

    def register_builtins!
      cmd = CommandRegistry.instance
      ex = ExCommandRegistry.instance

      register_internal_unless(cmd, "cursor.left", call: :cursor_left, desc: "Move cursor left")
      register_internal_unless(cmd, "cursor.right", call: :cursor_right, desc: "Move cursor right")
      register_internal_unless(cmd, "cursor.up", call: :cursor_up, desc: "Move cursor up")
      register_internal_unless(cmd, "cursor.down", call: :cursor_down, desc: "Move cursor down")
      register_internal_unless(cmd, "cursor.line_start", call: :cursor_line_start, desc: "Move to column 1")
      register_internal_unless(cmd, "cursor.line_end", call: :cursor_line_end, desc: "Move to end of line")
      register_internal_unless(cmd, "cursor.first_nonblank", call: :cursor_first_nonblank, desc: "Move to first nonblank")
      register_internal_unless(cmd, "cursor.buffer_start", call: :cursor_buffer_start, desc: "Move to start of buffer")
      register_internal_unless(cmd, "cursor.buffer_end", call: :cursor_buffer_end, desc: "Move to end of buffer")
      register_internal_unless(cmd, "cursor.word_forward", call: :cursor_word_forward, desc: "Move to next word")
      register_internal_unless(cmd, "cursor.word_backward", call: :cursor_word_backward, desc: "Move to previous word")
      register_internal_unless(cmd, "cursor.word_end", call: :cursor_word_end, desc: "Move to end of word")
      register_internal_unless(cmd, "cursor.match_bracket", call: :cursor_match_bracket, desc: "Jump to matching bracket")
      register_internal_unless(cmd, "mode.insert", call: :enter_insert_mode, desc: "Enter insert mode")
      register_internal_unless(cmd, "mode.append", call: :append_mode, desc: "Append after cursor")
      register_internal_unless(cmd, "mode.append_line_end", call: :append_line_end_mode, desc: "Append at line end")
      register_internal_unless(cmd, "mode.insert_nonblank", call: :insert_line_start_nonblank_mode, desc: "Insert at first nonblank")
      register_internal_unless(cmd, "mode.open_below", call: :open_line_below, desc: "Open line below")
      register_internal_unless(cmd, "mode.open_above", call: :open_line_above, desc: "Open line above")
      register_internal_unless(cmd, "mode.visual_char", call: :enter_visual_char_mode, desc: "Enter visual char mode")
      register_internal_unless(cmd, "mode.visual_line", call: :enter_visual_line_mode, desc: "Enter visual line mode")
      register_internal_unless(cmd, "window.split", call: :window_split, desc: "Horizontal split")
      register_internal_unless(cmd, "window.vsplit", call: :window_vsplit, desc: "Vertical split")
      register_internal_unless(cmd, "window.focus_next", call: :window_focus_next, desc: "Next window")
      register_internal_unless(cmd, "window.focus_left", call: :window_focus_left, desc: "Focus left window")
      register_internal_unless(cmd, "window.focus_right", call: :window_focus_right, desc: "Focus right window")
      register_internal_unless(cmd, "window.focus_up", call: :window_focus_up, desc: "Focus upper window")
      register_internal_unless(cmd, "window.focus_down", call: :window_focus_down, desc: "Focus lower window")
      register_internal_unless(cmd, "mode.command_line", call: :enter_command_line_mode, desc: "Enter command-line mode")
      register_internal_unless(cmd, "mode.search_forward", call: :enter_search_forward_mode, desc: "Enter / search")
      register_internal_unless(cmd, "mode.search_backward", call: :enter_search_backward_mode, desc: "Enter ? search")
      register_internal_unless(cmd, "buffer.delete_char", call: :delete_char, desc: "Delete char under cursor")
      register_internal_unless(cmd, "buffer.delete_line", call: :delete_line, desc: "Delete current line")
      register_internal_unless(cmd, "buffer.delete_motion", call: :delete_motion, desc: "Delete by motion")
      register_internal_unless(cmd, "buffer.change_motion", call: :change_motion, desc: "Change by motion")
      register_internal_unless(cmd, "buffer.change_line", call: :change_line, desc: "Change line(s)")
      register_internal_unless(cmd, "buffer.yank_line", call: :yank_line, desc: "Yank line(s)")
      register_internal_unless(cmd, "buffer.yank_motion", call: :yank_motion, desc: "Yank by motion")
      register_internal_unless(cmd, "buffer.paste_after", call: :paste_after, desc: "Paste after")
      register_internal_unless(cmd, "buffer.paste_before", call: :paste_before, desc: "Paste before")
      register_internal_unless(cmd, "buffer.visual_yank", call: :visual_yank, desc: "Yank visual selection")
      register_internal_unless(cmd, "buffer.visual_delete", call: :visual_delete, desc: "Delete visual selection")
      register_internal_unless(cmd, "buffer.visual_select_text_object", call: :visual_select_text_object, desc: "Select visual text object")
      register_internal_unless(cmd, "buffer.undo", call: :buffer_undo, desc: "Undo")
      register_internal_unless(cmd, "buffer.redo", call: :buffer_redo, desc: "Redo")
      register_internal_unless(cmd, "search.next", call: :search_next, desc: "Repeat search")
      register_internal_unless(cmd, "search.prev", call: :search_prev, desc: "Repeat search backward")
      register_internal_unless(cmd, "search.word_forward", call: :search_word_forward, desc: "Search word forward")
      register_internal_unless(cmd, "search.word_backward", call: :search_word_backward, desc: "Search word backward")
      register_internal_unless(cmd, "search.word_forward_partial", call: :search_word_forward_partial, desc: "Search partial word forward")
      register_internal_unless(cmd, "search.word_backward_partial", call: :search_word_backward_partial, desc: "Search partial word backward")
      register_internal_unless(cmd, "mark.set", call: :mark_set, desc: "Set mark")
      register_internal_unless(cmd, "mark.jump", call: :mark_jump, desc: "Jump to mark")
      register_internal_unless(cmd, "jump.older", call: :jump_older, desc: "Jump older")
      register_internal_unless(cmd, "jump.newer", call: :jump_newer, desc: "Jump newer")
      register_internal_unless(cmd, "editor.buffer_next", call: :buffer_next, desc: "Next buffer")
      register_internal_unless(cmd, "editor.buffer_prev", call: :buffer_prev, desc: "Previous buffer")
      register_internal_unless(cmd, "buffer.replace_char", call: :replace_char, desc: "Replace single char")
      register_internal_unless(cmd, "ui.clear_message", call: :clear_message, desc: "Clear message")

      register_ex_unless(ex, "w", call: :file_write, aliases: %w[write], desc: "Write current buffer", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "q", call: :app_quit, aliases: %w[quit], desc: "Quit", nargs: 0, bang: true)
      register_ex_unless(ex, "wq", call: :file_write_quit, desc: "Write and quit", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "e", call: :file_edit, aliases: %w[edit], desc: "Edit file / reload", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "help", call: :ex_help, desc: "Show help / topics", nargs: :any)
      register_ex_unless(ex, "command", call: :ex_define_command, desc: "Define user command", nargs: :any, bang: true)
      register_ex_unless(ex, "ruby", call: :ex_ruby, aliases: %w[rb], desc: "Evaluate Ruby", nargs: :any, bang: false)
      register_ex_unless(ex, "ls", call: :buffer_list, aliases: %w[buffers], desc: "List buffers", nargs: 0)
      register_ex_unless(ex, "bnext", call: :buffer_next, aliases: %w[bn], desc: "Next buffer", nargs: 0, bang: true)
      register_ex_unless(ex, "bprev", call: :buffer_prev, aliases: %w[bp], desc: "Previous buffer", nargs: 0, bang: true)
      register_ex_unless(ex, "buffer", call: :buffer_switch, aliases: %w[b], desc: "Switch buffer", nargs: 1, bang: true)
      register_ex_unless(ex, "commands", call: :ex_commands, desc: "List Ex commands", nargs: 0)
      register_ex_unless(ex, "set", call: :ex_set, desc: "Set options", nargs: :any)
      register_ex_unless(ex, "setlocal", call: :ex_setlocal, desc: "Set window/buffer local option", nargs: :any)
      register_ex_unless(ex, "setglobal", call: :ex_setglobal, desc: "Set global option", nargs: :any)
      register_ex_unless(ex, "split", call: :window_split, desc: "Horizontal split", nargs: 0)
      register_ex_unless(ex, "vsplit", call: :window_vsplit, desc: "Vertical split", nargs: 0)
      register_ex_unless(ex, "tabnew", call: :tab_new, desc: "New tab", nargs: :maybe_one)
      register_ex_unless(ex, "tabnext", call: :tab_next, aliases: %w[tabn], desc: "Next tab", nargs: 0)
      register_ex_unless(ex, "tabprev", call: :tab_prev, aliases: %w[tabp], desc: "Prev tab", nargs: 0)
    end

    def bind_default_keys!
      @keymaps.bind(:normal, "h", "cursor.left")
      @keymaps.bind(:normal, "j", "cursor.down")
      @keymaps.bind(:normal, "k", "cursor.up")
      @keymaps.bind(:normal, "l", "cursor.right")
      @keymaps.bind(:normal, "0", "cursor.line_start")
      @keymaps.bind(:normal, "$", "cursor.line_end")
      @keymaps.bind(:normal, "^", "cursor.first_nonblank")
      @keymaps.bind(:normal, "gg", "cursor.buffer_start")
      @keymaps.bind(:normal, "G", "cursor.buffer_end")
      @keymaps.bind(:normal, "w", "cursor.word_forward")
      @keymaps.bind(:normal, "b", "cursor.word_backward")
      @keymaps.bind(:normal, "e", "cursor.word_end")
      @keymaps.bind(:normal, "%", "cursor.match_bracket")
      @keymaps.bind(:normal, "i", "mode.insert")
      @keymaps.bind(:normal, "a", "mode.append")
      @keymaps.bind(:normal, "A", "mode.append_line_end")
      @keymaps.bind(:normal, "I", "mode.insert_nonblank")
      @keymaps.bind(:normal, "o", "mode.open_below")
      @keymaps.bind(:normal, "O", "mode.open_above")
      @keymaps.bind(:normal, "v", "mode.visual_char")
      @keymaps.bind(:normal, "V", "mode.visual_line")
      @keymaps.bind(:normal, ["<C-w>", "w"], "window.focus_next")
      @keymaps.bind(:normal, ["<C-w>", "h"], "window.focus_left")
      @keymaps.bind(:normal, ["<C-w>", "j"], "window.focus_down")
      @keymaps.bind(:normal, ["<C-w>", "k"], "window.focus_up")
      @keymaps.bind(:normal, ["<C-w>", "l"], "window.focus_right")
      @keymaps.bind(:normal, ":", "mode.command_line")
      @keymaps.bind(:normal, "/", "mode.search_forward")
      @keymaps.bind(:normal, "?", "mode.search_backward")
      @keymaps.bind(:normal, "x", "buffer.delete_char")
      @keymaps.bind(:normal, "p", "buffer.paste_after")
      @keymaps.bind(:normal, "P", "buffer.paste_before")
      @keymaps.bind(:normal, "u", "buffer.undo")
      @keymaps.bind(:normal, ["<C-r>"], "buffer.redo")
      @keymaps.bind(:normal, ["<C-o>"], "jump.older")
      @keymaps.bind(:normal, ["<C-i>"], "jump.newer")
      @keymaps.bind(:normal, "n", "search.next")
      @keymaps.bind(:normal, "N", "search.prev")
      @keymaps.bind(:normal, "*", "search.word_forward")
      @keymaps.bind(:normal, "#", "search.word_backward")
      @keymaps.bind(:normal, "g*", "search.word_forward_partial")
      @keymaps.bind(:normal, "g#", "search.word_backward_partial")
      @keymaps.bind(:normal, "\e", "ui.clear_message")
    end

    def handle_key(key)
      @skip_record_for_current_key = false
      if key == :ctrl_c
        handle_ctrl_c
        record_macro_key_if_needed(key)
        return
      end

      case @editor.mode
      when :insert
        handle_insert_key(key)
      when :command_line
        handle_command_line_key(key)
      when :visual_char, :visual_line
        handle_visual_key(key)
      else
        handle_normal_key(key)
      end
      load_current_ftplugin!
      record_macro_key_if_needed(key)
    end

    def handle_normal_key(key)
      if arrow_key?(key)
        invoke_arrow(key)
        return
      end

      if digit_key?(key) && count_digit_allowed?(key)
        @editor.pending_count = (@editor.pending_count.to_s + key).to_i
        @editor.echo(@editor.pending_count.to_s)
        @pending_keys = []
        return
      end

      token = normalize_key_token(key)
      return if token.nil?

      if @operator_pending
        handle_operator_pending_key(token)
        return
      end

      if @register_pending
        finish_register_pending(token)
        return
      end

      if @mark_pending
        finish_mark_pending(token)
        return
      end

      if @jump_pending
        finish_jump_pending(token)
        return
      end

      if @macro_record_pending
        finish_macro_record_pending(token)
        return
      end

      if @macro_play_pending
        finish_macro_play_pending(token)
        return
      end

      if @replace_pending
        handle_replace_pending_key(token)
        return
      end

      if @find_pending
        finish_find_pending(token)
        return
      end

      if token == "\""
        start_register_pending
        return
      end

      if token == "d"
        start_operator_pending(:delete)
        return
      end

      if token == "y"
        start_operator_pending(:yank)
        return
      end

      if token == "c"
        start_operator_pending(:change)
        return
      end

      if token == "r"
        start_replace_pending
        return
      end

      if %w[f F t T].include?(token)
        start_find_pending(token)
        return
      end

      if token == ";"
        repeat_last_find(reverse: false)
        return
      end

      if token == ","
        repeat_last_find(reverse: true)
        return
      end

      if token == "."
        repeat_last_change
        return
      end

      if token == "q"
        if @editor.macro_recording?
          stop_macro_recording
        else
          start_macro_record_pending
        end
        return
      end

      if token == "@"
        start_macro_play_pending
        return
      end

      if token == "m"
        start_mark_pending
        return
      end

      if token == "'"
        start_jump_pending(linewise: true, repeat_token: "'")
        return
      end

      if token == "`"
        start_jump_pending(linewise: false, repeat_token: "`")
        return
      end

      @pending_keys ||= []
      @pending_keys << token

      match = @keymaps.resolve_with_context(:normal, @pending_keys, editor: @editor)
      case match.status
      when :pending, :ambiguous
        return
      when :match
        matched_keys = @pending_keys.dup
        repeat_count = @editor.pending_count || 1
        invocation = dup_invocation(match.invocation)
        invocation.count = repeat_count
        @dispatcher.dispatch(@editor, invocation)
        maybe_record_simple_dot_change(invocation, matched_keys, repeat_count)
      else
        @editor.echo("Unknown key: #{@pending_keys.join}")
      end
      @editor.pending_count = nil
      @pending_keys = []
    end

    def handle_insert_key(key)
      case key
      when :escape
        finish_insert_change_group
        clear_insert_completion
        @editor.enter_normal_mode
        @editor.echo("")
      when :backspace
        clear_insert_completion
        y, x = @editor.current_buffer.backspace(@editor.current_window.cursor_y, @editor.current_window.cursor_x)
        @editor.current_window.cursor_y = y
        @editor.current_window.cursor_x = x
      when :ctrl_n
        insert_complete(+1)
      when :ctrl_p
        insert_complete(-1)
      when :ctrl_i
        clear_insert_completion
        @editor.current_buffer.insert_char(@editor.current_window.cursor_y, @editor.current_window.cursor_x, "\t")
        @editor.current_window.cursor_x += 1
      when :enter
        clear_insert_completion
        y, x = @editor.current_buffer.insert_newline(@editor.current_window.cursor_y, @editor.current_window.cursor_x)
        @editor.current_window.cursor_y = y
        @editor.current_window.cursor_x = x
      when :left
        clear_insert_completion
        @editor.current_window.move_left(@editor.current_buffer, 1)
      when :right
        clear_insert_completion
        @editor.current_window.move_right(@editor.current_buffer, 1)
      when :up
        clear_insert_completion
        @editor.current_window.move_up(@editor.current_buffer, 1)
      when :down
        clear_insert_completion
        @editor.current_window.move_down(@editor.current_buffer, 1)
      else
        return unless key.is_a?(String)

        clear_insert_completion
        @editor.current_buffer.insert_char(@editor.current_window.cursor_y, @editor.current_window.cursor_x, key)
        @editor.current_window.cursor_x += 1
      end
    end

    def handle_visual_key(key)
      if arrow_key?(key)
        invoke_arrow(key)
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
      when "y"
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "buffer.visual_yank"))
      when "d"
        @visual_pending = nil
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: "buffer.visual_delete"))
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
        return
      end

      if @pending_keys == ["g"] && token == "g"
        id = "cursor.buffer_start"
      end

      if id
        count = @editor.pending_count || 1
        @dispatcher.dispatch(@editor, CommandInvocation.new(id:, count: count))
      else
        @editor.echo("Unknown visual key: #{token}")
      end
    ensure
      @pending_keys = [] unless token == "g"
    end

    def handle_command_line_key(key)
      cmd = @editor.command_line
      case key
      when :escape
        @editor.cancel_command_line
      when :enter
        line = cmd.text.dup
        push_command_line_history(cmd.prefix, line)
        handle_command_line_submit(cmd.prefix, line)
      when :backspace
        cmd.backspace
      when :up
        command_line_history_move(-1)
      when :down
        command_line_history_move(1)
      when :left
        cmd.move_left
      when :right
        cmd.move_right
      else
        if key == :ctrl_i
          command_line_complete
        elsif key.is_a?(String)
          @cmdline_history_index = nil
          cmd.insert(key)
        end
      end
    end

    def arrow_key?(key)
      %i[left right up down].include?(key)
    end

    def invoke_arrow(key)
      id = {
        left: "cursor.left",
        right: "cursor.right",
        up: "cursor.up",
        down: "cursor.down"
      }.fetch(key)
      inv = CommandInvocation.new(id:, count: @editor.pending_count || 1)
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
      when :ctrl_i then "<C-i>"
      when :ctrl_o then "<C-o>"
      when :ctrl_w then "<C-w>"
      when :home then "<Home>"
      when :end then "<End>"
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

    def handle_ctrl_c
      case @editor.mode
      when :insert
        finish_insert_change_group
        clear_insert_completion
        @editor.enter_normal_mode
        @editor.echo("")
      when :command_line
        @editor.cancel_command_line
      when :visual_char, :visual_line
        @visual_pending = nil
        @register_pending = false
        @mark_pending = false
        @jump_pending = nil
        @editor.enter_normal_mode
      else
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

    def finish_insert_change_group
      @editor.current_buffer.end_change_group
    end

    def handle_command_line_submit(prefix, line)
      case prefix
      when ":"
        @dispatcher.dispatch_ex(@editor, line)
      when "/"
        submit_search(line, direction: :forward)
      when "?"
        submit_search(line, direction: :backward)
      else
        @editor.echo("Unknown command-line prefix: #{prefix}")
        @editor.enter_normal_mode
      end
      @cmdline_history_index = nil
    end

    def start_operator_pending(name)
      @operator_pending = { name:, count: (@editor.pending_count || 1) }
      @editor.pending_count = nil
      @pending_keys = []
      @editor.echo(name == :delete ? "d" : name.to_s)
    end

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
        @editor.echo("Invalid register")
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
        @editor.echo("Invalid mark")
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
        @editor.echo("Invalid mark")
        return
      end

      inv = CommandInvocation.new(id: "mark.jump", kwargs: { mark: token, linewise: pending[:linewise] })
      @dispatcher.dispatch(@editor, inv)
    end

    def start_macro_record_pending
      @macro_record_pending = true
      @editor.echo("q")
    end

    def finish_macro_record_pending(token)
      @macro_record_pending = false
      if token == "\e"
        @editor.clear_message
        return
      end
      unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9]\z/)
        @editor.echo("Invalid macro register")
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
        @editor.echo("Invalid macro register")
        return
      end

      count = @editor.pending_count || 1
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
      count.times do
        keys.each { |k| handle_key(dup_macro_runtime_key(k)) }
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

    def handle_operator_pending_key(token)
      op = @operator_pending
      if %w[i a].include?(token) && !op[:motion_prefix]
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

      if op[:name] == :change && motion == "c"
        inv = CommandInvocation.new(id: "buffer.change_line", count: op[:count])
        @dispatcher.dispatch(@editor, inv)
        return
      end

      if op[:name] == :change
        inv = CommandInvocation.new(id: "buffer.change_motion", count: op[:count], kwargs: { motion: motion })
        @dispatcher.dispatch(@editor, inv)
        return
      end

      @editor.echo("Unknown operator")
    end

    def start_replace_pending
      @replace_pending = { count: (@editor.pending_count || 1) }
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

    def repeat_last_change
      keys = @last_change_keys
      if keys.nil? || keys.empty?
        @editor.echo("No previous change")
        return
      end

      @dot_replay_depth = (@dot_replay_depth || 0) + 1
      keys.each { |k| handle_key(dup_macro_runtime_key(k)) }
      @editor.echo(".")
    ensure
      @dot_replay_depth = [(@dot_replay_depth || 1) - 1, 0].max
    end

    def maybe_record_simple_dot_change(invocation, matched_keys, count)
      return if (@dot_replay_depth || 0).positive?

      case invocation.id
      when "buffer.delete_char", "buffer.paste_after", "buffer.paste_before"
        record_last_change_keys(count_prefixed_keys(count, matched_keys))
      end
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

    def start_find_pending(token)
      @find_pending = {
        direction: (token == "f" || token == "t") ? :forward : :backward,
        till: (token == "t" || token == "T"),
        count: (@editor.pending_count || 1)
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
      count = @editor.pending_count || 1
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

      count.times do
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
      @editor.echo("Error: #{e.message}")
      @editor.enter_normal_mode
    end

    def push_command_line_history(prefix, line)
      text = line.to_s
      return if text.empty?

      hist = @cmdline_history[prefix]
      hist.delete(text)
      hist << text
      hist.shift while hist.length > 100
      @cmdline_history_index = nil
    end

    def command_line_history_move(delta)
      cmd = @editor.command_line
      hist = @cmdline_history[cmd.prefix]
      return if hist.empty?

      @cmdline_history_index =
        if @cmdline_history_index.nil?
          delta.negative? ? hist.length - 1 : hist.length
        else
          @cmdline_history_index + delta
        end

      @cmdline_history_index = [[@cmdline_history_index, 0].max, hist.length].min
      if @cmdline_history_index == hist.length
        cmd.replace_text("")
      else
        cmd.replace_text(hist[@cmdline_history_index])
      end
    end

    def command_line_complete
      cmd = @editor.command_line
      return unless cmd.prefix == ":"

      ctx = ex_completion_context(cmd)
      return unless ctx

      matches = ex_completion_candidates(ctx)
      case matches.length
      when 0
        @editor.echo("No completion")
      when 1
        cmd.replace_span(ctx[:token_start], ctx[:token_end], matches.first)
      else
        prefix = common_prefix(matches)
        cmd.replace_span(ctx[:token_start], ctx[:token_end], prefix) if prefix.length > ctx[:prefix].length
        @editor.echo(matches.join(" "))
      end
    end

    def common_prefix(strings)
      return "" if strings.empty?

      prefix = strings.first.dup
      strings[1..]&.each do |s|
        while !prefix.empty? && !s.start_with?(prefix)
          prefix = prefix[0...-1]
        end
      end
      prefix
    end

    def clear_insert_completion
      @insert_completion = nil
    end

    def insert_complete(direction)
      state = ensure_insert_completion_state
      return unless state

      matches = state[:matches]
      if matches.empty?
        @editor.echo("No completion")
        return
      end

      idx = state[:index]
      idx = idx.nil? ? (direction.positive? ? 0 : matches.length - 1) : (idx + direction) % matches.length
      replacement = matches[idx]

      end_col = state[:current_end_col]
      start_col = state[:start_col]
      @editor.current_buffer.delete_span(state[:row], start_col, state[:row], end_col)
      _y, new_x = @editor.current_buffer.insert_text(state[:row], start_col, replacement)
      @editor.current_window.cursor_y = state[:row]
      @editor.current_window.cursor_x = new_x
      state[:index] = idx
      state[:current_end_col] = start_col + replacement.length
      @editor.echo(matches.length == 1 ? replacement : "#{replacement} (#{idx + 1}/#{matches.length})")
    rescue StandardError => e
      @editor.echo("Completion error: #{e.message}")
      clear_insert_completion
    end

    def ensure_insert_completion_state
      row = @editor.current_window.cursor_y
      col = @editor.current_window.cursor_x
      line = @editor.current_buffer.line_at(row)
      prefix = line[0...col].to_s[/[[:alnum:]_]+\z/]
      return nil if prefix.nil? || prefix.empty?

      start_col = col - prefix.length
      current_token = line[start_col...col].to_s
      state = @insert_completion

      if state &&
         state[:row] == row &&
         state[:start_col] == start_col &&
         state[:prefix] == prefix &&
         col == state[:current_end_col]
        return state
      end

      matches = collect_buffer_word_completions(prefix, current_word: current_token)
      @insert_completion = {
        row: row,
        start_col: start_col,
        prefix: prefix,
        matches: matches,
        index: nil,
        current_end_col: col
      }
    end

    def collect_buffer_word_completions(prefix, current_word:)
      words = []
      seen = {}
      @editor.buffers.values.each do |buf|
        buf.lines.each do |line|
          line.scan(/[[:alnum:]_]+/) do |w|
            next unless w.start_with?(prefix)
            next if w == current_word
            next if seen[w]

            seen[w] = true
            words << w
          end
        end
      end
      words.sort
    end

    def ex_completion_context(cmd)
      text = cmd.text
      cursor = cmd.cursor
      token_start = token_start_index(text, cursor)
      token_end = token_end_index(text, cursor)
      prefix = text[token_start...cursor].to_s
      before = text[0...token_start].to_s
      argv_before = before.split(/\s+/).reject(&:empty?)

      if argv_before.empty?
        {
          kind: :command,
          token_start: token_start,
          token_end: token_end,
          prefix: prefix
        }
      else
        {
          kind: :arg,
          command: argv_before.first,
          arg_index: argv_before.length - 1,
          token_start: token_start,
          token_end: token_end,
          prefix: prefix
        }
      end
    end

    def ex_completion_candidates(ctx)
      case ctx[:kind]
      when :command
        ExCommandRegistry.instance.all.flat_map { |spec| [spec.name, *spec.aliases] }.uniq.sort.select { |n| n.start_with?(ctx[:prefix]) }
      when :arg
        ex_arg_completion_candidates(ctx[:command], ctx[:arg_index], ctx[:prefix])
      else
        []
      end
    end

    def ex_arg_completion_candidates(command_name, arg_index, prefix)
      cmd = command_name.to_s
      return [] unless arg_index.zero?

      if %w[e edit w write tabnew].include?(cmd)
        return path_completion_candidates(prefix)
      end

      if %w[buffer b].include?(cmd)
        return buffer_completion_candidates(prefix)
      end

      if %w[set setlocal setglobal].include?(cmd)
        return option_completion_candidates(prefix)
      end

      []
    end

    def path_completion_candidates(prefix)
      input = prefix.to_s
      base_dir =
        if input.empty?
          "."
        elsif input.end_with?("/")
          input
        else
          File.dirname(input)
        end
      base_dir = "." if base_dir == "."
      partial = input.end_with?("/") ? "" : File.basename(input)
      pattern = input.empty? ? "*" : File.join(base_dir, "#{partial}*")
      Dir.glob(pattern, File::FNM_DOTMATCH).sort.filter_map do |p|
        next if [".", ".."].include?(File.basename(p))
        next unless p.start_with?(input) || input.empty?
        File.directory?(p) ? "#{p}/" : p
      end
    rescue StandardError
      []
    end

    def buffer_completion_candidates(prefix)
      pfx = prefix.to_s
      items = @editor.buffers.values.flat_map do |b|
        path = b.path.to_s
        base = path.empty? ? nil : File.basename(path)
        [b.id.to_s, path, base].compact
      end.uniq.sort
      items.select { |s| s.start_with?(pfx) }
    end

    def option_completion_candidates(prefix)
      pfx = prefix.to_s
      names = RuVim::Editor::OPTION_DEFS.keys
      tokens = names + names.map { |n| "no#{n}" } + names.map { |n| "inv#{n}" } + names.map { |n| "#{n}?" }
      tokens.uniq.sort.select { |s| s.start_with?(pfx) }
    end

    def token_start_index(text, cursor)
      i = [[cursor, 0].max, text.length].min
      i -= 1 while i.positive? && !whitespace_char?(text[i - 1])
      i
    end

    def token_end_index(text, cursor)
      i = [[cursor, 0].max, text.length].min
      i += 1 while i < text.length && !whitespace_char?(text[i])
      i
    end

    def whitespace_char?(ch)
      ch && ch.match?(/\s/)
    end

    def install_signal_handlers
      Signal.trap("WINCH") do
        @screen.invalidate_cache! if @screen.respond_to?(:invalidate_cache!)
        @needs_redraw = true
        notify_signal_wakeup
      end
    rescue ArgumentError
      nil
    end

    def init_config_loader!
      @config_loader = ConfigLoader.new(
        command_registry: CommandRegistry.instance,
        ex_registry: ExCommandRegistry.instance,
        keymaps: @keymaps,
        command_host: GlobalCommands.instance
      )
    end

    def load_user_config!
      return if @clean_mode
      return if @skip_user_config

      if @config_path
        @config_loader.load_file(@config_path)
      else
        @config_loader.load_default!
      end
    rescue StandardError => e
      @editor.echo("config error: #{e.message}")
    end

    def load_current_ftplugin!
      return if @clean_mode
      return unless @config_loader

      @config_loader.load_ftplugin!(@editor, @editor.current_buffer)
    rescue StandardError => e
      @editor.echo("ftplugin error: #{e.message}")
    end

    def run_startup_action!(action)
      case action[:type]
      when :ex
        @dispatcher.dispatch_ex(@editor, action[:value].to_s)
      when :line
        move_cursor_to_line(action[:value].to_i)
      when :line_end
        move_cursor_to_line(@editor.current_buffer.line_count)
      end
    end

    def apply_startup_readonly!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?

      buf.readonly = true
      @editor.echo("readonly: #{buf.display_name}")
    end

    def apply_startup_nomodifiable!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?

      buf.modifiable = false
      buf.readonly = true
      @editor.echo("nomodifiable: #{buf.display_name}")
    end

    def open_startup_paths!(paths)
      list = Array(paths).compact
      return if list.empty?

      first, *rest = list
      @editor.open_path(first)
      apply_startup_readonly! if @startup_readonly
      apply_startup_nomodifiable! if @startup_nomodifiable

      case @startup_open_layout
      when :horizontal
        rest.each { |p| open_path_in_split!(p, layout: :horizontal) }
      when :vertical
        rest.each { |p| open_path_in_split!(p, layout: :vertical) }
      when :tab
        rest.each { |p| open_path_in_tab!(p) }
      else
        # No multi-file layout mode yet; ignore extras if called directly.
      end
    end

    def open_path_in_split!(path, layout:)
      @editor.split_current_window(layout:)
      buf = @editor.add_buffer_from_file(path)
      @editor.switch_to_buffer(buf.id)
      apply_startup_readonly! if @startup_readonly
      apply_startup_nomodifiable! if @startup_nomodifiable
    end

    def open_path_in_tab!(path)
      @editor.tabnew(path:)
      apply_startup_readonly! if @startup_readonly
      apply_startup_nomodifiable! if @startup_nomodifiable
    end

    def move_cursor_to_line(line_number)
      win = @editor.current_window
      buf = @editor.current_buffer
      return unless win && buf

      target = [[line_number.to_i - 1, 0].max, buf.line_count - 1].min
      win.cursor_y = target
      win.clamp_to_buffer(buf)
    end

    def notify_signal_wakeup
      @signal_w.write_nonblock(".")
    rescue IO::WaitWritable, Errno::EPIPE
      nil
    end

    def register_internal_unless(registry, id, **spec)
      return if registry.registered?(id)

      registry.register(id, **spec)
    end

    def register_ex_unless(registry, name, **spec)
      return if registry.registered?(name)

      registry.register(name, **spec)
    end
  end
end
