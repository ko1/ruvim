module RuVim
  module DisplayWidth
    module_function

    def cell_width(ch, col: 0, tabstop: 2)
      return 1 if ch.nil? || ch.empty?

      if ch == "\t"
        width = tabstop - (col % tabstop)
        return width.zero? ? tabstop : width
      end

      code = ch.ord
      return 1 if code <= 0xA0 && !code.zero?
      return cached_codepoint_width(code) if codepoint_cacheable?(code)

      uncached_codepoint_width(code)
    end

    def codepoint_cacheable?(code)
      !code.nil? && !code.zero?
    end

    def cached_codepoint_width(code)
      aw = ambiguous_width
      @codepoint_width_cache ||= {}
      key = [code, aw]
      return @codepoint_width_cache[key] if @codepoint_width_cache.key?(key)

      @codepoint_width_cache[key] = uncached_codepoint_width(code)
    end

    def uncached_codepoint_width(code)
      return 0 if code.zero?
      return 0 if combining_mark?(code)
      return 0 if zero_width_codepoint?(code)
      return ambiguous_width if ambiguous_codepoint?(code)
      return 2 if emoji_codepoint?(code)
      return 2 if wide_codepoint?(code)

      1
    end

    def display_width(str, tabstop: 2, start_col: 0)
      col = start_col
      str.to_s.each_char { |ch| col += cell_width(ch, col:, tabstop:) }
      col - start_col
    end

    def expand_tabs(str, tabstop: 2, start_col: 0)
      col = start_col
      out = +""
      str.to_s.each_char do |ch|
        if ch == "\t"
          n = cell_width(ch, col:, tabstop:)
          out << (" " * n)
          col += n
        else
          out << ch
          col += cell_width(ch, col:, tabstop:)
        end
      end
      out
    end

    def combining_mark?(code)
      (0x0300..0x036F).cover?(code) ||
        (0x1AB0..0x1AFF).cover?(code) ||
        (0x1DC0..0x1DFF).cover?(code) ||
        (0x20D0..0x20FF).cover?(code) ||
        (0xFE20..0xFE2F).cover?(code)
    end

    def zero_width_codepoint?(code)
      (0x200D..0x200D).cover?(code) || # ZWJ
        (0xFE00..0xFE0F).cover?(code) || # variation selectors
        (0xE0100..0xE01EF).cover?(code)  # variation selectors supplement
    end

    def wide_codepoint?(code)
      (0x1100..0x115F).cover?(code) ||
        (0x2329..0x232A).cover?(code) ||
        (0x2E80..0xA4CF).cover?(code) ||
        (0xAC00..0xD7A3).cover?(code) ||
        (0xF900..0xFAFF).cover?(code) ||
        (0xFE10..0xFE19).cover?(code) ||
        (0xFE30..0xFE6F).cover?(code) ||
        (0xFF00..0xFF60).cover?(code) ||
        (0xFFE0..0xFFE6).cover?(code)
    end

    def emoji_codepoint?(code)
      (0x1F300..0x1FAFF).cover?(code) ||
        (0x2600..0x27BF).cover?(code)
    end

    def ambiguous_codepoint?(code)
      (0x00A1..0x00A1).cover?(code) ||
        (0x00A4..0x00A4).cover?(code) ||
        (0x00A7..0x00A8).cover?(code) ||
        (0x00AA..0x00AA).cover?(code) ||
        (0x00AD..0x00AE).cover?(code) ||
        (0x00B0..0x00B4).cover?(code) ||
        (0x00B6..0x00BA).cover?(code) ||
        (0x00BC..0x00BF).cover?(code) ||
        (0x0391..0x03A9).cover?(code) ||
        (0x03B1..0x03C9).cover?(code) ||
        (0x2010..0x2010).cover?(code) ||
        (0x2013..0x2016).cover?(code) ||
        (0x2018..0x2019).cover?(code) ||
        (0x201C..0x201D).cover?(code) ||
        (0x2020..0x2022).cover?(code) ||
        (0x2024..0x2027).cover?(code) ||
        (0x2030..0x2030).cover?(code) ||
        (0x2032..0x2033).cover?(code) ||
        (0x2035..0x2035).cover?(code) ||
        (0x203B..0x203B).cover?(code) ||
        (0x203E..0x203E).cover?(code) ||
        (0x2460..0x24E9).cover?(code) ||
        (0x2500..0x257F).cover?(code)
    end

    def ambiguous_width
      env = ::ENV["RUVIM_AMBIGUOUS_WIDTH"]
      if !defined?(@ambiguous_width_cached) || @ambiguous_width_env != env
        @ambiguous_width_env = env
        @ambiguous_width_cached = (env == "2" ? 2 : 1)
        @codepoint_width_cache = {}
      end

      @ambiguous_width_cached
    end
  end
end
