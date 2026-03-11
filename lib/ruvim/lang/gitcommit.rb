# frozen_string_literal: true

module RuVim
  module Lang
    module Gitcommit
      COMMENT_COLOR = "\e[90m"  # gray

      module_function

      def color_columns(text)
        cols = {}
        if text.start_with?("#")
          text.length.times { |i| cols[i] = COMMENT_COLOR }
        end
        cols
      end
    end

    Registry.register("gitcommit",
                       mod: Gitcommit,
                       buffer_defaults: { "spell" => true })
  end
end
