# frozen_string_literal: true

module RuVim
  module Lang
    class Rust < Base
      KEYWORDS = %w[
      as async await break const continue crate dyn else enum extern
      false fn for if impl in let loop match mod move mut pub ref
      return self Self static struct super trait true type unsafe use
      where while
      macro_rules
      ].freeze

      TYPES = %w[
      bool char str
      i8 i16 i32 i64 i128 isize
      u8 u16 u32 u64 u128 usize
      f32 f64
      String Vec Box Rc Arc Option Result HashMap HashSet
      Vec! vec!
      ].freeze

      ALL_KEYWORDS = (KEYWORDS + TYPES).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.map { |k| Regexp.escape(k) }.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_RAW_RE = /r#*"[^"]*"#*/
      CHAR_RE = /'(?:\\.|[^'\\])'/
      LIFETIME_RE = /'[a-z_]\w*/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?(?:_?[iu](?:8|16|32|64|128|size)|_?f(?:32|64))?)\b/
      LINE_COMMENT_RE = %r{//.*}
      BLOCK_COMMENT_RE = %r{/\*.*?\*/}
      ATTRIBUTE_RE = /#!?\[[\w:(,)\s"]*\]/
      MACRO_RE = /\b\w+!/
      CONSTANT_RE = /\b[A-Z][A-Z0-9_]{1,}\b/

      INDENT_OPEN_RE = /[{(\[]\s*(?:\/\/.*)?$/
      INDENT_CLOSE_RE = /\A\s*[}\])]/

      DEDENT_TRIGGERS = {
      "}" => /\A(\s*)\}/,
      "]" => /\A(\s*)\]/,
      ")" => /\A(\s*)\)/
      }.freeze

      def buffer_defaults

        { "runprg" => "rustc -o /tmp/a.out % && /tmp/a.out" }

      end

      def calculate_indent(lines, target_row, shiftwidth)
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

      def indent_trigger?(line)
      line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def dedent_trigger(char)
      DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
      cols = {}
      apply_regex(cols, text, CHAR_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_RAW_RE, STRING_COLOR)
      apply_regex(cols, text, LIFETIME_RE, "\e[35m")
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, MACRO_RE, "\e[35m")
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, CONSTANT_RE, CONSTANT_COLOR)
      apply_regex(cols, text, ATTRIBUTE_RE, "\e[35m")
      apply_regex(cols, text, BLOCK_COMMENT_RE, COMMENT_COLOR, override: true)
      apply_regex(cols, text, LINE_COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
