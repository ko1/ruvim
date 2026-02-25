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
      editor.echo("Error: #{e.message}")
    end

    def dispatch_ex(editor, line)
      if (sub = parse_global_substitute(line))
        invocation = CommandInvocation.new(id: "__substitute__", kwargs: sub)
        ctx = Context.new(editor:, invocation:)
        @command_host.ex_substitute(ctx, **sub)
        editor.enter_normal_mode
        return
      end

      parsed = parse_ex(line)
      return if parsed.nil?

      spec = @ex_registry.fetch(parsed.name)
      validate_ex_args!(spec, parsed.argv, parsed.bang)
      invocation = CommandInvocation.new(id: spec.name, argv: parsed.argv, bang: parsed.bang)
      ctx = Context.new(editor:, invocation:)
      @command_host.call(spec.call, ctx, argv: parsed.argv, bang: parsed.bang, count: 1, kwargs: {})
    rescue StandardError => e
      editor.echo("Error: #{e.message}")
    ensure
      editor.enter_normal_mode
    end

    def parse_ex(line)
      raw = line.to_s.strip
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

    def parse_global_substitute(line)
      raw = line.to_s.strip
      return nil unless raw.start_with?("%s")
      return nil if raw.length < 4

      delim = raw[2]
      return nil if delim.nil? || delim =~ /\s/
      i = 3
      pat, i = parse_delimited_segment(raw, i, delim)
      return nil unless pat
      rep, i = parse_delimited_segment(raw, i, delim)
      return nil unless rep
      flags = raw[i..].to_s
      {
        pattern: pat,
        replacement: rep,
        global: flags.include?("g")
      }
    rescue StandardError
      nil
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
