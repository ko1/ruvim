# frozen_string_literal: true

module RuVim
  module TextMetrics
    module_function

    class Cell
      attr_reader :glyph, :source_col, :display_width

      def initialize(glyph, source_col, display_width)
        @glyph = glyph
        @source_col = source_col
        @display_width = display_width
      end
    end

    # Cursor positions in RuVim are currently "character index" (Ruby String#[] index on UTF-8),
    # not byte offsets. Grapheme-aware movement is layered on top of that.
    def previous_grapheme_char_index(line, char_index)
      idx = [char_index, 0].max
      return 0 if idx <= 0

      left = line[0...idx].to_s
      clusters = left.scan(/\X/)
      return 0 if clusters.empty?

      idx - clusters.last.length
    end

    def next_grapheme_char_index(line, char_index)
      s = line.to_s
      idx = [[char_index, 0].max, s.length].min
      return s.length if idx >= s.length

      rest = s[idx..].to_s
      m = /\A\X/.match(rest)
      return idx + 1 unless m

      idx + m[0].length
    end

    def screen_col_for_char_index(line, char_index, tabstop: 2)
      idx = [char_index, 0].max
      prefix = line[0...idx].to_s
      RuVim::DisplayWidth.display_width(prefix, tabstop:)
    end

    # Returns a character index whose screen column is <= target_screen_col,
    # aligned to a grapheme-cluster boundary.
    def char_index_for_screen_col(line, target_screen_col, tabstop: 2, align: :floor)
      s = line.to_s
      target = [target_screen_col, 0].max
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
      max_width = [width, 0].max
      cells = []
      display_col = 0
      source_col = source_col_start

      text.to_s.each_char do |ch|
        code = ch.ord
        # Fast path: printable ASCII (0x20..0x7E) — width 1, no special handling
        if code >= 0x20 && code <= 0x7E
          break if display_col >= max_width
          cells << Cell.new(ch, source_col, 1)
          display_col += 1
          source_col += 1
          next
        end

        if ch == "\t"
          w = tabstop - (display_col % tabstop)
          w = tabstop if w.zero?
          break if display_col + w > max_width

          w.times do
            cells << Cell.new(" ", source_col, 1)
          end
          display_col += w
          source_col += 1
          next
        end

        # Control chars (0x00..0x1F, 0x7F, 0x80..0x9F)
        if code < 0x20 || code == 0x7F || (code >= 0x80 && code <= 0x9F)
          break if display_col >= max_width
          cells << Cell.new("?", source_col, 1)
          display_col += 1
          source_col += 1
          next
        end

        w = RuVim::DisplayWidth.cell_width(ch, col: display_col, tabstop:)
        break if display_col + w > max_width

        cells << Cell.new(ch, source_col, w)
        display_col += w
        source_col += 1
      end

      [cells, display_col]
    end

    def pad_plain_to_screen_width(text, width, tabstop: 2)
      cells, used = clip_cells_for_width(text, width, tabstop:)
      out = cells.map(&:glyph).join
      out << (" " * [width - used, 0].max)
      out
    end

    UNSAFE_CONTROL_CHAR_RE = /[\u0000-\u0008\u000a-\u001f\u007f\u0080-\u009f]/

    def terminal_safe_text(text)
      text.to_s.gsub(UNSAFE_CONTROL_CHAR_RE, "?")
    end

  end
end
