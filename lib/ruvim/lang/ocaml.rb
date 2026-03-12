# frozen_string_literal: true

module RuVim
  module Lang
    class Ocaml < Base
      KEYWORDS = %w[
        and as assert begin class constraint do done downto else end
        exception external false for fun function functor if in include
        inherit initializer lazy let match method mod module mutable
        new nonrec object of open or private rec sig struct then to
        true try type val virtual when while with
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      CHAR_RE = /'(?:\\.|[^'\\])'/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b/
      BLOCK_COMMENT_RE = /\(\*.*?\*\)/
      MODULE_RE = /\b[A-Z]\w*(?:\.[A-Z]\w*)*/
      VARIANT_RE = /\b[A-Z]\w*\b/
      TYPE_VAR_RE = /'\w+/
      OPERATOR_RE = /->|::|;;|<-|\|>/

      INDENT_OPEN_RE = /\b(?:struct|sig|begin|do|then|else)\s*$/
      INDENT_CLOSE_RE = /\A\s*(?:end|done)\b/

      DEDENT_TRIGGERS = {
        "d" => /\A(\s*)end\z/,
        "e" => /\A(\s*)(?:done|else)\z/
      }.freeze

      def buffer_defaults

        { "runprg" => "ocaml %" }

      end

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row].to_s.strip
          next if line.empty?

          depth += 1 if line.match?(/\b(?:struct|sig|begin|do)\b/)
          depth -= 1 if line.match?(/\A(?:end|done)\b/)
        end

        target_line = lines[target_row].to_s.strip
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
        apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
        apply_regex(cols, text, TYPE_VAR_RE, VARIABLE_COLOR)
        apply_regex(cols, text, MODULE_RE, CONSTANT_COLOR)
        apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
        apply_regex(cols, text, OPERATOR_RE, KEYWORD_COLOR)
        apply_regex(cols, text, BLOCK_COMMENT_RE, COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
