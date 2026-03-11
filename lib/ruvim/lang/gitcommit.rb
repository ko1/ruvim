# frozen_string_literal: true

module RuVim
  module Lang
    module Gitcommit
      COMMENT_COLOR = "\e[90m"  # gray

      module_function

      BUFFER_DEFAULTS = { "spell" => true }.freeze

      def color_columns(text)
        cols = {}
        if text.start_with?("#")
          text.length.times { |i| cols[i] = COMMENT_COLOR }
        end
        cols
      end
    end
  end
end
