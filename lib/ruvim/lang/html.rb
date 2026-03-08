# frozen_string_literal: true

module RuVim
  module Lang
    module Html
      TAG_RE = /<\/?[\w\-]+/
      TAG_CLOSE_RE = /\/?>/
      ATTR_NAME_RE = /\b[\w\-]+(?==)/
      STRING_DOUBLE_RE = /"(?:[^"\\]|\\.)*"/
      STRING_SINGLE_RE = /'(?:[^'\\]|\\.)*'/
      COMMENT_RE = /<!--.*?-->/
      DOCTYPE_RE = /<!DOCTYPE\b[^>]*/i
      ENTITY_RE = /&\w+;|&#\d+;|&#x[\da-fA-F]+;/

      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, TAG_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, TAG_CLOSE_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, DOCTYPE_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, ATTR_NAME_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, ENTITY_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("html", mod: Html,
      extensions: %w[.html .htm .xml])
  end
end
