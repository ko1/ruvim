module RuVim
  module Lang
    module Json
      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, /"(?:\\.|[^"\\])*"\s*(?=:)/, "\e[36m")
        Highlighter.apply_regex(cols, text, /"(?:\\.|[^"\\])*"/, "\e[32m")
        Highlighter.apply_regex(cols, text, /\b(?:true|false|null)\b/, "\e[35m")
        Highlighter.apply_regex(cols, text, /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, "\e[33m")
        cols
      end
    end
  end
end
