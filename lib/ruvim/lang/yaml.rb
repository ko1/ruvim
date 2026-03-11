# frozen_string_literal: true

module RuVim
  module Lang
    class Yaml < Base
      KEYWORDS = %w[true false null yes no on off].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      KEY_RE = /\A\s*[\w.\-\/]+\s*(?=:)/
      TAG_RE = /![\w!.\/\-]*/
      ANCHOR_RE = /[&*]\w+/
      COMMENT_RE = /#.*/
      STRING_SINGLE_RE = /'(?:[^'\\]|\\.)*'/
      STRING_DOUBLE_RE = /"(?:[^"\\]|\\.)*"/
      NUMBER_RE = /(?<=[\s:\-\[,]|^)-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\s*$/
      BLOCK_SCALAR_RE = /\A\s*[|>][+-]?\s*$/

      def calculate_indent(lines, target_row, shiftwidth)
      return 0 if target_row == 0

      prev_row = target_row - 1
      prev_row -= 1 while prev_row > 0 && lines[prev_row].to_s.strip.empty?
      prev = lines[prev_row].to_s
      prev_indent = prev[/\A */].size

      # Increase indent after mapping key or list with sub-items
      if prev.match?(/:\s*$/) || prev.match?(/[|>][+-]?\s*$/)
        return prev_indent + shiftwidth
      end

      prev_indent
      end

      def indent_trigger?(line)
      line.to_s.rstrip.match?(/:\s*$/) || line.to_s.rstrip.match?(/[|>][+-]?\s*$/)
      end

      def dedent_trigger(_char)
      nil
      end

      def color_columns(text)
      cols = {}
      apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, KEY_RE, KEYWORD_COLOR)
      apply_regex(cols, text, KEYWORD_RE, "\e[35m")
      apply_regex(cols, text, TAG_RE, CONSTANT_COLOR)
      apply_regex(cols, text, ANCHOR_RE, VARIABLE_COLOR)
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, BLOCK_SCALAR_RE, STRING_COLOR)
      apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
