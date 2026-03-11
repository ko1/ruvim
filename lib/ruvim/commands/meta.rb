# frozen_string_literal: true

require "tempfile"
require "open3"

module RuVim
  module Commands
    # Meta commands: help, set, bindings, ruby eval, run, shell, define command, normal exec
    module Meta
      def show_help(ctx, argv: [], **)
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
            command_help_line(spec)
          else
            "No help for #{topic}. Try :help or :help commands"
          end
        end
        ctx.editor.show_help_buffer!(title: "[Help] #{topic}", lines: help_text_to_lines(topic, text))
      end

      def define_command(ctx, argv:, bang:, **)
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

      def eval_ruby(ctx, argv:, **)
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

      def run_command(ctx, argv:, **)
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

      def shell_command(ctx, command:, **)
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

      def list_commands(ctx, **)
        rows = RuVim::ExCommandRegistry.instance.all.map do |spec|
          alias_text = spec.aliases.empty? ? "" : " (#{spec.aliases.join(', ')})"
          source = spec.source == :user ? " [user]" : ""
          name = "#{spec.name}#{alias_text}#{source}"
          desc = spec.desc
          keys = command_binding_labels(ctx.editor, spec)
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

      def list_bindings(ctx, argv: [], **)
        keymaps = ctx.editor.keymap_manager
        raise RuVim::CommandError, "Keymap manager is unavailable" unless keymaps

        mode_filter, sort = parse_bindings_args(argv)
        entries = keymaps.binding_entries_for_context(ctx.editor, mode: mode_filter)
        lines = bindings_buffer_lines(ctx.editor, entries, mode_filter:, sort:)
        ctx.editor.show_help_buffer!(title: "[Bindings]", lines:)
      end

      def set_option(ctx, argv:, **)
        set_option_common(ctx, argv, scope: :auto)
      end

      def set_option_local(ctx, argv:, **)
        set_option_common(ctx, argv, scope: :local)
      end

      def set_option_global(ctx, argv:, **)
        set_option_common(ctx, argv, scope: :global)
      end

      def execute_normal(ctx, argv:, kwargs: {}, **)
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

      def set_option_common(ctx, argv, scope:)
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

      def command_help_line(spec)
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

      def command_binding_labels(editor, ex_spec)
        keymaps = editor.keymap_manager
        return [] unless keymaps

        command_ids = command_ids_for_callable(ex_spec.call)
        return [] if command_ids.empty?

        entries = keymaps.binding_entries_for_context(editor).select do |entry|
          entry.layer == :app && command_ids.include?(entry.id.to_s)
        end
        entries.sort_by do |entry|
          [binding_mode_order_index(entry.mode), entry.scope == :global ? 1 : 0, format_binding_tokens(entry.tokens)]
        end.map do |entry|
          format_command_binding_label(entry)
        end.uniq
      end

      def command_ids_for_callable(callable)
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

      def format_command_binding_label(entry)
        lhs = format_binding_tokens(entry.tokens)
        if entry.scope == :global
          "global:#{lhs}"
        elsif entry.mode && entry.mode != :normal
          "#{entry.mode}:#{lhs}"
        else
          lhs
        end
      end
    end
  end
end
