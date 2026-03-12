# frozen_string_literal: true

module RuVim
  module Lang
    class Gitcommit < Base
      COMMENT_COLOR = "\e[90m"  # gray

      def buffer_defaults

        { "spell" => true }

      end

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
