# frozen_string_literal: true

module RuVim
  module Lang
    class Json < Base
      INDENT_OPEN_RE = /[\[{]\s*$/
      INDENT_CLOSE_RE = /\A\s*[\]}]/

      DEDENT_TRIGGERS = {
      "}" => /\A(\s*)\}/,
      "]" => /\A(\s*)\]/
      }.freeze

      def calculate_indent(lines, target_row, shiftwidth)
      depth = 0
      (0...target_row).each do |row|
        line = lines[row].to_s
        line.each_char do |ch|
          case ch
          when "{", "[" then depth += 1
          when "}", "]" then depth -= 1
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
      apply_regex(cols, text, /"(?:\\.|[^"\\])*"\s*(?=:)/, "\e[36m")
      apply_regex(cols, text, /"(?:\\.|[^"\\])*"/, "\e[32m")
      apply_regex(cols, text, /\b(?:true|false|null)\b/, "\e[35m")
      apply_regex(cols, text, /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, "\e[33m")
      cols
      end
    end
  end
end
