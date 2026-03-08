# frozen_string_literal: true

module RuVim
  module Lang
    module Base
      module_function

      def indent_trigger?(_line)
        false
      end

      def dedent_trigger(_char)
        nil
      end

      def calculate_indent(_lines, _target_row, _shiftwidth)
        nil
      end

      def on_save(_ctx, _path)
        # no-op
      end
    end

    # Non-highlighted filetypes (extension-only detection)
    Registry.register("text", mod: Base, extensions: %w[.txt])
    Registry.register("css", mod: Base, extensions: %w[.css])
    Registry.register("erlang", mod: Base, extensions: %w[.erl])
  end
end
