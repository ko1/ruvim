# frozen_string_literal: true

module RuVim
  module Lang
    module Erb
      ERB_COMMENT_RE = /<%#.*?%>/
      ERB_TAG_RE = /<%[=\-]?|[-%]?%>/

      module_function

      def color_columns(text)
        cols = {}

        # First apply HTML highlighting as base
        Html.color_columns(text).each { |k, v| cols[k] = v }

        # ERB delimiters (<%= %> <% %> <%- -%>)
        Highlighter.apply_regex(cols, text, ERB_TAG_RE, "\e[35m", override: true)

        # ERB comment tags override everything (including delimiters)
        Highlighter.apply_regex(cols, text, ERB_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)

        cols
      end
    end
  end
end
