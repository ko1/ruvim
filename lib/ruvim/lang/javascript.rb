# frozen_string_literal: true

module RuVim
  module Lang
    class Javascript < Base
      KEYWORDS = %w[
      async await break case catch class const continue debugger default
      delete do else export extends finally for from function if import
      in instanceof let new of return static super switch this throw
      try typeof var void while with yield
      true false null undefined NaN Infinity
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      TEMPLATE_RE = /`(?:\\.|[^`\\])*`/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?n?)\b/
      LINE_COMMENT_RE = %r{//.*}
      BLOCK_COMMENT_RE = %r{/\*.*?\*/}
      CONSTANT_RE = /\b[A-Z][A-Z0-9_]{1,}\b/
      REGEX_RE = %r{/(?:\\.|[^/\\])+/[gimsuvy]*}

      INDENT_OPEN_RE = /[{(\[]\s*(?:\/\/.*)?$/
      INDENT_CLOSE_RE = /\A\s*[}\])]/

      DEDENT_TRIGGERS = {
      "}" => /\A(\s*)\}/,
      "]" => /\A(\s*)\]/,
      ")" => /\A(\s*)\)/
      }.freeze

      BUFFER_DEFAULTS = { "runprg" => "node %" }.freeze

      def self.calculate_indent(lines, target_row, shiftwidth)
      depth = 0
      (0...target_row).each do |row|
        line = lines[row].to_s
        line.each_char do |ch|
          case ch
          when "{", "[", "(" then depth += 1
          when "}", "]", ")" then depth -= 1
          end
        end
      end

      target_line = lines[target_row].to_s.lstrip
      depth -= 1 if target_line.match?(INDENT_CLOSE_RE)
      depth = 0 if depth < 0
      depth * shiftwidth
      end

      def self.indent_trigger?(line)
      line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def self.dedent_trigger(char)
      DEDENT_TRIGGERS[char]
      end

      def self.color_columns(text)
      cols = {}
      apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, TEMPLATE_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, CONSTANT_RE, CONSTANT_COLOR)
      apply_regex(cols, text, BLOCK_COMMENT_RE, COMMENT_COLOR, override: true)
      apply_regex(cols, text, LINE_COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
