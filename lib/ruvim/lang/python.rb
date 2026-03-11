# frozen_string_literal: true

module RuVim
  module Lang
    class Python < Base
      KEYWORDS = %w[
      and as assert async await break class continue def del elif else
      except finally for from global if import in is lambda nonlocal
      not or pass raise return try while with yield
      True False None
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_TRIPLE_DQ_RE = /""".*?"""/m
      STRING_TRIPLE_SQ_RE = /'''.*?'''/m
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      FSTRING_PREFIX_RE = /[fFrRbBuU]{1,2}(?=["'])/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?j?)\b/
      DECORATOR_RE = /@[\w.]+/
      COMMENT_RE = /#.*/
      CONSTANT_RE = /\b[A-Z][A-Z0-9_]{1,}\b/
      BUILTIN_RE = /\b(?:print|len|range|type|int|str|float|list|dict|tuple|set|bool|open|input|map|filter|zip|enumerate|sorted|reversed|super|isinstance|issubclass|hasattr|getattr|setattr|delattr|property|staticmethod|classmethod|__\w+__)\b/

      INDENT_OPEN_RE = /:\s*(?:#.*)?$/
      INDENT_CLOSE_RE = /\A\s*(?:return|break|continue|pass|raise)\b/

      DEDENT_TRIGGERS = {
      "s" => /\A(\s*)(?:else|class)\z/,
      ":" => /\A(\s*)(?:else|elif|except|finally)\s*.*:\z/,
      "f" => /\A(\s*)elif\z/
      }.freeze

      def buffer_defaults

        { "runprg" => "python3 %" }

      end

      def calculate_indent(lines, target_row, shiftwidth)
      return 0 if target_row == 0

      prev_row = target_row - 1
      prev_row -= 1 while prev_row > 0 && lines[prev_row].to_s.strip.empty?
      prev = lines[prev_row].to_s
      prev_indent = prev[/\A */].size

      if prev.rstrip.match?(INDENT_OPEN_RE)
        return prev_indent + shiftwidth
      end

      target_line = lines[target_row].to_s.strip
      if target_line.match?(/\A(?:else|elif|except|finally)\b/)
        depth = prev_indent - shiftwidth
        return depth < 0 ? 0 : depth
      end

      prev_indent
      end

      def indent_trigger?(line)
      line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def dedent_trigger(char)
      DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
      cols = {}
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, FSTRING_PREFIX_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, BUILTIN_RE, "\e[35m")
      apply_regex(cols, text, DECORATOR_RE, "\e[35m")
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, CONSTANT_RE, CONSTANT_COLOR)
      apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
