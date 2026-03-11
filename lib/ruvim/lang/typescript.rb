# frozen_string_literal: true

module RuVim
  module Lang
    class Typescript < Base
      TS_KEYWORDS = %w[
      abstract as declare enum implements interface
      module namespace private protected public readonly
      type keyof infer extends
      never unknown any
      override satisfies
      ].freeze

      ALL_KEYWORDS = (Javascript::KEYWORDS + TS_KEYWORDS).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.join("|")})\b/

      BUFFER_DEFAULTS = { "runprg" => "npx tsx %" }.freeze

      def self.calculate_indent(lines, target_row, shiftwidth)
      Javascript.calculate_indent(lines, target_row, shiftwidth)
      end

      def self.indent_trigger?(line)
      Javascript.indent_trigger?(line)
      end

      def self.dedent_trigger(char)
      Javascript.dedent_trigger(char)
      end

      def self.color_columns(text)
      cols = {}
      apply_regex(cols, text, Javascript::STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, Javascript::STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, Javascript::TEMPLATE_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, Javascript::NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, Javascript::CONSTANT_RE, CONSTANT_COLOR)
      apply_regex(cols, text, Javascript::BLOCK_COMMENT_RE, COMMENT_COLOR, override: true)
      apply_regex(cols, text, Javascript::LINE_COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
