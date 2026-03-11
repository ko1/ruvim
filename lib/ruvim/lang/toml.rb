# frozen_string_literal: true

module RuVim
  module Lang
    class Toml < Base
      KEYWORD_RE = /\b(?:true|false)\b/
      TABLE_RE = /\A\s*\[[\w.\-"]+\]/
      ARRAY_TABLE_RE = /\A\s*\[\[[\w.\-"]+\]\]/
      KEY_RE = /\A\s*[\w.\-]+\s*(?==)/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'[^']*'/
      NUMBER_RE = /(?<=[= ])[+-]?(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b/
      DATETIME_RE = /\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?/
      COMMENT_RE = /#.*/

      def self.color_columns(text)
      cols = {}
      apply_regex(cols, text, ARRAY_TABLE_RE, "\e[1;36m")
      apply_regex(cols, text, TABLE_RE, "\e[1;36m")
      apply_regex(cols, text, KEY_RE, KEYWORD_COLOR)
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, "\e[35m")
      apply_regex(cols, text, DATETIME_RE, CONSTANT_COLOR)
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
