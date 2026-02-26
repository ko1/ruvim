module RuVim
  class KeymapManager
    Match = Struct.new(:status, :invocation, keyword_init: true)
    BindingEntry = Struct.new(:layer, :mode, :tokens, :id, :argv, :kwargs, :bang, :scope, keyword_init: true)

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

    def binding_entries_for_context(editor, mode: nil)
      buffer = editor.current_buffer
      filetype = detect_filetype(buffer)
      modes = normalized_mode_filter(mode)
      entries = []

      entries.concat(snapshot_plain_layer(@buffer_maps[buffer.id], layer: :buffer))

      if filetype && @filetype_maps.key?(filetype)
        ft_modes = @filetype_maps[filetype]
        entries.concat(snapshot_mode_layers(ft_modes, layer: :filetype, modes:))
      end

      entries.concat(snapshot_mode_layers(@mode_maps, layer: :app, modes:, scope: :mode))
      entries.concat(snapshot_plain_layer(@global_map, layer: :app, scope: :global))

      entries
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

    def snapshot_plain_layer(layer_map, layer:, scope: nil)
      return [] unless layer_map && !layer_map.empty?

      layer_map.map do |tokens, inv|
        snapshot_entry(tokens, inv, layer:, scope:)
      end.sort_by { |e| [token_sort_key(e.tokens), e.id.to_s] }
    end

    def snapshot_mode_layers(mode_maps, layer:, modes: nil, scope: nil)
      return [] unless mode_maps

      selected = mode_maps.keys.map(&:to_sym)
      selected &= modes if modes
      selected.sort_by! { |m| mode_sort_key(m) }

      selected.flat_map do |m|
        next [] if mode_maps[m].nil? || mode_maps[m].empty?

        mode_maps[m].map do |tokens, inv|
          snapshot_entry(tokens, inv, layer:, mode: m, scope:)
        end.sort_by { |e| [token_sort_key(e.tokens), e.id.to_s] }
      end
    end

    def snapshot_entry(tokens, inv, layer:, mode: nil, scope: nil)
      BindingEntry.new(
        layer: layer,
        mode: mode,
        tokens: Array(tokens).map(&:dup),
        id: inv.id.to_s,
        argv: Array(inv.argv).map { |v| v.is_a?(String) ? v.dup : v },
        kwargs: (inv.kwargs || {}).dup,
        bang: !!inv.bang,
        scope: scope
      )
    end

    def normalized_mode_filter(mode)
      return nil if mode.nil?

      ary = Array(mode).compact.map { |m| m.to_sym }
      ary.empty? ? nil : ary
    end

    def token_sort_key(tokens)
      Array(tokens).join("\0")
    end

    def mode_sort_key(mode)
      order = {
        normal: 0,
        insert: 1,
        visual_char: 2,
        visual_line: 3,
        visual_block: 4,
        operator_pending: 5,
        command_line: 6
      }
      [order.fetch(mode.to_sym, 99), mode.to_s]
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
