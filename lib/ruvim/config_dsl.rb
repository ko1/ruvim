module RuVim
  class ConfigDSL < BasicObject
    def initialize(command_registry:, ex_registry:, keymaps:, command_host:, editor: nil, filetype: nil)
      @command_registry = command_registry
      @ex_registry = ex_registry
      @keymaps = keymaps
      @command_host = command_host
      @editor = editor
      @filetype = filetype&.to_s
      @inline_map_command_seq = 0
    end

    def nmap(seq, command_id = nil, desc: "user keymap", **opts, &block)
      command_id = inline_map_command_id(:normal, seq, desc:, &block) if block
      raise ::ArgumentError, "command_id or block required" if command_id.nil?

      if @filetype && !@filetype.empty?
        @keymaps.bind_filetype(@filetype, seq, command_id.to_s, mode: :normal, **opts)
      else
        @keymaps.bind(:normal, seq, command_id.to_s, **opts)
      end
    end

    def imap(seq, command_id = nil, desc: "user keymap", **opts, &block)
      command_id = inline_map_command_id(:insert, seq, desc:, &block) if block
      raise ::ArgumentError, "command_id or block required" if command_id.nil?

      if @filetype && !@filetype.empty?
        @keymaps.bind_filetype(@filetype, seq, command_id.to_s, mode: :insert, **opts)
      else
        @keymaps.bind(:insert, seq, command_id.to_s, **opts)
      end
    end

    def map_global(seq, command_id = nil, mode: :normal, desc: "user keymap", **opts, &block)
      command_id = inline_map_command_id(mode || :global, seq, desc:, &block) if block
      raise ::ArgumentError, "command_id or block required" if command_id.nil?

      if mode
        @keymaps.bind(mode.to_sym, seq, command_id.to_s, **opts)
      else
        @keymaps.bind_global(seq, command_id.to_s, **opts)
      end
    end

    def command(id, desc: "user command", &block)
      raise ::ArgumentError, "block required" unless block

      @command_registry.register(id.to_s, call: block, desc:, source: :user)
    end

    def ex_command(name, desc: "user ex", aliases: [], nargs: :any, bang: false, &block)
      raise ::ArgumentError, "block required" unless block

      @ex_registry.unregister(name.to_s) if @ex_registry.registered?(name.to_s)
      @ex_registry.register(name.to_s, call: block, desc:, aliases:, nargs:, bang:, source: :user)
    end

    # Convenience: define an Ex command that forwards to an existing internal command ID.
    def ex_command_call(name, command_id, desc: "user ex", aliases: [], nargs: :any, bang: false)
      ex_command(name, desc:, aliases:, nargs:, bang:) do |ctx, argv:, kwargs:, bang:, count:|
        spec = @command_registry.fetch(command_id.to_s)
        @command_host.call(spec.call, ctx, argv:, kwargs:, bang:, count:)
      end
    end

    def set(option_expr)
      apply_option_expr(option_expr, scope: :auto)
    end

    def setlocal(option_expr)
      apply_option_expr(option_expr, scope: :local)
    end

    def setglobal(option_expr)
      apply_option_expr(option_expr, scope: :global)
    end

    private

    def inline_map_command_id(mode, seq, desc:, &block)
      raise ::ArgumentError, "block required" unless block

      @inline_map_command_seq += 1
      id = "user.keymap.#{normalize_mode_name(mode)}.#{sanitize_seq_label(seq)}.#{@inline_map_command_seq}"
      command(id, desc:, &block)
      id
    end

    def normalize_mode_name(mode)
      (mode || :global).to_s
    end

    def sanitize_seq_label(seq)
      raw =
        case seq
        when ::Array
          seq.map(&:to_s).join("_")
        else
          seq.to_s
        end
      s = raw.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      s.empty? ? "anonymous" : s
    end

    def apply_option_expr(expr, scope:)
      raise ::ArgumentError, "editor context required for option DSL" unless @editor

      token = expr.to_s.strip
      raise ::ArgumentError, "empty option expression" if token.empty?

      if token.start_with?("no")
        name = token[2..]
        @editor.set_option(name, false, scope: resolve_scope(name, scope))
        return
      end

      if token.include?("=")
        name, raw = token.split("=", 2)
        @editor.set_option(name, raw, scope: resolve_scope(name, scope))
        return
      end

      @editor.set_option(token, true, scope: resolve_scope(token, scope))
    end

    def resolve_scope(name, scope)
      return :auto if scope == :auto
      return :global if scope == :global

      @editor.option_default_scope(name) == :buffer ? :buffer : :window
    end
  end
end
