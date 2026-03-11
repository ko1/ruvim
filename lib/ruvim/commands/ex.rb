# frozen_string_literal: true

require "tempfile"
require "open3"

module RuVim
  module Commands
    # Ex commands: help, set, bindings, ruby, run, shell, read, range operations,
    # quickfix/location list, spell, define command
    module Ex
      def ex_help(ctx, argv: [], **)
        topic = argv.first.to_s
        registry = RuVim::ExCommandRegistry.instance

        if topic.empty?
          lines = [
            "RuVim help",
            "",
            "Topics:",
            "  :help commands",
            "  :help regex",
            "  :help options",
            "  :help config",
            "  :help bindings",
            "",
            "Ex command help:",
            "  :help w",
            "  :help set",
            "  :help buffer"
          ]
          ctx.editor.show_help_buffer!(title: "[Help] help", lines:)
          return
        end

        key = topic.downcase
        text =
        case key
        when "commands", "command"
          "Ex commands: use :commands (list), :help <name> (detail)"
        when "regex", "search"
          "Regex uses Ruby Regexp (not Vim regex). :%s/pat/rep/g is minimal parser + Ruby regex."
        when "options", "set"
          "Options: use :set/:setlocal/:setglobal. See :help number, :help relativenumber, :help ignorecase, :help smartcase, :help hlsearch"
        when "config"
          "Config: XDG Ruby DSL at ~/.config/ruvim/init.rb and ftplugin/<filetype>.rb"
        when "bindings", "keys", "keymap"
          "Bindings: use :bindings (current effective key bindings by layer). Docs: docs/binding.md"
        when "number", "relativenumber", "ignorecase", "smartcase", "hlsearch", "tabstop", "filetype"
          option_help_line(key)
        else
          if (spec = registry.resolve(topic))
            ex_command_help_line(spec)
          else
            "No help for #{topic}. Try :help or :help commands"
          end
        end
        ctx.editor.show_help_buffer!(title: "[Help] #{topic}", lines: help_text_to_lines(topic, text))
      end

      def ex_define_command(ctx, argv:, bang:, **)
        registry = RuVim::ExCommandRegistry.instance
        if argv.empty?
          user_cmds = registry.all.select { |spec| spec.source == :user }
          if user_cmds.empty?
            ctx.editor.echo("No user commands")
          else
            header = "    Name        Definition"
            items = [header] + user_cmds.map { |spec|
              body = spec.respond_to?(:body) ? spec.body.to_s : spec.name.to_s
              "    %-12s%s" % [spec.name, body]
            }
            ctx.editor.echo_multiline(items)
          end
          return
        end

        name = argv[0].to_s
        body_tokens = argv[1..] || []
        raise RuVim::CommandError, "Usage: :command Name ex_body" if body_tokens.empty?

        if registry.registered?(name)
          unless bang
            raise RuVim::CommandError, "Command exists: #{name} (use :command! to replace)"
          end
          registry.unregister(name)
        end

        body = body_tokens.join(" ")
        handler = lambda do |inner_ctx, argv:, **_k|
          expanded = [body, *argv].join(" ").strip
          Dispatcher.new.dispatch_ex(inner_ctx.editor, expanded)
        end

        registry.register(name, call: handler, desc: "user-defined", nargs: :any, bang: true, source: :user)
        ctx.editor.echo("Defined :#{name}")
      end

      def ex_ruby(ctx, argv:, **)
        raise RuVim::CommandError, "Restricted mode: :ruby is disabled" if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

        code = argv.join(" ")
        raise RuVim::CommandError, "Usage: :ruby <code>" if code.strip.empty?

        b = binding
        # Use local_variable_set for eval locals to avoid "assigned but unused variable"
        # warnings while still exposing editor/buffer/window in :ruby.
        b.local_variable_set(:editor, ctx.editor)
        b.local_variable_set(:buffer, ctx.buffer)
        b.local_variable_set(:window, ctx.window)
        saved_stdout = STDOUT.dup
        saved_stderr = STDERR.dup
        original_g_stdout = $stdout
        original_g_stderr = $stderr
        result = nil
        stdout_text = ""
        stderr_text = ""
        Tempfile.create("ruvim-ruby-stdout") do |outf|
          Tempfile.create("ruvim-ruby-stderr") do |errf|
            STDOUT.reopen(outf)
            STDERR.reopen(errf)
            $stdout = STDOUT
            $stderr = STDERR
            result = eval(code, b) # rubocop:disable Security/Eval
            STDOUT.flush
            STDERR.flush
            outf.flush
            errf.flush
            outf.rewind
            errf.rewind
            stdout_text = outf.read
            stderr_text = errf.read
          end
        end
        if !stdout_text.empty? || !stderr_text.empty?
          lines = ["Ruby output", ""]
          unless stdout_text.empty?
            lines << "[stdout]"
            lines.concat(stdout_text.lines(chomp: true))
            lines << ""
          end
          unless stderr_text.empty?
            lines << "[stderr]"
            lines.concat(stderr_text.lines(chomp: true))
            lines << ""
          end
          lines << "[result]"
          lines << (result.nil? ? "nil" : result.inspect)
          ctx.editor.show_help_buffer!(title: "[Ruby Output]", lines:, filetype: "ruby")
        else
          ctx.editor.echo(result.nil? ? "ruby: nil" : "ruby: #{result.inspect}")
        end
      rescue StandardError => e
        raise RuVim::CommandError, "Ruby error: #{e.class}: #{e.message}"
      ensure
        if defined?(saved_stdout) && saved_stdout
          STDOUT.reopen(saved_stdout)
          saved_stdout.close unless saved_stdout.closed?
        end
        if defined?(saved_stderr) && saved_stderr
          STDERR.reopen(saved_stderr)
          saved_stderr.close unless saved_stderr.closed?
        end
        $stdout = (defined?(original_g_stdout) && original_g_stdout) ? original_g_stdout : STDOUT
        $stderr = (defined?(original_g_stderr) && original_g_stderr) ? original_g_stderr : STDERR
      end

      def ex_run(ctx, argv:, **)
        editor = ctx.editor
        source_buffer = ctx.buffer

        if argv.empty?
          # No args: use last command for this buffer, or runprg
          command = editor.run_history[source_buffer.id]
          if command.nil?
            runprg = editor.get_option("runprg", buffer: source_buffer)
            raise RuVim::CommandError, "No runprg set and no previous :run command" unless runprg
            command = runprg
          end
        else
          command = argv.first
        end

        # Auto-save modified buffer before running
        if source_buffer.modified? && source_buffer.path
          source_buffer.write_to
        end

        expanded = expand_run_command(command, source_buffer)
        editor.run_history[source_buffer.id] = command

        # Find or create [Shell Output] buffer
        output_buf = if editor.run_output_buffer_id
                       editor.buffers[editor.run_output_buffer_id]
                     end

        if output_buf
          # Reuse: clear content
          output_buf.replace_all_lines!([""])
        else
          output_buf = editor.add_virtual_buffer(
            kind: :run_output,
            name: "[Shell Output]",
            lines: [""],
            readonly: true,
            modifiable: false
          )
          editor.run_output_buffer_id = output_buf.id
        end
        # Open output buffer in a split (reuse existing window if present)
        existing_win = editor.windows.values.find { |w| w.buffer_id == output_buf.id }
        if existing_win
          editor.current_window_id = existing_win.id
        else
          win = editor.split_current_window(layout: :horizontal, place: :after)
          win.buffer_id = output_buf.id
          win.cursor_x = 0
          win.cursor_y = 0
          win.row_offset = 0
        end

        # Start streaming (falls back to synchronous for tests without stream_mixer)
        unless editor.start_stream!(output_buf, expanded)
          shell = ENV["SHELL"].to_s
          shell = "/bin/sh" if shell.empty?
          output, _status = Open3.capture2e(shell, "-c", expanded)
          output_buf.replace_all_lines!(output.lines(chomp: true))
        end
      end

      def ex_shell(ctx, command:, **)
        raise RuVim::CommandError, "Restricted mode: :! is disabled" if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

        raise RuVim::CommandError, "Usage: :!<command>" if command.strip.empty?

        executor = ctx.editor.shell_executor
        if executor
          status = executor.call(command)
          ctx.editor.echo("shell exit #{status.exitstatus}")
        else
          shell = ENV["SHELL"].to_s
          shell = "/bin/sh" if shell.empty?
          stdout_text, stderr_text, status = Open3.capture3(shell, "-c", command)

          if !stdout_text.empty? || !stderr_text.empty?
            lines = ["Shell output", "", "[command]", command, ""]
            unless stdout_text.empty?
              lines << "[stdout]"
              lines.concat(stdout_text.lines(chomp: true))
              lines << ""
            end
            unless stderr_text.empty?
              lines << "[stderr]"
              lines.concat(stderr_text.lines(chomp: true))
              lines << ""
            end
            lines << "[status]"
            lines << "exit #{status.exitstatus}"
            ctx.editor.show_help_buffer!(title: "[Shell Output]", lines:, filetype: "sh")
          else
            ctx.editor.echo("shell exit #{status.exitstatus}")
          end
        end
      rescue Errno::ENOENT => e
        raise RuVim::CommandError, "Shell error: #{e.message}"
      end

      def ex_read(ctx, argv:, kwargs:, **)
        arg = argv.join(" ")
        raise RuVim::CommandError, "Usage: :r[ead] [file] or :r[ead] !command" if arg.strip.empty?

        insert_line = kwargs[:range_start] || ctx.window.cursor_y
        new_lines = if arg.start_with?("!")
                      command = arg[1..].strip
                      raise RuVim::CommandError, "Usage: :r !<command>" if command.empty?

                      shell = ENV["SHELL"].to_s
                      shell = "/bin/sh" if shell.empty?
                      stdout_text, stderr_text, _status = Open3.capture3(shell, "-c", command)
                      unless stderr_text.empty?
                        ctx.editor.echo_error(stderr_text.lines(chomp: true).first)
                      end
                      stdout_text.lines(chomp: true)
                    else
                      path = File.expand_path(arg.strip)
                      raise RuVim::CommandError, "File not found: #{arg.strip}" unless File.exist?(path)

                      File.read(path).lines(chomp: true)
                    end

        return if new_lines.empty?

        ctx.buffer.insert_lines_at(insert_line + 1, new_lines)
        ctx.window.cursor_y = insert_line + new_lines.length
        ctx.editor.echo("#{new_lines.length} line(s) inserted")
      end

      def ex_commands(ctx, **)
        rows = RuVim::ExCommandRegistry.instance.all.map do |spec|
          alias_text = spec.aliases.empty? ? "" : " (#{spec.aliases.join(', ')})"
          source = spec.source == :user ? " [user]" : ""
          name = "#{spec.name}#{alias_text}#{source}"
          desc = spec.desc
          keys = ex_command_binding_labels(ctx.editor, spec)
          [name, desc, keys]
        end
        name_width = rows.map { |name, _desc, _keys| name.length }.max || 0
        items = rows.map do |name, desc, keys|
          line = "#{name.ljust(name_width)}  #{desc}"
          line += "  keys: #{keys.join(', ')}" unless keys.empty?
          line
        end
        ctx.editor.show_help_buffer!(title: "[Commands]", lines: ["Ex commands", "", *items])
      end

      def ex_bindings(ctx, argv: [], **)
        keymaps = ctx.editor.keymap_manager
        raise RuVim::CommandError, "Keymap manager is unavailable" unless keymaps

        mode_filter, sort = parse_bindings_args(argv)
        entries = keymaps.binding_entries_for_context(ctx.editor, mode: mode_filter)
        lines = bindings_buffer_lines(ctx.editor, entries, mode_filter:, sort:)
        ctx.editor.show_help_buffer!(title: "[Bindings]", lines:)
      end

      def ex_set(ctx, argv:, **)
        ex_set_common(ctx, argv, scope: :auto)
      end

      def ex_setlocal(ctx, argv:, **)
        ex_set_common(ctx, argv, scope: :local)
      end

      def ex_setglobal(ctx, argv:, **)
        ex_set_common(ctx, argv, scope: :global)
      end

      def ex_vimgrep(ctx, argv:, **)
        pattern = parse_vimgrep_pattern(argv)
        regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
        items = grep_items_for_buffers(ctx.editor.buffers.values.select(&:file_buffer?), regex)
        if items.empty?
          ctx.editor.echo_error("Pattern not found: #{pattern}")
          return
        end

        ctx.editor.set_quickfix_list(items)
        ctx.editor.select_quickfix(0)
        ctx.editor.jump_to_location(ctx.editor.current_quickfix_item)
        ctx.editor.echo("quickfix: #{items.length} item(s)")
      end

      def ex_lvimgrep(ctx, argv:, **)
        pattern = parse_vimgrep_pattern(argv)
        regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
        items = grep_items_for_buffers([ctx.buffer], regex)
        if items.empty?
          ctx.editor.echo_error("Pattern not found: #{pattern}")
          return
        end

        ctx.editor.set_location_list(items, window_id: ctx.window.id)
        ctx.editor.select_location_list(0, window_id: ctx.window.id)
        ctx.editor.jump_to_location(ctx.editor.current_location_list_item(ctx.window.id))
        ctx.editor.echo("location list: #{items.length} item(s)")
      end

      def ex_copen(ctx, **)
        open_list_window(ctx, kind: :quickfix, title: "[Quickfix]", lines: quickfix_buffer_lines(ctx.editor), source_window_id: ctx.window.id)
      end

      def ex_cclose(ctx, **)
        close_list_windows(ctx.editor, :quickfix)
      end

      def ex_cnext(ctx, **)
        item = ctx.editor.move_quickfix(+1)
        unless item
          ctx.editor.echo_error("quickfix list is empty")
          return
        end
        ctx.editor.jump_to_location(item)
        refresh_list_window(ctx.editor, :quickfix)
        ctx.editor.echo(quickfix_item_echo(ctx.editor))
      end

      def ex_cprev(ctx, **)
        item = ctx.editor.move_quickfix(-1)
        unless item
          ctx.editor.echo_error("quickfix list is empty")
          return
        end
        ctx.editor.jump_to_location(item)
        refresh_list_window(ctx.editor, :quickfix)
        ctx.editor.echo(quickfix_item_echo(ctx.editor))
      end

      def spell_next(ctx, count:, **)
        return unless spell_enabled?(ctx)

        cnt = normalized_count(count)
        checker = ctx.editor.spell_checker
        buf = ctx.buffer
        win = ctx.window
        y = win.cursor_y
        x = win.cursor_x

        cnt.times do
          found = find_next_misspelled(checker, buf, y, x)
          unless found
            ctx.editor.echo_error("No misspelled word found")
            return
          end
          y, x = found
        end
        win.cursor_y = y
        win.cursor_x = x
      end

      def spell_prev(ctx, count:, **)
        return unless spell_enabled?(ctx)

        cnt = normalized_count(count)
        checker = ctx.editor.spell_checker
        buf = ctx.buffer
        win = ctx.window
        y = win.cursor_y
        x = win.cursor_x

        cnt.times do
          found = find_prev_misspelled(checker, buf, y, x)
          unless found
            ctx.editor.echo_error("No misspelled word found")
            return
          end
          y, x = found
        end
        win.cursor_y = y
        win.cursor_x = x
      end

      def ex_lopen(ctx, **)
        open_list_window(ctx, kind: :location_list, title: "[Location List]", lines: location_list_buffer_lines(ctx.editor, ctx.window.id),
                         source_window_id: ctx.window.id)
      end

      def ex_lclose(ctx, **)
        close_list_windows(ctx.editor, :location_list)
      end

      def ex_lnext(ctx, **)
        item = ctx.editor.move_location_list(+1, window_id: ctx.window.id)
        unless item
          ctx.editor.echo_error("location list is empty")
          return
        end
        ctx.editor.jump_to_location(item)
        refresh_list_window(ctx.editor, :location_list)
        ctx.editor.echo(location_item_echo(ctx.editor, ctx.window.id))
      end

      def ex_lprev(ctx, **)
        item = ctx.editor.move_location_list(-1, window_id: ctx.window.id)
        unless item
          ctx.editor.echo_error("location list is empty")
          return
        end
        ctx.editor.jump_to_location(item)
        refresh_list_window(ctx.editor, :location_list)
        ctx.editor.echo(location_item_echo(ctx.editor, ctx.window.id))
      end

      def ex_delete_lines(ctx, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          # Default to current line
          r_start = r_end = ctx.window.cursor_y
        end

        count = r_end - r_start + 1
        deleted_text = ctx.buffer.line_block_text(r_start, count)
        ctx.buffer.begin_change_group
        count.times { ctx.buffer.delete_line(r_start) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted_text, type: :linewise)
        ctx.window.cursor_y = [r_start, ctx.buffer.line_count - 1].min
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("#{count} line(s) deleted")
      end

      def ex_yank_lines(ctx, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        count = r_end - r_start + 1
        text = ctx.buffer.line_block_text(r_start, count)
        store_yank_register(ctx, text:, type: :linewise)
        ctx.editor.echo("#{count} line(s) yanked")
      end

      def ex_print_lines(ctx, kwargs: {}, **)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        lines = (r_start..r_end).map { |row| ctx.buffer.line_at(row) }
        ctx.editor.echo(lines.join("\n"))
      end

      def ex_number_lines(ctx, kwargs: {}, **)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        lines = (r_start..r_end).map { |row| "#{row + 1}\t#{ctx.buffer.line_at(row)}" }
        ctx.editor.echo(lines.join("\n"))
      end

      def ex_move_lines(ctx, argv:, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        dest = argv.join(" ").strip
        raise RuVim::CommandError, "Argument required" if dest.empty?

        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        dest_row = resolve_ex_address(dest, ctx)

        count = r_end - r_start + 1
        lines = (r_start..r_end).map { |row| ctx.buffer.line_at(row) }

        ctx.buffer.begin_change_group
        count.times { ctx.buffer.delete_line(r_start) }
        insert_at = dest_row >= r_start ? dest_row - count + 1 : dest_row + 1
        insert_at = [[insert_at, 0].max, ctx.buffer.line_count].min
        ctx.buffer.insert_lines_at(insert_at, lines)
        ctx.buffer.end_change_group

        ctx.window.cursor_y = [insert_at + count - 1, ctx.buffer.line_count - 1].min
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("#{count} line(s) moved")
      end

      def ex_copy_lines(ctx, argv:, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        dest = argv.join(" ").strip
        raise RuVim::CommandError, "Argument required" if dest.empty?

        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        dest_row = resolve_ex_address(dest, ctx)

        count = r_end - r_start + 1
        lines = (r_start..r_end).map { |row| ctx.buffer.line_at(row) }

        insert_at = dest_row + 1
        insert_at = [[insert_at, 0].max, ctx.buffer.line_count].min
        ctx.buffer.insert_lines_at(insert_at, lines)

        ctx.window.cursor_y = [insert_at + count - 1, ctx.buffer.line_count - 1].min
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("#{count} line(s) copied")
      end

      def ex_join_lines(ctx, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = ctx.window.cursor_y
          r_end = [r_start + 1, ctx.buffer.line_count - 1].min
        end
        return if r_start >= r_end

        ctx.buffer.begin_change_group
        row = r_start
        (r_end - r_start).times do
          break if row >= ctx.buffer.line_count - 1

          left = ctx.buffer.line_at(row)
          right = ctx.buffer.line_at(row + 1)
          join_col = left.length
          ctx.buffer.delete_char(row, join_col)

          right_trimmed = right.sub(/\A\s+/, "")
          trimmed_count = right.length - right_trimmed.length
          if trimmed_count.positive?
            ctx.buffer.delete_span(row, join_col, row, join_col + trimmed_count)
          end

          need_space = !left.empty? && !left.match?(/\s\z/) && !right_trimmed.empty?
          if need_space
            ctx.buffer.insert_char(row, join_col, " ")
          end
        end
        ctx.buffer.end_change_group

        ctx.window.cursor_y = r_start
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def ex_shift_right(ctx, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        sw = ctx.editor.effective_option("shiftwidth", buffer: ctx.buffer).to_i
        sw = 2 if sw <= 0
        indent = " " * sw

        ctx.buffer.begin_change_group
        (r_start..r_end).each do |row|
          ctx.buffer.replace_line!(row, indent + ctx.buffer.line_at(row))
        end
        ctx.buffer.end_change_group
      end

      def ex_shift_left(ctx, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]
        unless r_start && r_end
          r_start = r_end = ctx.window.cursor_y
        end

        sw = ctx.editor.effective_option("shiftwidth", buffer: ctx.buffer).to_i
        sw = 2 if sw <= 0

        ctx.buffer.begin_change_group
        (r_start..r_end).each do |row|
          line = ctx.buffer.line_at(row)
          stripped = line.sub(/\A {1,#{sw}}/, "")
          ctx.buffer.replace_line!(row, stripped) if stripped != line
        end
        ctx.buffer.end_change_group
      end

      def ex_normal(ctx, argv:, kwargs: {}, **)
        materialize_intro_buffer_if_needed(ctx)
        keys_str = argv.join(" ")
        raise RuVim::CommandError, "Argument required" if keys_str.empty?

        feeder = ctx.editor.normal_key_feeder
        raise RuVim::CommandError, ":normal not available" unless feeder

        keys = parse_normal_keys(keys_str)

        r_start = kwargs[:range_start]
        r_end = kwargs[:range_end]

        unless r_start && r_end
          # No range: execute once at current cursor position
          ctx.editor.enter_normal_mode unless ctx.editor.mode == :normal
          feeder.call(keys)
          return
        end

        ctx.buffer.begin_change_group
        begin
          offset = 0
          (r_start..r_end).each do |orig_row|
            row = orig_row + offset
            break if row >= ctx.buffer.line_count

            prev_count = ctx.buffer.line_count
            ctx.window.cursor_y = row
            ctx.window.cursor_x = 0
            ctx.editor.enter_normal_mode unless ctx.editor.mode == :normal
            feeder.call(keys)
            offset += ctx.buffer.line_count - prev_count
          end
        ensure
          ctx.buffer.end_change_group
        end

        ctx.editor.enter_normal_mode unless ctx.editor.mode == :normal
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      private

      def expand_run_command(command, buffer)
        return command unless command.include?("%")

        path = buffer.path
        raise RuVim::CommandError, "No file name (use % in :run requires a file)" unless path

        command.gsub("%", path)
      end

      def resolve_ex_address(addr_str, ctx)
        str = addr_str.to_s.strip
        case str
        when "$"
          ctx.buffer.line_count - 1
        when "."
          ctx.window.cursor_y
        when /\A\d+\z/
          str.to_i - 1
        when "0"
          -1
        else
          dispatcher = RuVim::Dispatcher.new
          result = dispatcher.parse_address(str, 0, ctx.editor)
          raise RuVim::CommandError, "Invalid address: #{addr_str}" unless result
          result[0]
        end
      end

      def parse_normal_keys(str)
        keys = []
        i = 0
        while i < str.length
          ch = str[i]
          if ch == "\\"
            nxt = str[i + 1]
            if nxt
              keys << nxt
              i += 2
              next
            end
          end
          keys << ch
          i += 1
        end
        keys
      end

      def quickfix_buffer_lines(editor)
        items = editor.quickfix_items
        return ["Quickfix", "", "(empty)"] if items.empty?

        idx = editor.quickfix_index || 0
        build_list_buffer_lines(editor, items, idx, title: "Quickfix")
      end

      def location_list_buffer_lines(editor, window_id)
        items = editor.location_items(window_id)
        idx = editor.location_list(window_id)[:index] || 0
        return ["Location List", "", "(empty)"] if items.empty?

        build_list_buffer_lines(editor, items, idx, title: "Location List")
      end

      def build_list_buffer_lines(editor, items, current_index, title:)
        [
          title,
          "",
          *items.each_with_index.map do |it, i|
            b = editor.buffers[it[:buffer_id]]
            path = b&.display_name || "(missing)"
            mark = i == current_index ? ">" : " "
            "#{mark} #{i + 1}: #{path}:#{it[:row] + 1}:#{it[:col] + 1}: #{it[:text]}"
          end
        ]
      end

      def open_list_window(ctx, kind:, title:, lines:, source_window_id:)
        editor = ctx.editor
        editor.split_current_window(layout: :horizontal)
        buffer = editor.add_virtual_buffer(kind:, name: title, lines:, filetype: "qf", readonly: true, modifiable: false)
        buffer.options["ruvim_list_source_window_id"] = source_window_id
        editor.switch_to_buffer(buffer.id)
        editor.echo(title)
        buffer
      end

      def close_list_windows(editor, kind)
        ids = editor.find_window_ids_by_buffer_kind(kind)
        if ids.empty?
          editor.echo_error("#{kind} window is not open")
          return
        end

        ids.each do |wid|
          break if editor.window_count <= 1
          editor.close_window(wid)
        end
        editor.echo("#{kind} closed")
      end

      def refresh_list_window(editor, kind)
        wids = editor.find_window_ids_by_buffer_kind(kind)
        return if wids.empty?

        lines = case kind
                when :quickfix then quickfix_buffer_lines(editor)
                when :location_list then location_list_buffer_lines(editor, editor.current_window_id)
                end
        wids.each do |wid|
          buf = editor.buffers[editor.windows[wid].buffer_id]
          next unless buf
          # Bypass modifiable check — this is an internal refresh of a readonly list buffer
          buf.instance_variable_set(:@lines, Array(lines).map(&:dup))
        end
      end

      def quickfix_item_echo(editor)
        item = editor.current_quickfix_item
        list_item_echo(editor, item, editor.quickfix_index, editor.quickfix_items.length, label: "qf")
      end

      def location_item_echo(editor, window_id)
        item = editor.current_location_list_item(window_id)
        list = editor.location_list(window_id)
        list_item_echo(editor, item, list[:index], list[:items].length, label: "ll")
      end

      def list_item_echo(editor, item, index, total, label:)
        return "#{label}: empty" unless item

        b = editor.buffers[item[:buffer_id]]
        "#{label} #{index.to_i + 1}/#{total}: #{b&.display_name || '(missing)'}:#{item[:row] + 1}:#{item[:col] + 1}"
      end

      def ex_set_common(ctx, argv, scope:)
        editor = ctx.editor
        if argv.empty?
          items = editor.option_snapshot(window: ctx.window, buffer: ctx.buffer).map do |opt|
            format_option_value(opt[:name], opt[:effective])
          end
          ctx.editor.echo_multiline(items)
          return
        end

        output = []
        argv.each do |token|
          output.concat(handle_set_token(ctx, token, scope:))
        end
        ctx.editor.echo(output.join(" ")) unless output.empty?
      end

      def handle_set_token(ctx, token, scope:)
        t = token.to_s
        return [] if t.empty?

        if t.end_with?("?")
          name = t[0...-1]
          val = ctx.editor.get_option(name, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
          return ["#{name}=#{format_option_scalar(val)}"]
        end

        if t.start_with?("no")
          name = t[2..]
          return [apply_bool_option(ctx, name, false, scope:)]
        end

        if t.start_with?("inv")
          name = t[3..]
          cur = !!ctx.editor.get_option(name, scope: :effective, window: ctx.window, buffer: ctx.buffer)
          return [apply_bool_option(ctx, name, !cur, scope:)]
        end

        if t.include?("=")
          name, raw = t.split("=", 2)
          val = parse_option_value(ctx.editor, name, raw)
          applied = ctx.editor.set_option(name, val, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
          return ["#{name}=#{format_option_scalar(applied)}"]
        end

        if bool_option?(ctx.editor, t)
          return [apply_bool_option(ctx, t, true, scope:)]
        end

        val = ctx.editor.get_option(t, scope: resolve_option_scope(ctx.editor, t, scope), window: ctx.window, buffer: ctx.buffer)
        ["#{t}=#{format_option_scalar(val)}"]
      end

      def apply_bool_option(ctx, name, value, scope:)
        unless bool_option?(ctx.editor, name)
          raise RuVim::CommandError, "#{name} is not a boolean option"
        end
        applied = ctx.editor.set_option(name, value, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
        applied ? name.to_s : "no#{name}"
      end

      def resolve_option_scope(editor, name, requested_scope)
        case requested_scope
        when :auto
          :auto
        when :global
          :global
        when :local
          editor.option_default_scope(name) == :buffer ? :buffer : :window
        else
          requested_scope
        end
      end

      def parse_option_value(editor, name, raw)
        defn = editor.option_def(name)
        return raw unless defn

        case defn[:type]
        when :bool
          parse_bool(raw)
        when :int
          Integer(raw)
        else
          raw
        end
      rescue ArgumentError
        raise RuVim::CommandError, "Invalid value for #{name}: #{raw}"
      end

      def parse_bool(raw)
        case raw.to_s.downcase
        when "1", "true", "on", "yes" then true
        when "0", "false", "off", "no" then false
        else
          raise ArgumentError
        end
      end

      def bool_option?(editor, name)
        editor.option_def(name)&.dig(:type) == :bool
      end

      def format_option_value(name, value)
        if value == true
          name.to_s
        elsif value == false
          "no#{name}"
        else
          "#{name}=#{format_option_scalar(value)}"
        end
      end

      def format_option_scalar(value)
        value.nil? ? "nil" : value.to_s
      end

      def ex_command_help_line(spec)
        aliases = spec.aliases.empty? ? "" : " aliases=#{spec.aliases.join(',')}"
        nargs = " nargs=#{spec.nargs}"
        bang = spec.bang ? " !" : ""
        src = spec.source == :user ? " [user]" : ""
        ":#{spec.name}#{bang} - #{spec.desc}#{aliases}#{nargs}#{src}"
      end

      def option_help_line(name)
        case name
        when "number"
          "number (bool, window-local): line numbers. :set number / :set nonumber"
        when "tabstop"
          "tabstop (int, buffer-local): tab display width. ex: :set tabstop=4"
        when "relativenumber"
          "relativenumber (bool, window-local): show relative line numbers. ex: :set relativenumber"
        when "ignorecase"
          "ignorecase (bool, global): case-insensitive search unless smartcase + uppercase pattern"
        when "smartcase"
          "smartcase (bool, global): with ignorecase, uppercase in pattern makes search case-sensitive"
        when "hlsearch"
          "hlsearch (bool, global): highlight search matches on screen"
        when "filetype"
          "filetype (string, buffer-local): used for ftplugin and filetype-local keymaps"
        else
          "No option help: #{name}"
        end
      end

      def help_text_to_lines(topic, text)
        [
          "RuVim help: #{topic}",
          "",
          *text.to_s.scan(/.{1,78}(?:\s+|$)|.{1,78}/).map(&:rstrip)
        ]
      end

      def parse_bindings_args(argv)
        mode_filter = nil
        sort = "key"

        Array(argv).each do |raw|
          token = raw.to_s.strip
          next if token.empty?

          if token.include?("=")
            key, value = token.split("=", 2).map(&:strip)
            case key.downcase
            when "sort"
              sort = parse_bindings_sort(value)
            else
              raise RuVim::CommandError, "Unknown option for :bindings: #{key}"
            end
            next
          end

          raise RuVim::CommandError, "Too many positional args for :bindings" if mode_filter

          mode_filter = parse_bindings_mode_filter(token)
        end

        [mode_filter, sort]
      end

      def parse_bindings_sort(raw)
        token = raw.to_s.strip.downcase
        case token
        when "", "key", "keys" then "key"
        when "command", "cmd" then "command"
        else
          raise RuVim::CommandError, "Unknown sort for :bindings: #{raw}"
        end
      end

      def parse_bindings_mode_filter(raw)
        return nil if raw.nil? || raw.to_s.strip.empty?

        token = raw.to_s.strip.downcase
        case token
        when "n", "normal" then :normal
        when "i", "insert" then :insert
        when "v", "visual", "visual_char" then :visual_char
        when "vl", "visual_line" then :visual_line
        when "vb", "visual_block", "x" then :visual_block
        when "o", "operator", "operator_pending" then :operator_pending
        when "c", "cmdline", "command", "command_line" then :command_line
        else
          raise RuVim::CommandError, "Unknown mode for :bindings: #{raw}"
        end
      end

      def bindings_buffer_lines(editor, entries, mode_filter:, sort:)
        buffer = editor.current_buffer
        filetype = buffer.options["filetype"].to_s
        filetype = nil if filetype.empty?

        lines = [
          "Bindings",
          "",
          "Buffer: #{buffer.display_name}",
          "Filetype: #{filetype || '-'}",
          "Mode filter: #{mode_filter || 'all'}",
          "Sort: #{sort}",
          ""
        ]

        any = false
        %i[buffer filetype app].each do |layer|
          layer_entries = entries.select { |e| e.layer == layer }
          next if layer_entries.empty?

          any = true
          lines << "Layer: #{layer}"
          append_binding_entries_grouped!(lines, layer_entries, layer:, sort:)
          lines << ""
        end

        lines << "(no bindings)" unless any
        lines
      end

      def append_binding_entries_grouped!(lines, entries, layer:, sort:)
        groups = entries.group_by do |e|
          if layer == :app && e.scope == :global
            [:global, nil]
          elsif e.mode
            [:mode, e.mode]
          else
            [:plain, nil]
          end
        end

        groups.keys.sort_by { |kind, mode| binding_group_sort_key(kind, mode) }.each do |kind, mode|
          group_entries = groups[[kind, mode]]
          next if group_entries.nil? || group_entries.empty?

          if kind == :global
            lines << "  [global]"
          elsif mode
            lines << "  [#{mode}]"
          end

          group_entries = sort_binding_entries(group_entries, sort:)
          parts = group_entries.map { |entry| binding_entry_display_parts(entry) }
          rhs_width = parts.map { |_, rhs, _| rhs.length }.max || 0
          parts.each do |lhs, rhs, desc|
            lines << format_binding_entry_line(lhs, rhs, desc, rhs_width:)
          end
        end
      end

      def binding_group_sort_key(kind, mode)
        rank =
          case kind
          when :plain then 0
          when :mode then 1
          when :global then 2
          else 9
          end
        [rank, binding_mode_order_index(mode), mode.to_s]
      end

      def binding_mode_order_index(mode)
        return -1 if mode.nil?

        order = {
          normal: 0,
          insert: 1,
          visual_char: 2,
          visual_line: 3,
          visual_block: 4,
          operator_pending: 5,
          command_line: 6
        }
        order.fetch(mode, 99)
      end

      def sort_binding_entries(entries, sort:)
        case sort.to_s
        when "command"
          entries.sort_by do |e|
            [e.id.to_s, format_binding_tokens(e.tokens), e.bang ? 1 : 0, e.argv.inspect, e.kwargs.inspect]
          end
        else
          entries
        end
      end

      def binding_entry_display_parts(entry)
        lhs = format_binding_tokens(entry.tokens)
        rhs = entry.id.to_s
        rhs += "!" if entry.bang
        rhs += " argv=#{entry.argv.inspect}" unless entry.argv.nil? || entry.argv.empty?
        rhs += " kwargs=#{entry.kwargs.inspect}" unless entry.kwargs.nil? || entry.kwargs.empty?
        desc = binding_command_desc(entry.id)
        [lhs, rhs, desc.to_s]
      end

      def format_binding_entry_line(lhs, rhs, desc, rhs_width:)
        line = "    #{lhs.ljust(18)} #{rhs.ljust(rhs_width)}"
        line += "    #{desc}" unless desc.to_s.empty?
        line
      end

      def format_binding_tokens(tokens)
        Array(tokens).map { |t| format_binding_token(t) }.join
      end

      def format_binding_token(token)
        case token.to_s
        when "\e" then "<Esc>"
        when "\t" then "<Tab>"
        when "\r" then "<CR>"
        else token.to_s
        end
      end

      def binding_command_desc(command_id)
        RuVim::CommandRegistry.instance.fetch(command_id).desc.to_s
      rescue StandardError
        ""
      end

      def ex_command_binding_labels(editor, ex_spec)
        keymaps = editor.keymap_manager
        return [] unless keymaps

        command_ids = command_ids_for_ex_callable(ex_spec.call)
        return [] if command_ids.empty?

        entries = keymaps.binding_entries_for_context(editor).select do |entry|
          entry.layer == :app && command_ids.include?(entry.id.to_s)
        end
        entries.sort_by do |entry|
          [binding_mode_order_index(entry.mode), entry.scope == :global ? 1 : 0, format_binding_tokens(entry.tokens)]
        end.map do |entry|
          format_ex_command_binding_label(entry)
        end.uniq
      end

      def command_ids_for_ex_callable(callable)
        RuVim::CommandRegistry.instance.all.filter_map do |spec|
          spec.id if same_command_callable?(spec.call, callable)
        end
      end

      def same_command_callable?(a, b)
        if (a.is_a?(Symbol) || a.is_a?(String)) && (b.is_a?(Symbol) || b.is_a?(String))
          return a.to_sym == b.to_sym
        end
        a.equal?(b)
      end

      def format_ex_command_binding_label(entry)
        lhs = format_binding_tokens(entry.tokens)
        if entry.scope == :global
          "global:#{lhs}"
        elsif entry.mode && entry.mode != :normal
          "#{entry.mode}:#{lhs}"
        else
          lhs
        end
      end

      def spell_enabled?(ctx)
        !!ctx.editor.effective_option("spell", window: ctx.window, buffer: ctx.buffer)
      end

      def find_next_misspelled(checker, buf, start_y, start_x)
        line_count = buf.line_count
        # Search from current line forward
        (start_y...line_count).each do |y|
          line = buf.lines[y]
          misspelled = checker.misspelled_words(line)
          misspelled.each do |m|
            next if y == start_y && m[:col] <= start_x
            return [y, m[:col]]
          end
        end
        # Wrap around from the beginning
        (0..start_y).each do |y|
          line = buf.lines[y]
          misspelled = checker.misspelled_words(line)
          misspelled.each do |m|
            next if y == start_y && m[:col] <= start_x
            return [y, m[:col]]
          end
        end
        nil
      end

      def find_prev_misspelled(checker, buf, start_y, start_x)
        # Search from current line backward
        start_y.downto(0) do |y|
          line = buf.lines[y]
          misspelled = checker.misspelled_words(line).reverse
          misspelled.each do |m|
            next if y == start_y && m[:col] >= start_x
            return [y, m[:col]]
          end
        end
        # Wrap around from the end
        (buf.line_count - 1).downto(start_y) do |y|
          line = buf.lines[y]
          misspelled = checker.misspelled_words(line).reverse
          misspelled.each do |m|
            next if y == start_y && m[:col] >= start_x
            return [y, m[:col]]
          end
        end
        nil
      end
    end
  end
end
