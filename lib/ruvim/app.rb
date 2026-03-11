# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "file_watcher"
require_relative "stream_mixer"
require_relative "completion_manager"
require_relative "key_handler"

module RuVim
  class App
    StartupState = Struct.new(
      :readonly, :diff_mode, :quickfix_errorfile, :session_file,
      :nomodifiable, :follow, :time_path, :time_origin, :timeline,
      :open_layout, :open_count, :skip_user_config, :config_path,
      keyword_init: true
    )
    def initialize(path: nil, paths: nil, stdin: STDIN, ui_stdin: nil, stdin_stream_mode: false, stdout: STDOUT, pre_config_actions: [], startup_actions: [], clean: false, skip_user_config: false, config_path: nil, readonly: false, diff_mode: false, quickfix_errorfile: nil, session_file: nil, nomodifiable: false, follow: false, restricted: false, verbose_level: 0, verbose_io: STDERR, startup_time_path: nil, startup_open_layout: nil, startup_open_count: nil)
      startup_paths = Array(paths || path).compact
      stdin_stream = !!stdin_stream_mode
      effective_stdin = ui_stdin || stdin
      @terminal = Terminal.new(stdin: effective_stdin, stdout:)
      @input = Input.new(effective_stdin)
      @screen = Screen.new(terminal: @terminal)
      @dispatcher = Dispatcher.new
      @keymaps = KeymapManager.new
      @signal_r, @signal_w = IO.pipe
      @needs_redraw = true
      @clean_mode = clean
      @startup = StartupState.new(
        skip_user_config: skip_user_config,
        config_path: config_path,
        readonly: readonly,
        diff_mode: diff_mode,
        quickfix_errorfile: quickfix_errorfile,
        session_file: session_file,
        nomodifiable: nomodifiable,
        follow: follow,
        time_path: startup_time_path,
        time_origin: monotonic_now,
        timeline: [],
        open_layout: startup_open_layout,
        open_count: startup_open_count
      )
      @verbose_level = verbose_level.to_i
      @verbose_io = verbose_io

      @editor = Editor.new(
        restricted_mode: restricted,
        keymap_manager: @keymaps
      )
      @stream_mixer = StreamMixer.new(editor: @editor, signal_w: @signal_w)
      @editor.stream_mixer = @stream_mixer
      @completion = CompletionManager.new(
        editor: @editor,
        verbose_logger: method(:verbose_log)
      )
      @key_handler = KeyHandler.new(
        editor: @editor,
        dispatcher: @dispatcher,
        completion: @completion
      )
      @editor.app_action_handler = @key_handler.method(:handle_editor_app_action)
      @editor.suspend_handler = -> {
        @terminal.suspend_for_tstp
        @screen.invalidate_cache!
      }
      @editor.shell_executor = ->(command) {
        result = @terminal.suspend_for_shell(command)
        @screen.invalidate_cache!
        result
      }
      @editor.confirm_key_reader = -> {
        @screen.render(@editor)
        @input.read_key
      }
      @editor.normal_key_feeder = ->(keys) { keys.each { |k| @key_handler.handle(k) } }

      @completion.load_history!

      startup_mark("init.start")
      register_builtins!
      bind_default_keys!
      init_config_loader!
      @editor.ensure_bootstrap_buffer!
      verbose_log(1, "startup: run_pre_config_actions count=#{Array(pre_config_actions).length}")
      run_startup_actions!(pre_config_actions, log_prefix: "pre-config")
      startup_mark("pre_config_actions.done")
      verbose_log(1, "startup: load_user_config")
      load_user_config!
      startup_mark("config.loaded")
      install_signal_handlers
      startup_mark("signals.installed")

      if stdin_stream && startup_paths.empty?
        verbose_log(1, "startup: stdin stream buffer")
        @stream_mixer.prepare_stdin_stream_buffer!(stdin)
      elsif startup_paths.empty?
        verbose_log(1, "startup: intro")
        @editor.show_intro_buffer_if_applicable!
      else
        verbose_log(1, "startup: open_paths #{startup_paths.inspect} layout=#{@startup.open_layout || :single}")
        open_startup_paths!(startup_paths)
      end
      startup_mark("buffers.opened")
      verbose_log(1, "startup: load_current_ftplugin")
      load_current_ftplugin!
      startup_mark("ftplugin.loaded")
      apply_startup_compat_mode_messages!
      verbose_log(1, "startup: run_startup_actions count=#{Array(startup_actions).length}")
      run_startup_actions!(startup_actions)
      startup_mark("startup_actions.done")
      @stream_mixer.start_pending_stdin!
      write_startuptime_log!
      @startup = nil
    end

    def run
      @terminal.with_ui do
        loop do
          @needs_redraw = true if @stream_mixer.drain_events!
          if @needs_redraw
            @screen.render(@editor)
            @needs_redraw = false
          end
          break unless @editor.running?

          key = @input.read_key(
            wakeup_ios: [@signal_r],
            timeout: @key_handler.loop_timeout_seconds,
            esc_timeout: @key_handler.escape_sequence_timeout_seconds
          )
          if key.nil?
            @needs_redraw = true if @key_handler.handle_idle_timeout
            next
          end

          needs_redraw_from_key = @key_handler.handle(key)
          @needs_redraw = true
          load_current_ftplugin!

          # Force redraw after suspend_to_shell
          @needs_redraw = true if needs_redraw_from_key

          # Batch insert-mode keystrokes to avoid per-char rendering during paste
          if @editor.mode == :insert && @input.has_pending_input?
            @key_handler.paste_batch = true
            begin
              while @editor.mode == :insert && @input.has_pending_input?
                batch_key = @input.read_key(timeout: 0, esc_timeout: 0)
                break unless batch_key
                @key_handler.handle(batch_key)
              end
            ensure
              @key_handler.paste_batch = false
            end
          end
        end
      end
    ensure
      @stream_mixer.shutdown!
      @completion.save_history!
    end

    def run_startup_actions!(actions, log_prefix: "startup")
      Array(actions).each do |action|
        run_startup_action!(action, log_prefix:)
        break unless @editor.running?
      end
    end

    private

    def clear_expired_transient_message_if_any
      @needs_redraw = true if @key_handler.handle_idle_timeout
    end


    def register_builtins!
      cmd = CommandRegistry.instance
      ex = ExCommandRegistry.instance

      register_internal_unless(cmd, "cursor.left", call: :cursor_left, desc: "Move cursor left")
      register_internal_unless(cmd, "cursor.right", call: :cursor_right, desc: "Move cursor right")
      register_internal_unless(cmd, "cursor.up", call: :cursor_up, desc: "Move cursor up")
      register_internal_unless(cmd, "cursor.down", call: :cursor_down, desc: "Move cursor down")
      register_internal_unless(cmd, "cursor.page_up", call: :cursor_page_up, desc: "Move one page up")
      register_internal_unless(cmd, "cursor.page_down", call: :cursor_page_down, desc: "Move one page down")
      register_internal_unless(cmd, "window.scroll_up", call: :window_scroll_up, desc: "Scroll window up")
      register_internal_unless(cmd, "window.scroll_down", call: :window_scroll_down, desc: "Scroll window down")
      register_internal_unless(cmd, "cursor.page_up.default", call: :cursor_page_up_default, desc: "Move one page up (view-sized)")
      register_internal_unless(cmd, "cursor.page_down.default", call: :cursor_page_down_default, desc: "Move one page down (view-sized)")
      register_internal_unless(cmd, "cursor.page_up.half", call: :cursor_page_up_half, desc: "Move half page up")
      register_internal_unless(cmd, "cursor.page_down.half", call: :cursor_page_down_half, desc: "Move half page down")
      register_internal_unless(cmd, "window.scroll_up.line", call: :window_scroll_up_line, desc: "Scroll window up one line")
      register_internal_unless(cmd, "window.scroll_down.line", call: :window_scroll_down_line, desc: "Scroll window down one line")
      register_internal_unless(cmd, "window.cursor_line_top", call: :window_cursor_line_top, desc: "Put cursor line at top")
      register_internal_unless(cmd, "window.cursor_line_center", call: :window_cursor_line_center, desc: "Put cursor line at center")
      register_internal_unless(cmd, "window.cursor_line_bottom", call: :window_cursor_line_bottom, desc: "Put cursor line at bottom")
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
      register_internal_unless(cmd, "mode.visual_block", call: :enter_visual_block_mode, desc: "Enter visual block mode")
      register_internal_unless(cmd, "window.split", call: :window_split, desc: "Horizontal split")
      register_internal_unless(cmd, "window.vsplit", call: :window_vsplit, desc: "Vertical split")
      register_internal_unless(cmd, "window.focus_next", call: :window_focus_next, desc: "Next window")
      register_internal_unless(cmd, "window.focus_left", call: :window_focus_left, desc: "Focus left window")
      register_internal_unless(cmd, "window.focus_right", call: :window_focus_right, desc: "Focus right window")
      register_internal_unless(cmd, "window.focus_up", call: :window_focus_up, desc: "Focus upper window")
      register_internal_unless(cmd, "window.focus_down", call: :window_focus_down, desc: "Focus lower window")
      register_internal_unless(cmd, "window.focus_or_split_left", call: :window_focus_or_split_left, desc: "Focus left window or split")
      register_internal_unless(cmd, "window.focus_or_split_right", call: :window_focus_or_split_right, desc: "Focus right window or split")
      register_internal_unless(cmd, "window.focus_or_split_up", call: :window_focus_or_split_up, desc: "Focus upper window or split")
      register_internal_unless(cmd, "window.focus_or_split_down", call: :window_focus_or_split_down, desc: "Focus lower window or split")
      register_internal_unless(cmd, "window.close", call: :window_close, desc: "Close current window")
      register_internal_unless(cmd, "window.only", call: :window_only, desc: "Close all other windows")
      register_internal_unless(cmd, "window.equalize", call: :window_equalize, desc: "Equalize window sizes")
      register_internal_unless(cmd, "window.resize_height_inc", call: :window_resize_height_inc, desc: "Increase window height")
      register_internal_unless(cmd, "window.resize_height_dec", call: :window_resize_height_dec, desc: "Decrease window height")
      register_internal_unless(cmd, "window.resize_width_inc", call: :window_resize_width_inc, desc: "Increase window width")
      register_internal_unless(cmd, "window.resize_width_dec", call: :window_resize_width_dec, desc: "Decrease window width")
      register_internal_unless(cmd, "mode.command_line", call: :enter_command_line_mode, desc: "Enter command-line mode")
      register_internal_unless(cmd, "mode.search_forward", call: :enter_search_forward_mode, desc: "Enter / search")
      register_internal_unless(cmd, "mode.search_backward", call: :enter_search_backward_mode, desc: "Enter ? search")
      register_internal_unless(cmd, "buffer.delete_char", call: :delete_char, desc: "Delete char under cursor")
      register_internal_unless(cmd, "buffer.substitute_char", call: :substitute_char, desc: "Substitute char(s)")
      register_internal_unless(cmd, "buffer.swapcase_char", call: :swapcase_char, desc: "Swap case under cursor")
      register_internal_unless(cmd, "buffer.join_lines", call: :join_lines, desc: "Join lines")
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
      register_internal_unless(cmd, "editor.buffer_delete", call: :buffer_delete, desc: "Delete buffer")
      register_internal_unless(cmd, "buffer.replace_char", call: :replace_char, desc: "Replace single char")
      register_internal_unless(cmd, "file.goto_under_cursor", call: :file_goto_under_cursor, desc: "Open file under cursor")
      register_internal_unless(cmd, "ui.clear_message", call: :clear_message, desc: "Clear message")
      register_internal_unless(cmd, "normal.register_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_register_pending_start) }, desc: "Select register for next operation")
      register_internal_unless(cmd, "normal.operator_delete_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_operator_start, name: :delete) }, desc: "Start delete operator")
      register_internal_unless(cmd, "normal.operator_yank_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_operator_start, name: :yank) }, desc: "Start yank operator")
      register_internal_unless(cmd, "normal.operator_change_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_operator_start, name: :change) }, desc: "Start change operator")
      register_internal_unless(cmd, "normal.operator_indent_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_operator_start, name: :indent) }, desc: "Start indent operator")
      register_internal_unless(cmd, "buffer.indent_lines", call: :indent_lines, desc: "Auto-indent lines")
      register_internal_unless(cmd, "buffer.indent_motion", call: :indent_motion, desc: "Auto-indent motion range")
      register_internal_unless(cmd, "buffer.visual_indent", call: :visual_indent, desc: "Auto-indent visual selection")
      register_internal_unless(cmd, "normal.replace_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_replace_pending_start) }, desc: "Start replace-char pending")
      register_internal_unless(cmd, "normal.find_char_forward_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_pending_start, token: "f") }, desc: "Start char find forward")
      register_internal_unless(cmd, "normal.find_char_backward_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_pending_start, token: "F") }, desc: "Start char find backward")
      register_internal_unless(cmd, "normal.find_till_forward_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_pending_start, token: "t") }, desc: "Start till-char find forward")
      register_internal_unless(cmd, "normal.find_till_backward_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_pending_start, token: "T") }, desc: "Start till-char find backward")
      register_internal_unless(cmd, "normal.find_repeat", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_repeat, reverse: false) }, desc: "Repeat last f/t/F/T")
      register_internal_unless(cmd, "normal.find_repeat_reverse", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_find_repeat, reverse: true) }, desc: "Repeat last f/t/F/T in reverse")
      register_internal_unless(cmd, "normal.change_repeat", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_change_repeat) }, desc: "Repeat last change")
      register_internal_unless(cmd, "normal.macro_record_toggle", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_macro_record_toggle) }, desc: "Start/stop macro recording")
      register_internal_unless(cmd, "normal.macro_play_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_macro_play_pending_start) }, desc: "Start macro play pending")
      register_internal_unless(cmd, "normal.mark_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_mark_pending_start) }, desc: "Start mark set pending")
      register_internal_unless(cmd, "normal.jump_mark_linewise_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_jump_pending_start, linewise: true, repeat_token: "'") }, desc: "Start linewise mark jump pending")
      register_internal_unless(cmd, "normal.jump_mark_exact_pending_start", call: ->(ctx, **) { ctx.editor.invoke_app_action(:normal_jump_pending_start, linewise: false, repeat_token: "`") }, desc: "Start exact mark jump pending")
      register_internal_unless(
        cmd,
        "stdin.stream_stop",
        call: ->(ctx, **) {
          return if ctx.editor.stream_stop_or_cancel!
          ctx.editor.invoke_app_action(:normal_ctrl_c)
        },
        desc: "Stop stream (or cancel pending state)"
      )

      register_ex_unless(ex, "w", call: :file_write, aliases: %w[write], desc: "Write current buffer", nargs: :any, bang: true)
      register_ex_unless(ex, "q", call: :app_quit, aliases: %w[quit], desc: "Quit", nargs: 0, bang: true)
      register_ex_unless(ex, "qa", call: :app_quit_all, aliases: %w[qall], desc: "Quit all", nargs: 0, bang: true)
      register_ex_unless(ex, "wq", call: :file_write_quit, desc: "Write and quit", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "wqa", call: :file_write_quit_all, aliases: %w[wqall xa xall], desc: "Write all and quit", nargs: 0, bang: true)
      register_ex_unless(ex, "e", call: :file_edit, aliases: %w[edit], desc: "Edit file / reload", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "r", call: :ex_read, aliases: %w[read], desc: "Read file or command output into buffer", nargs: :any)
      register_ex_unless(ex, "help", call: :ex_help, desc: "Show help / topics", nargs: :any)
      register_ex_unless(ex, "command", call: :ex_define_command, desc: "Define user command", nargs: :any, bang: true)
      register_ex_unless(ex, "ruby", call: :ex_ruby, aliases: %w[rb], desc: "Evaluate Ruby", nargs: :any, bang: false)
      register_ex_unless(ex, "ls", call: :buffer_list, aliases: %w[buffers], desc: "List buffers", nargs: 0)
      register_ex_unless(ex, "bnext", call: :buffer_next, aliases: %w[bn], desc: "Next buffer", nargs: 0, bang: true)
      register_ex_unless(ex, "bprev", call: :buffer_prev, aliases: %w[bp], desc: "Previous buffer", nargs: 0, bang: true)
      register_ex_unless(ex, "buffer", call: :buffer_switch, aliases: %w[b], desc: "Switch buffer", nargs: 1, bang: true)
      register_ex_unless(ex, "bdelete", call: :buffer_delete, aliases: %w[bd], desc: "Delete buffer", nargs: :maybe_one, bang: true)
      register_ex_unless(ex, "args", call: :arglist_show, desc: "Show argument list", nargs: 0)
      register_ex_unless(ex, "next", call: :arglist_next, desc: "Next argument", nargs: 0)
      register_ex_unless(ex, "prev", call: :arglist_prev, desc: "Previous argument", nargs: 0)
      register_ex_unless(ex, "first", call: :arglist_first, desc: "First argument", nargs: 0)
      register_ex_unless(ex, "last", call: :arglist_last, desc: "Last argument", nargs: 0)
      register_ex_unless(ex, "commands", call: :ex_commands, desc: "List Ex commands", nargs: 0)
      register_ex_unless(ex, "bindings", call: :ex_bindings, desc: "List active key bindings", nargs: :any)
      register_ex_unless(ex, "set", call: :ex_set, desc: "Set options", nargs: :any)
      register_ex_unless(ex, "setlocal", call: :ex_setlocal, desc: "Set window/buffer local option", nargs: :any)
      register_ex_unless(ex, "setglobal", call: :ex_setglobal, desc: "Set global option", nargs: :any)
      register_ex_unless(ex, "split", call: :window_split, desc: "Horizontal split", nargs: 0)
      register_ex_unless(ex, "vsplit", call: :window_vsplit, desc: "Vertical split", nargs: 0)
      register_ex_unless(ex, "tabnew", call: :tab_new, desc: "New tab", nargs: :maybe_one)
      register_ex_unless(ex, "tabnext", call: :tab_next, aliases: %w[tabn], desc: "Next tab", nargs: 0)
      register_ex_unless(ex, "tabprev", call: :tab_prev, aliases: %w[tabp], desc: "Prev tab", nargs: 0)
      register_ex_unless(ex, "tabs", call: :tab_list, desc: "List tabs", nargs: 0)
      register_ex_unless(ex, "vimgrep", call: :ex_vimgrep, desc: "Populate quickfix from regex (minimal)", nargs: :any)
      register_ex_unless(ex, "lvimgrep", call: :ex_lvimgrep, desc: "Populate location list from regex (minimal)", nargs: :any)
      register_ex_unless(ex, "copen", call: :ex_copen, desc: "Open quickfix list", nargs: 0)
      register_ex_unless(ex, "cclose", call: :ex_cclose, desc: "Close quickfix window", nargs: 0)
      register_ex_unless(ex, "cnext", call: :ex_cnext, aliases: %w[cn], desc: "Next quickfix item", nargs: 0)
      register_ex_unless(ex, "cprev", call: :ex_cprev, aliases: %w[cp], desc: "Prev quickfix item", nargs: 0)
      register_ex_unless(ex, "lopen", call: :ex_lopen, desc: "Open location list", nargs: 0)
      register_ex_unless(ex, "lclose", call: :ex_lclose, desc: "Close location list window", nargs: 0)
      register_ex_unless(ex, "lnext", call: :ex_lnext, aliases: %w[ln], desc: "Next location item", nargs: 0)
      register_ex_unless(ex, "lprev", call: :ex_lprev, aliases: %w[lp], desc: "Prev location item", nargs: 0)
      register_ex_unless(ex, "grep", call: :ex_grep, desc: "Search with external grep", nargs: :any)
      register_ex_unless(ex, "lgrep", call: :ex_lgrep, desc: "Search with external grep (location list)", nargs: :any)
      register_ex_unless(ex, "d", call: :ex_delete_lines, aliases: %w[delete], desc: "Delete lines", nargs: :any)
      register_ex_unless(ex, "y", call: :ex_yank_lines, aliases: %w[yank], desc: "Yank lines", nargs: :any)
      register_ex_unless(ex, "p", call: :ex_print_lines, aliases: %w[print], desc: "Print lines", nargs: 0)
      register_ex_unless(ex, "nu", call: :ex_number_lines, aliases: %w[number], desc: "Print lines with numbers", nargs: 0)
      register_ex_unless(ex, "m", call: :ex_move_lines, aliases: %w[move], desc: "Move lines", nargs: :any, raw_args: true)
      register_ex_unless(ex, "t", call: :ex_copy_lines, aliases: %w[copy co], desc: "Copy lines", nargs: :any, raw_args: true)
      register_ex_unless(ex, "j", call: :ex_join_lines, aliases: %w[join], desc: "Join lines", nargs: 0)
      register_ex_unless(ex, ">", call: :ex_shift_right, desc: "Shift lines right", nargs: 0)
      register_ex_unless(ex, "<", call: :ex_shift_left, desc: "Shift lines left", nargs: 0)
      register_ex_unless(ex, "normal", call: :ex_normal, aliases: %w[norm], desc: "Execute normal mode commands", nargs: :any, raw_args: true)
      register_ex_unless(ex, "rich", call: :ex_rich, desc: "Open/close Rich View", nargs: :maybe_one)
      register_ex_unless(ex, "follow", call: ->(ctx, **) { ctx.editor.invoke_app_action(:follow_toggle) }, desc: "Toggle file follow mode", nargs: 0)
      register_ex_unless(ex, "nohlsearch", call: ->(ctx, **) { ctx.editor.suppress_hlsearch! }, aliases: %w[noh nohl nohlsearc nohlsear nohlsea nohlse nohls], desc: "Temporarily clear search highlight", nargs: 0)
      register_ex_unless(ex, "filter", call: :ex_filter, desc: "Filter lines matching search pattern", nargs: :any)
      register_internal_unless(cmd, "search.filter", call: :search_filter, desc: "Filter lines matching search pattern")
      register_internal_unless(cmd, "rich.toggle", call: :rich_toggle, desc: "Toggle Rich View")
      register_internal_unless(cmd, "rich.close_buffer", call: :rich_view_close_buffer, desc: "Close rich view buffer")
      register_internal_unless(cmd, "quickfix.next", call: :ex_cnext, desc: "Next quickfix item")
      register_internal_unless(cmd, "quickfix.prev", call: :ex_cprev, desc: "Prev quickfix item")
      register_internal_unless(cmd, "quickfix.open", call: :ex_copen, desc: "Open quickfix list")

      register_internal_unless(cmd, "spell.next", call: :spell_next, desc: "Next misspelled word")
      register_internal_unless(cmd, "spell.prev", call: :spell_prev, desc: "Previous misspelled word")

      register_internal_unless(cmd, "git.blame", call: :git_blame, desc: "Open git blame buffer")
      register_internal_unless(cmd, "git.blame.prev", call: :git_blame_prev, desc: "Blame at parent commit")
      register_internal_unless(cmd, "git.blame.back", call: :git_blame_back, desc: "Restore previous blame")
      register_internal_unless(cmd, "git.blame.commit", call: :git_blame_commit, desc: "Show commit details")
      register_internal_unless(cmd, "git.command_mode", call: :enter_git_command_mode, desc: "Enter Git command-line mode")
      register_internal_unless(cmd, "git.close_buffer", call: :git_close_buffer, desc: "Close git buffer")
      register_internal_unless(cmd, "git.status.open_file", call: :git_status_open_file, desc: "Open file from git status")
      register_internal_unless(cmd, "git.diff.open_file", call: :git_diff_open_file, desc: "Open file from git diff")
      register_internal_unless(cmd, "git.grep.open_file", call: :git_grep_open_file, desc: "Open file from git grep")
      register_internal_unless(cmd, "git.branch.checkout", call: :git_branch_checkout, desc: "Checkout branch under cursor")
      register_internal_unless(cmd, "git.commit.execute", call: :git_commit_execute, desc: "Execute git commit")
      register_ex_unless(ex, "run", call: :ex_run, desc: "Run command and show output in buffer", nargs: :any, raw_args: true)
      register_ex_unless(ex, "git", call: :ex_git, desc: "Git subcommand dispatcher", nargs: :any)
      register_ex_unless(ex, "gh", call: :ex_gh, desc: "GitHub subcommand dispatcher", nargs: :any)
    end

    def bind_default_keys!
      @keymaps.bind(:normal, "h", "cursor.left")
      @keymaps.bind(:normal, "j", "cursor.down")
      @keymaps.bind(:normal, "k", "cursor.up")
      @keymaps.bind(:normal, "l", "cursor.right")
      @keymaps.bind(:normal, ["<Left>"], "cursor.left")
      @keymaps.bind(:normal, ["<Down>"], "cursor.down")
      @keymaps.bind(:normal, ["<Up>"], "cursor.up")
      @keymaps.bind(:normal, ["<Right>"], "cursor.right")
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
      @keymaps.bind(:normal, ["<C-v>"], "mode.visual_block")
      @keymaps.bind(:normal, ["<C-w>", "w"], "window.focus_next")
      @keymaps.bind(:normal, ["<C-w>", "h"], "window.focus_left")
      @keymaps.bind(:normal, ["<C-w>", "j"], "window.focus_down")
      @keymaps.bind(:normal, ["<C-w>", "k"], "window.focus_up")
      @keymaps.bind(:normal, ["<C-w>", "l"], "window.focus_right")
      @keymaps.bind(:normal, ["<C-w>", "c"], "window.close")
      @keymaps.bind(:normal, ["<C-w>", "o"], "window.only")
      @keymaps.bind(:normal, ["<C-w>", "="], "window.equalize")
      @keymaps.bind(:normal, ["<C-w>", "+"], "window.resize_height_inc")
      @keymaps.bind(:normal, ["<C-w>", "-"], "window.resize_height_dec")
      @keymaps.bind(:normal, ["<C-w>", ">"], "window.resize_width_inc")
      @keymaps.bind(:normal, ["<C-w>", "<"], "window.resize_width_dec")
      @keymaps.bind(:normal, ["<S-Left>"], "window.focus_or_split_left")
      @keymaps.bind(:normal, ["<S-Right>"], "window.focus_or_split_right")
      @keymaps.bind(:normal, ["<S-Up>"], "window.focus_or_split_up")
      @keymaps.bind(:normal, ["<S-Down>"], "window.focus_or_split_down")
      @keymaps.bind(:normal, ":", "mode.command_line")
      @keymaps.bind(:normal, "/", "mode.search_forward")
      @keymaps.bind(:normal, "?", "mode.search_backward")
      @keymaps.bind(:normal, "x", "buffer.delete_char")
      @keymaps.bind(:normal, "X", "buffer.delete_motion", kwargs: { motion: "h" })
      @keymaps.bind(:normal, "s", "buffer.substitute_char")
      @keymaps.bind(:normal, "D", "buffer.delete_motion", kwargs: { motion: "$" })
      @keymaps.bind(:normal, "C", "buffer.change_motion", kwargs: { motion: "$" })
      @keymaps.bind(:normal, "S", "buffer.change_line")
      @keymaps.bind(:normal, "Y", "buffer.yank_line")
      @keymaps.bind(:normal, "J", "buffer.join_lines")
      @keymaps.bind(:normal, "~", "buffer.swapcase_char")
      @keymaps.bind(:normal, "\"", "normal.register_pending_start")
      @keymaps.bind(:normal, "d", "normal.operator_delete_start")
      @keymaps.bind(:normal, "y", "normal.operator_yank_start")
      @keymaps.bind(:normal, "c", "normal.operator_change_start")
      @keymaps.bind(:normal, "=", "normal.operator_indent_start")
      @keymaps.bind(:normal, "r", "normal.replace_pending_start")
      @keymaps.bind(:normal, "f", "normal.find_char_forward_start")
      @keymaps.bind(:normal, "F", "normal.find_char_backward_start")
      @keymaps.bind(:normal, "t", "normal.find_till_forward_start")
      @keymaps.bind(:normal, "T", "normal.find_till_backward_start")
      @keymaps.bind(:normal, ";", "normal.find_repeat")
      @keymaps.bind(:normal, ",", "normal.find_repeat_reverse")
      @keymaps.bind(:normal, ".", "normal.change_repeat")
      @keymaps.bind(:normal, "q", "normal.macro_record_toggle")
      @keymaps.bind(:normal, "@", "normal.macro_play_pending_start")
      @keymaps.bind(:normal, "m", "normal.mark_pending_start")
      @keymaps.bind(:normal, "'", "normal.jump_mark_linewise_pending_start")
      @keymaps.bind(:normal, "`", "normal.jump_mark_exact_pending_start")
      @keymaps.bind(:normal, "p", "buffer.paste_after")
      @keymaps.bind(:normal, "P", "buffer.paste_before")
      @keymaps.bind(:normal, "u", "buffer.undo")
      @keymaps.bind(:normal, ["<C-r>"], "buffer.redo")
      @keymaps.bind(:normal, ["<C-o>"], "jump.older")
      @keymaps.bind(:normal, ["<C-i>"], "jump.newer")
      @keymaps.bind(:normal, ["<C-d>"], "cursor.page_down.half")
      @keymaps.bind(:normal, ["<C-u>"], "cursor.page_up.half")
      @keymaps.bind(:normal, ["<C-f>"], "cursor.page_down.default")
      @keymaps.bind(:normal, ["<C-b>"], "cursor.page_up.default")
      @keymaps.bind(:normal, ["<C-e>"], "window.scroll_down.line")
      @keymaps.bind(:normal, ["<C-y>"], "window.scroll_up.line")
      @keymaps.bind(:normal, "zt", "window.cursor_line_top")
      @keymaps.bind(:normal, "zz", "window.cursor_line_center")
      @keymaps.bind(:normal, "zb", "window.cursor_line_bottom")
      @keymaps.bind(:normal, ["<C-c>"], "stdin.stream_stop")
      @keymaps.bind(:normal, "n", "search.next")
      @keymaps.bind(:normal, "N", "search.prev")
      @keymaps.bind(:normal, "*", "search.word_forward")
      @keymaps.bind(:normal, "#", "search.word_backward")
      @keymaps.bind(:normal, "g*", "search.word_forward_partial")
      @keymaps.bind(:normal, "g#", "search.word_backward_partial")
      @keymaps.bind(:normal, "gf", "file.goto_under_cursor")
      @keymaps.bind(:normal, "gr", "rich.toggle")
      @keymaps.bind(:normal, "g/", "search.filter")
      @keymaps.bind(:normal, ["<C-g>"], "git.command_mode")
      @keymaps.bind(:normal, "Q", "quickfix.open")
      @keymaps.bind(:normal, ["]", "q"], "quickfix.next")
      @keymaps.bind(:normal, ["[", "q"], "quickfix.prev")
      @keymaps.bind(:normal, ["]", "s"], "spell.next")
      @keymaps.bind(:normal, ["[", "s"], "spell.prev")
      @keymaps.bind(:normal, ["<PageUp>"], "cursor.page_up.default")
      @keymaps.bind(:normal, ["<PageDown>"], "cursor.page_down.default")
      @keymaps.bind(:normal, "\e", "ui.clear_message")
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
      return if @clean_mode || @editor.restricted_mode?
      return if @startup.skip_user_config

      if @startup.config_path
        @config_loader.load_file(@startup.config_path)
      else
        @config_loader.load_default!
      end
    rescue StandardError => e
      @editor.echo_error("config error: #{e.message}")
    end

    def load_current_ftplugin!
      return if @clean_mode || @editor.restricted_mode?
      return unless @config_loader

      @config_loader.load_ftplugin!(@editor, @editor.current_buffer)
    rescue StandardError => e
      @editor.echo_error("ftplugin error: #{e.message}")
    end

    def run_startup_action!(action, log_prefix: "startup")
      case action[:type]
      when :ex
        verbose_log(2, "#{log_prefix} ex: #{action[:value]}")
        @dispatcher.dispatch_ex(@editor, action[:value].to_s)
      when :line
        verbose_log(2, "#{log_prefix} line: #{action[:value]}")
        move_cursor_to_line(action[:value].to_i)
      when :line_end
        verbose_log(2, "#{log_prefix} line_end")
        move_cursor_to_line(@editor.current_buffer.line_count)
      end
    end

    def verbose_log(level, message)
      return if @verbose_level < level
      return unless @verbose_io

      @verbose_io.puts("[ruvim:v#{@verbose_level}] #{message}")
      @verbose_io.flush if @verbose_io.respond_to?(:flush)
    rescue StandardError
      nil
    end

    def startup_mark(label)
      return unless @startup&.time_path

      @startup.timeline << [label.to_s, monotonic_now]
    end

    def write_startuptime_log!
      return unless @startup&.time_path

      prev = @startup.time_origin
      lines = @startup.timeline.map do |label, t|
        total_ms = ((t - @startup.time_origin) * 1000.0)
        delta_ms = ((t - prev) * 1000.0)
        prev = t
        format("%9.3f %9.3f %s", total_ms, delta_ms, label)
      end
      File.write(@startup.time_path, lines.join("\n") + "\n")
    rescue StandardError => e
      verbose_log(1, "startuptime write error: #{e.message}")
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue StandardError
      Time.now.to_f
    end

    def apply_startup_buffer_flags!
      apply_startup_readonly! if @startup.readonly
      apply_startup_nomodifiable! if @startup.nomodifiable
      apply_startup_follow! if @startup.follow
    end

    def apply_startup_readonly!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?

      buf.readonly = true
      @editor.echo("readonly: #{buf.display_name}")
    end

    def apply_startup_follow!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?
      return if @stream_mixer.follow_active?(buf)

      win = @editor.current_window
      win.cursor_y = buf.line_count - 1
      win.clamp_to_buffer(buf)
      @stream_mixer.start_follow!(buf)
    end

    def apply_startup_nomodifiable!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?

      buf.modifiable = false
      buf.readonly = true
      @editor.echo("nomodifiable: #{buf.display_name}")
    end

    def apply_startup_compat_mode_messages!
      if @startup.diff_mode
        verbose_log(1, "startup: -d requested (diff mode placeholder)")
        @editor.echo("diff mode (-d) is not implemented yet")
      end

      if @startup.quickfix_errorfile
        verbose_log(1, "startup: -q #{@startup.quickfix_errorfile} requested (quickfix placeholder)")
        @editor.echo("quickfix startup (-q #{@startup.quickfix_errorfile}) is not implemented yet")
      end

      if @startup.session_file
        verbose_log(1, "startup: -S #{@startup.session_file} requested (session placeholder)")
        @editor.echo("session startup (-S #{@startup.session_file}) is not implemented yet")
      end
    end

    def open_startup_paths!(paths)
      list = Array(paths).compact
      return if list.empty?

      evict_bootstrap_buffer!
      @editor.set_arglist(list)

      first, *rest = list
      @editor.open_path(first)
      apply_startup_buffer_flags!

      case @startup.open_layout
      when :horizontal
        first_win_id = @editor.current_window_id
        rest.each { |p| open_path_in_split!(p, layout: :horizontal) }
        @editor.focus_window(first_win_id)
      when :vertical
        first_win_id = @editor.current_window_id
        rest.each { |p| open_path_in_split!(p, layout: :vertical) }
        @editor.focus_window(first_win_id)
      when :tab
        rest.each { |p| open_path_in_tab!(p) }
        @editor.tabnext(-(@editor.tabpage_count - 1))
      else
        rest.each do |p|
          buf = @editor.add_buffer_from_file(p)
          @stream_mixer.start_follow!(buf) if @startup.follow
        end
      end
    end

    def evict_bootstrap_buffer!
      bid = @editor.buffer_ids.find do |id|
        b = @editor.buffers[id]
        b.path.nil? && !b.modified? && b.line_count <= 1 && b.kind == :file
      end
      return unless bid

      @editor.buffers.delete(bid)
      @editor.instance_variable_set(:@next_buffer_id, 1)
    end

    def open_path_in_split!(path, layout:)
      @editor.split_current_window(layout:)
      @editor.open_path(path)
      apply_startup_buffer_flags!
    end

    def open_path_in_tab!(path)
      @editor.tabnew(path:)
      apply_startup_buffer_flags!
    end

    def move_cursor_to_line(line_number)
      win = @editor.current_window
      buf = @editor.current_buffer
      return unless win && buf

      target = [[line_number - 1, 0].max, buf.line_count - 1].min
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
