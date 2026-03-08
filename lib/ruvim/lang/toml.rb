# frozen_string_literal: true

module RuVim
  module Lang
    module Toml
      KEYWORD_RE = /\b(?:true|false)\b/
      TABLE_RE = /\A\s*\[[\w.\-"]+\]/
      ARRAY_TABLE_RE = /\A\s*\[\[[\w.\-"]+\]\]/
      KEY_RE = /\A\s*[\w.\-]+\s*(?==)/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'[^']*'/
      NUMBER_RE = /(?<=[= ])[+-]?(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b/
      DATETIME_RE = /\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?/
      COMMENT_RE = /#.*/

      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, ARRAY_TABLE_RE, "\e[1;36m")
        Highlighter.apply_regex(cols, text, TABLE_RE, "\e[1;36m")
        Highlighter.apply_regex(cols, text, KEY_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, DATETIME_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("toml", mod: Toml,
      extensions: %w[.toml])
  end
end
