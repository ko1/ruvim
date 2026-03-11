# frozen_string_literal: true

module RuVim
  module Highlighter
    KEYWORD_COLOR = "\e[36m"
    STRING_COLOR = "\e[32m"
    NUMBER_COLOR = "\e[33m"
    COMMENT_COLOR = "\e[90m"
    VARIABLE_COLOR = "\e[93m"
    CONSTANT_COLOR = "\e[96m"

    module_function

    def color_columns(filetype, line)
      ft = filetype.to_s
      return {} if line.empty?
      return {} unless Lang::Registry.highlight?(ft)

      Lang::Registry.resolve_module(ft).color_columns(line)
    end

    def apply_regex(cols, text, regex, color, override: false)
      text.to_enum(:scan, regex).each do
        m = Regexp.last_match
        next unless m
        (m.begin(0)...m.end(0)).each do |idx|
          next if cols.key?(idx) && !override

          cols[idx] = color
        end
      end
    end

    module_function :apply_regex
  end
end
