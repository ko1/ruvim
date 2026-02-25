module RuVim
  class KeymapManager
    Match = Struct.new(:status, :invocation, keyword_init: true)

    def initialize
      @mode_maps = Hash.new { |h, k| h[k] = {} }
      @global_map = {}
      @buffer_maps = Hash.new { |h, k| h[k] = {} }
      @filetype_maps = Hash.new { |h, k| h[k] = Hash.new { |hh, m| hh[m] = {} } }
    end

    def bind(mode, seq, id, argv: [], kwargs: {}, bang: false)
      tokens = normalize_seq(seq)
      @mode_maps[mode.to_sym][tokens] = build_invocation(id, argv:, kwargs:, bang:, tokens:)
    end

    def bind_global(seq, id, argv: [], kwargs: {}, bang: false)
      tokens = normalize_seq(seq)
      @global_map[tokens] = build_invocation(id, argv:, kwargs:, bang:, tokens:)
    end

    def bind_buffer(buffer_id, seq, id, argv: [], kwargs: {}, bang: false)
      tokens = normalize_seq(seq)
      @buffer_maps[buffer_id][tokens] = build_invocation(id, argv:, kwargs:, bang:, tokens:)
    end

    def bind_filetype(filetype, seq, id, mode: :normal, argv: [], kwargs: {}, bang: false)
      tokens = normalize_seq(seq)
      @filetype_maps[filetype.to_s][mode.to_sym][tokens] = build_invocation(id, argv:, kwargs:, bang:, tokens:)
    end

    def resolve(mode, pending_tokens)
      resolve_layers([@mode_maps[mode.to_sym]], pending_tokens)
    end

    def resolve_with_context(mode, pending_tokens, editor:)
      buffer = editor.current_buffer
      filetype = detect_filetype(buffer)
      layers = []
      layers << @filetype_maps[filetype][mode.to_sym] if filetype && @filetype_maps.key?(filetype)
      layers << @buffer_maps[buffer.id] if @buffer_maps.key?(buffer.id)
      layers << @mode_maps[mode.to_sym]
      layers << @global_map
      resolve_layers(layers, pending_tokens)
    end

    private

    def build_invocation(id, argv:, kwargs:, bang:, tokens:)
      CommandInvocation.new(
        id: id,
        argv: argv,
        kwargs: kwargs,
        bang: bang,
        raw_keys: tokens
      )
    end

    def resolve_layers(layers, pending_tokens)
      layers = layers.compact
      return Match.new(status: :none) if layers.empty?

      layers.each do |layer|
        next if layer.empty?

        if (exact = layer[pending_tokens])
          longer = layer.keys.any? { |k| k.length > pending_tokens.length && k[0, pending_tokens.length] == pending_tokens }
          return Match.new(status: (longer ? :ambiguous : :match), invocation: exact)
        end
      end

      has_prefix = layers.any? { |layer| layer.keys.any? { |k| k[0, pending_tokens.length] == pending_tokens } }
      Match.new(status: has_prefix ? :pending : :none)
    end

    def detect_filetype(buffer)
      ft = buffer.options["filetype"] if buffer.respond_to?(:options)
      return ft if ft && !ft.empty?

      path = buffer.path.to_s
      ext = File.extname(path)
      return nil if ext.empty?

      ext.delete_prefix(".")
    end

    def normalize_seq(seq)
      case seq
      when Array
        seq.map(&:to_s).freeze
      else
        seq.to_s.each_char.map(&:to_s).freeze
      end
    end
  end
end
