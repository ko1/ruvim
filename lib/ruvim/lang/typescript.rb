# frozen_string_literal: true

module RuVim
  module Lang
    module Typescript
      TS_KEYWORDS = %w[
        abstract as declare enum implements interface
        module namespace private protected public readonly
        type keyof infer extends
        never unknown any
        override satisfies
      ].freeze

      ALL_KEYWORDS = (Javascript::KEYWORDS + TS_KEYWORDS).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.join("|")})\b/

      module_function

      def calculate_indent(lines, target_row, shiftwidth)
        Javascript.calculate_indent(lines, target_row, shiftwidth)
      end

      def indent_trigger?(line)
        Javascript.indent_trigger?(line)
      end

      def dedent_trigger(char)
        Javascript.dedent_trigger(char)
      end

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, Javascript::STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, Javascript::STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, Javascript::TEMPLATE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, Javascript::NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, Javascript::CONSTANT_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, Javascript::BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, Javascript::LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
