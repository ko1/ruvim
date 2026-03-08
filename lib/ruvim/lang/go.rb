# frozen_string_literal: true

module RuVim
  module Lang
    module Go
      KEYWORDS = %w[
        break case chan const continue default defer else fallthrough
        for func go goto if import interface map package range return
        select struct switch type var
        true false nil iota
      ].freeze

      TYPES = %w[
        bool byte complex64 complex128 error float32 float64
        int int8 int16 int32 int64 rune string
        uint uint8 uint16 uint32 uint64 uintptr any comparable
      ].freeze

      ALL_KEYWORDS = (KEYWORDS + TYPES).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_RAW_RE = /`[^`]*`/
      CHAR_RE = /'(?:\\.|[^'\\])'/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?i?)\b/
      LINE_COMMENT_RE = %r{//.*}
      BLOCK_COMMENT_RE = %r{/\*.*?\*/}
      CONSTANT_RE = /\b[A-Z][A-Z0-9_]{1,}\b/

      INDENT_OPEN_RE = /\{\s*(?:\/\/.*)?$/
      INDENT_CLOSE_RE = /\A\s*\}/

      DEDENT_TRIGGERS = {
        "}" => /\A(\s*)\}/
      }.freeze

      module_function

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row].to_s
          line.each_char do |ch|
            case ch
            when "{" then depth += 1
            when "}" then depth -= 1
            end
          end
        end

        target_line = lines[target_row].to_s.lstrip
        depth -= 1 if target_line.match?(INDENT_CLOSE_RE)
        depth = 0 if depth < 0
        depth * shiftwidth
      end

      def indent_trigger?(line)
        line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def dedent_trigger(char)
        DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, CHAR_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_RAW_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, CONSTANT_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("go", mod: Go,
      extensions: %w[.go],
      runprg: "go run %")
  end
end
