# frozen_string_literal: true

module RuVim
  module Lang
    class Erb < Base
      ERB_COMMENT_RE = /<%#.*?%>/
      ERB_TAG_RE = /<%[=\-]?|[-%]?%>/

      def self.color_columns(text)
      cols = {}

      # First apply HTML highlighting as base
      Html.color_columns(text).each { |k, v| cols[k] = v }

      # ERB delimiters (<%= %> <% %> <%- -%>)
      apply_regex(cols, text, ERB_TAG_RE, "\e[35m", override: true)

      # ERB comment tags override everything (including delimiters)
      apply_regex(cols, text, ERB_COMMENT_RE, COMMENT_COLOR, override: true)

      cols
      end
    end
  end
end
