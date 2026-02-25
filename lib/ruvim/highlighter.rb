module RuVim
  module Highlighter
    module_function

    def color_columns(filetype, line)
      ft = filetype.to_s
      text = line.to_s
      return {} if text.empty?

      case ft
      when "ruby"
        ruby_color_columns(text)
      when "json"
        json_color_columns(text)
      else
        {}
      end
    end

    def ruby_color_columns(text)
      cols = {}
      apply_regex(cols, text, /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, "\e[32m")
      apply_regex(cols, text, /\b(?:def|class|module|end|if|elsif|else|unless|case|when|do|while|until|begin|rescue|ensure|return|yield)\b/, "\e[36m")
      apply_regex(cols, text, /\b\d+(?:\.\d+)?\b/, "\e[33m")
      apply_regex(cols, text, /#.*\z/, "\e[90m", override: true)
      cols
    end

    def json_color_columns(text)
      cols = {}
      apply_regex(cols, text, /"(?:\\.|[^"\\])*"\s*(?=:)/, "\e[36m")
      apply_regex(cols, text, /"(?:\\.|[^"\\])*"/, "\e[32m")
      apply_regex(cols, text, /\b(?:true|false|null)\b/, "\e[35m")
      apply_regex(cols, text, /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, "\e[33m")
      cols
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

    module_function :ruby_color_columns, :json_color_columns, :apply_regex
  end
end
