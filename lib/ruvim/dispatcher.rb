# frozen_string_literal: true

require "shellwords"

module RuVim
  class Dispatcher
    ExCall = Struct.new(:name, :argv, :bang, keyword_init: true)

    def initialize(command_registry: CommandRegistry.instance, ex_registry: ExCommandRegistry.instance, command_host: GlobalCommands.instance)
      @command_registry = command_registry
      @ex_registry = ex_registry
      @command_host = command_host
    end

    def dispatch(editor, invocation)
      spec = @command_registry.fetch(invocation.id)
      ctx = Context.new(editor:, invocation:)
      @command_host.call(spec.call, ctx, argv: invocation.argv, kwargs: invocation.kwargs, bang: invocation.bang, count: invocation.count)
    rescue StandardError => e
      editor.echo_error("Error: #{e.message}")
    end

    def dispatch_ex(editor, line)
      raw = line.strip
      if raw.start_with?("!")
        command = raw[1..].strip
        invocation = CommandInvocation.new(id: "__shell__", argv: [command])
        ctx = Context.new(editor:, invocation:)
        @command_host.ex_shell(ctx, command:)
        editor.enter_normal_mode
        return
      end

      # Parse range prefix
      range_result = parse_range(raw, editor)
      rest = range_result ? range_result[:rest] : raw

      # Try global/vglobal on rest
      if (glob = parse_global(rest))
        kwargs = glob.merge(
          range_start: range_result&.dig(:range_start),
          range_end: range_result&.dig(:range_end)
        )
        invocation = CommandInvocation.new(id: "__global__", kwargs:)
        ctx = Context.new(editor:, invocation:)
        @command_host.ex_global(ctx, **kwargs)
        editor.enter_normal_mode
        return
      end

      # Try substitute on rest
      if (sub = parse_substitute(rest))
        kwargs = sub.merge(
          range_start: range_result&.dig(:range_start),
          range_end: range_result&.dig(:range_end)
        )
        invocation = CommandInvocation.new(id: "__substitute__", kwargs:)
        ctx = Context.new(editor:, invocation:)
        @command_host.ex_substitute(ctx, **kwargs)
        editor.enter_normal_mode
        return
      end

      parsed = parse_ex(rest)
      return if parsed.nil?

      spec = @ex_registry.resolve(parsed.name)
      unless spec
        # Try splitting single-char command from trailing content (e.g. "m$" -> "m" + "$")
        head = parsed.name
        bang = parsed.bang
        bare = bang ? head : head
        if bare.length > 1
          first = bare[0]
          spec = @ex_registry.resolve(first)
          if spec
            parsed = ExCall.new(name: first, argv: [bare[1..]] + parsed.argv, bang: bang)
          end
        end
        spec ||= @ex_registry.fetch(parsed.name) # raises if truly unknown
      end
      argv = parsed.argv
      if spec.raw_args
        # Re-extract raw text after command name (preserving shell quoting)
        cmd_name = parsed.name
        trimmed = rest.strip
        if trimmed.start_with?(cmd_name)
          raw_rest = trimmed[cmd_name.length..].to_s.lstrip
        else
          raw_rest = trimmed.sub(/\A\S+\s*/, "")
        end
        argv = raw_rest.empty? ? [] : [raw_rest]
      end
      validate_ex_args!(spec, argv, parsed.bang)
      invocation = CommandInvocation.new(id: spec.name, argv: argv, bang: parsed.bang)
      ctx = Context.new(editor:, invocation:)
      range_kwargs = {}
      if range_result
        range_kwargs[:range_start] = range_result[:range_start]
        range_kwargs[:range_end] = range_result[:range_end]
      end
      @command_host.call(spec.call, ctx, argv: argv, bang: parsed.bang, count: 1, kwargs: range_kwargs)
    rescue StandardError => e
      editor.echo_error("Error: #{e.message}")
    ensure
      editor.leave_command_line if editor.mode == :command_line
    end

    def parse_ex(line)
      raw = line.strip
      return nil if raw.empty?

      tokens = Shellwords.shellsplit(raw)
      return nil if tokens.empty?

      head = tokens.shift
      bang = head.end_with?("!")
      name = bang ? head[0...-1] : head
      ExCall.new(name:, argv: tokens, bang:)
    rescue ArgumentError => e
      raise RuVim::CommandError, "Parse error: #{e.message}"
    end

    # Parse a substitute command: s/pat/repl/flags
    # Returns {pattern:, replacement:, flags_str:} or nil
    def parse_substitute(line)
      raw = line.strip
      return nil unless raw.match?(/\As[^a-zA-Z]/)
      return nil if raw.length < 2

      delim = raw[1]
      return nil if delim.nil? || delim =~ /\s/
      i = 2
      pat, i = parse_delimited_segment(raw, i, delim)
      return nil unless pat
      rep, i = parse_delimited_segment(raw, i, delim)
      return nil unless rep
      flags_str = raw[i..].to_s
      {
        pattern: pat,
        replacement: rep,
        flags_str: flags_str
      }
    rescue StandardError
      nil
    end

    # Parse a global command: g/pattern/command or v/pattern/command
    # Also handles g!/pattern/command (same as v)
    # Returns {pattern:, command:, invert:} or nil
    def parse_global(line)
      raw = line.strip
      invert = false

      if raw.match?(/\Avglobal[^a-zA-Z]/) || raw.match?(/\Avglobal!\z/)
        invert = true
        pos = 7
      elsif raw.match?(/\Av[^a-zA-Z]/)
        invert = true
        pos = 1
      elsif raw.match?(/\Aglobal![^a-zA-Z]/) || raw.match?(/\Aglobal!\z/)
        invert = true
        pos = 7
      elsif raw.match?(/\Aglobal[^a-zA-Z]/)
        pos = 6
      elsif raw.match?(/\Ag![^a-zA-Z]/)
        invert = true
        pos = 2
      elsif raw.match?(/\Ag[^a-zA-Z]/)
        pos = 1
      else
        return nil
      end

      delim = raw[pos]
      return nil if delim.nil? || delim =~ /\s/

      pat, end_pos = parse_delimited_segment(raw, pos + 1, delim)
      return nil unless pat

      cmd = raw[end_pos..].to_s.strip
      cmd = "p" if cmd.empty?

      { pattern: pat, command: cmd, invert: invert }
    rescue StandardError
      nil
    end

    # Parse an address at position pos in str.
    # Returns [resolved_line_number, new_pos] or nil.
    def parse_address(str, pos, editor)
      return nil if pos >= str.length

      ch = str[pos]
      base = nil
      new_pos = pos

      case ch
      when /\d/
        # Numeric address
        m = str[pos..].match(/\A(\d+)/)
        return nil unless m
        base = m[1].to_i - 1 # convert 1-based to 0-based
        new_pos = pos + m[0].length
      when "."
        base = editor.current_window.cursor_y
        new_pos = pos + 1
      when "$"
        base = editor.current_buffer.line_count - 1
        new_pos = pos + 1
      when "'"
        # Mark address
        mark_ch = str[pos + 1]
        return nil unless mark_ch
        if mark_ch == "<" || mark_ch == ">"
          sel = editor.visual_selection
          if sel
            base = mark_ch == "<" ? sel[:start_row] : sel[:end_row]
          else
            return nil
          end
        else
          loc = editor.mark_location(mark_ch)
          return nil unless loc
          base = loc[:row]
        end
        new_pos = pos + 2
      when "+", "-"
        # Relative offset with implicit current line
        base = editor.current_window.cursor_y
        # Don't advance new_pos — the offset parsing below will handle +/-
      else
        return nil
      end

      # Parse trailing +N / -N offsets
      while new_pos < str.length
        offset_ch = str[new_pos]
        if offset_ch == "+"
          m = str[new_pos + 1..].to_s.match(/\A(\d+)/)
          if m
            base += m[1].to_i
            new_pos += 1 + m[0].length
          else
            base += 1
            new_pos += 1
          end
        elsif offset_ch == "-"
          m = str[new_pos + 1..].to_s.match(/\A(\d+)/)
          if m
            base -= m[1].to_i
            new_pos += 1 + m[0].length
          else
            base -= 1
            new_pos += 1
          end
        else
          break
        end
      end

      # Clamp to valid range
      max_line = editor.current_buffer.line_count - 1
      base = [[base, 0].max, max_line].min

      [base, new_pos]
    end

    # Parse a range from the beginning of raw.
    # Returns {range_start:, range_end:, rest:} or nil.
    def parse_range(raw, editor)
      str = raw
      return nil if str.empty?

      # % = whole file
      if str[0] == "%"
        max_line = editor.current_buffer.line_count - 1
        rest = str[1..].to_s
        return { range_start: 0, range_end: max_line, rest: rest }
      end

      # Try first address
      addr1 = parse_address(str, 0, editor)
      return nil unless addr1

      line1, pos = addr1

      if pos < str.length && str[pos] == ","
        # addr,addr range
        addr2 = parse_address(str, pos + 1, editor)
        if addr2
          line2, pos2 = addr2
          return { range_start: line1, range_end: line2, rest: str[pos2..].to_s }
        end
      end

      # Single address
      { range_start: line1, range_end: line1, rest: str[pos..].to_s }
    end

    private

    def parse_delimited_segment(str, idx, delim)
      out = +""
      i = idx
      while i < str.length
        ch = str[i]
        if ch == "\\"
          nxt = str[i + 1]
          return nil unless nxt
          out << "\\"
          out << nxt
          i += 2
          next
        end
        if ch == delim
          return [out, i + 1]
        end
        out << ch
        i += 1
      end
      nil
    end

    def validate_ex_args!(spec, argv, bang)
      case spec.nargs
      when 0
        raise RuVim::CommandError, "#{spec.name} takes no arguments" unless argv.empty?
      when 1
        raise RuVim::CommandError, "#{spec.name} requires one argument" unless argv.length == 1
      when :maybe_one
        raise RuVim::CommandError, "#{spec.name} takes at most one argument" unless argv.length <= 1
      end

      if bang && !spec.bang
        raise RuVim::CommandError, "#{spec.name} does not accept !"
      end
    end
  end
end
