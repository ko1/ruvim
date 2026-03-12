# frozen_string_literal: true

module RuVim
  module Lang
    class Html < Base
      TAG_RE = /<\/?[\w\-]+/
      TAG_CLOSE_RE = /\/?>/
      ATTR_NAME_RE = /\b[\w\-]+(?==)/
      STRING_DOUBLE_RE = /"(?:[^"\\]|\\.)*"/
      STRING_SINGLE_RE = /'(?:[^'\\]|\\.)*'/
      COMMENT_RE = /<!--.*?-->/
      DOCTYPE_RE = /<!DOCTYPE\b[^>]*/i
      ENTITY_RE = /&\w+;|&#\d+;|&#x[\da-fA-F]+;/

      def color_columns(text)
        cols = {}
        apply_regex(cols, text, TAG_RE, KEYWORD_COLOR)
        apply_regex(cols, text, TAG_CLOSE_RE, KEYWORD_COLOR)
        apply_regex(cols, text, DOCTYPE_RE, "\e[35m")
        apply_regex(cols, text, ATTR_NAME_RE, VARIABLE_COLOR)
        apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
        apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
        apply_regex(cols, text, ENTITY_RE, CONSTANT_COLOR)
        apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
