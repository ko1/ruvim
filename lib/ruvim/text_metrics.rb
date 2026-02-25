module RuVim
  module TextMetrics
    module_function

    Cell = Struct.new(:glyph, :source_col, :display_width, keyword_init: true)

    # Cursor positions in RuVim are currently "character index" (Ruby String#[] index on UTF-8),
    # not byte offsets. Grapheme-aware movement is layered on top of that.
    def previous_grapheme_char_index(line, char_index)
      idx = [char_index.to_i, 0].max
      return 0 if idx <= 0

      left = line.to_s[0...idx].to_s
      clusters = left.scan(/\X/)
      return 0 if clusters.empty?

      idx - clusters.last.length
    end

    def next_grapheme_char_index(line, char_index)
      s = line.to_s
      idx = [[char_index.to_i, 0].max, s.length].min
      return s.length if idx >= s.length

      rest = s[idx..].to_s
      m = /\A\X/.match(rest)
      return idx + 1 unless m

      idx + m[0].length
    end

    def screen_col_for_char_index(line, char_index, tabstop: 2)
      idx = [char_index.to_i, 0].max
      prefix = line.to_s[0...idx].to_s
      RuVim::DisplayWidth.display_width(prefix, tabstop:)
    end

    # Returns a character index whose screen column is <= target_screen_col,
    # aligned to a grapheme-cluster boundary.
    def char_index_for_screen_col(line, target_screen_col, tabstop: 2, align: :floor)
      s = line.to_s
      target = [target_screen_col.to_i, 0].max
      screen_col = 0
      char_index = 0

      s.scan(/\X/).each do |cluster|
        width = RuVim::DisplayWidth.display_width(cluster, tabstop:, start_col: screen_col)
        if screen_col + width > target
          return align == :ceil ? (char_index + cluster.length) : char_index
        end

        screen_col += width
        char_index += cluster.length
      end

      char_index
    end

    def clip_cells_for_width(text, width, source_col_start: 0, tabstop: 2)
      max_width = [width.to_i, 0].max
      cells = []
      display_col = 0
      source_col = source_col_start.to_i

      text.to_s.each_char do |ch|
        if ch == "\t"
          w = RuVim::DisplayWidth.cell_width(ch, col: display_col, tabstop:)
          break if display_col + w > max_width

          w.times do
            cells << Cell.new(glyph: " ", source_col:, display_width: 1)
          end
          display_col += w
          source_col += 1
          next
        end

        w = RuVim::DisplayWidth.cell_width(ch, col: display_col, tabstop:)
        break if display_col + w > max_width

        cells << Cell.new(glyph: ch, source_col:, display_width: w)
        display_col += w
        source_col += 1
      end

      [cells, display_col]
    end

    def pad_plain_to_screen_width(text, width, tabstop: 2)
      cells, used = clip_cells_for_width(text, width, tabstop:)
      out = cells.map(&:glyph).join
      out << (" " * [width.to_i - used, 0].max)
      out
    end
  end
end
