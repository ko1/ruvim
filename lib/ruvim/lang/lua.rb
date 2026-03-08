# frozen_string_literal: true

module RuVim
  module Lang
    module Lua
      KEYWORDS = %w[
        and break do else elseif end false for function goto if in
        local nil not or repeat return then true until while
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      LONG_STRING_RE = /\[\[.*?\]\]/
      NUMBER_RE = /\b(?:0[xX][\da-fA-F]+(?:\.[\da-fA-F]+)?(?:[pP][+-]?\d+)?|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/
      LINE_COMMENT_RE = /--(?!\[\[).*/
      BLOCK_COMMENT_RE = /--\[\[.*?\]\]/
      BUILTIN_RE = /\b(?:print|type|tostring|tonumber|pairs|ipairs|next|select|unpack|require|error|assert|pcall|xpcall|setmetatable|getmetatable|rawget|rawset|rawequal|rawlen|table|string|math|io|os|coroutine|debug|package)\b/

      INDENT_OPEN_RE = /\b(?:function|if|for|while|repeat|do|else|elseif)\b/
      INDENT_CLOSE_RE = /\A\s*(?:end|until)\b/
      INDENT_MID_RE = /\A\s*(?:else|elseif)\b/

      DEDENT_TRIGGERS = {
        "d" => /\A(\s*)end\z/,
        "l" => /\A(\s*)until\z/,
        "e" => /\A(\s*)(?:else|elseif)\z/
      }.freeze

      module_function

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row].to_s.strip
          next if line.empty? || line.start_with?("--")

          depth += 1 if line.match?(/\b(?:function|if|for|while|repeat|do)\b/) && !line.match?(/\bend\b/)
          depth -= 1 if line.match?(/\A(?:end|until)\b/)
        end

        target_line = lines[target_row].to_s.strip
        depth -= 1 if target_line.match?(INDENT_CLOSE_RE) || target_line.match?(INDENT_MID_RE)
        depth = 0 if depth < 0
        depth * shiftwidth
      end

      def indent_trigger?(line)
        stripped = line.to_s.rstrip
        stripped.match?(/\b(?:function|if|for|while|repeat|do|then|else)\b/)
      end

      def dedent_trigger(char)
        DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, LONG_STRING_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, BUILTIN_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("lua", mod: Lua,
      extensions: %w[.lua],
      shebangs: ["lua", /\Alua\d*\z/],
      runprg: "lua %")
  end
end
