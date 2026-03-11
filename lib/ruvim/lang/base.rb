# frozen_string_literal: true

module RuVim
  module Lang
    class Base
      KEYWORD_COLOR = "\e[36m"
      STRING_COLOR = "\e[32m"
      NUMBER_COLOR = "\e[33m"
      COMMENT_COLOR = "\e[90m"
      VARIABLE_COLOR = "\e[93m"
      CONSTANT_COLOR = "\e[96m"

      def self.apply_regex(cols, text, regex, color, override: false)
        text.to_enum(:scan, regex).each do
          m = Regexp.last_match
          next unless m
          (m.begin(0)...m.end(0)).each do |idx|
            next if cols.key?(idx) && !override

            cols[idx] = color
          end
        end
      end

      def self.indent_trigger?(_line)
        false
      end

      def self.dedent_trigger(_char)
        nil
      end

      def self.calculate_indent(_lines, _target_row, _shiftwidth)
        nil
      end

      def self.on_save(_ctx, _path)
        # no-op
      end
    end
  end
end
