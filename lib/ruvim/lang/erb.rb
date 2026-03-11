# frozen_string_literal: true

module RuVim
  module Lang
    class Erb < Html
      ERB_COMMENT_RE = /<%#.*?%>/
      ERB_TAG_RE = /<%[=\-]?|[-%]?%>/

      def color_columns(text)
        cols = super

        # ERB delimiters (<%= %> <% %> <%- -%>)
        apply_regex(cols, text, ERB_TAG_RE, "\e[35m", override: true)

        # ERB comment tags override everything (including delimiters)
        apply_regex(cols, text, ERB_COMMENT_RE, COMMENT_COLOR, override: true)

        cols
      end
    end
  end
end
