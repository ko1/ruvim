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
    end
  end
end
