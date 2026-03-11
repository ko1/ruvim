# frozen_string_literal: true

module RuVim
  module Lang
    class Sh < Base
      KEYWORDS = %w[
      if then else elif fi case esac for while until do done
      in function select return exit break continue
      local export readonly declare typeset unset
      source eval exec trap set shopt
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_SINGLE_RE = /'[^']*'/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      VARIABLE_RE = /\$\{?[A-Za-z_]\w*\}?|\$[0-9@#?!\-*$]/
      NUMBER_RE = /\b\d+\b/
      COMMENT_RE = /#.*/
      SHEBANG_RE = /\A#!.*/
      OPERATOR_RE = /(?:\|\||&&|;;|<<|>>)/

      INDENT_OPEN_RE = /\b(?:then|else|do)\s*$/
      INDENT_CLOSE_RE = /\A\s*(?:fi|done|esac|else|elif)\b/

      DEDENT_TRIGGERS = {
      "i" => /\A(\s*)fi\z/,
      "e" => /\A(\s*)(?:done|else)\z/,
      "c" => /\A(\s*)esac\z/,
      "f" => /\A(\s*)elif\z/
      }.freeze

      BUFFER_DEFAULTS = { "runprg" => "bash %" }.freeze

      def calculate_indent(lines, target_row, shiftwidth)
      depth = 0
      (0...target_row).each do |row|
        line = lines[row].to_s.strip
        next if line.empty? || line.start_with?("#")

        depth += 1 if line.match?(/\b(?:then|else|elif|do)\s*$/) || line.match?(/\{\s*$/)
        depth -= 1 if line.match?(/\A(?:fi|done|esac)\b/) || line.match?(/\A\}/)
      end

      target_line = lines[target_row].to_s.strip
      depth -= 1 if target_line.match?(/\A(?:fi|done|esac|else|elif)\b/) || target_line.match?(/\A\}/)
      depth = 0 if depth < 0
      depth * shiftwidth
      end

      def indent_trigger?(line)
      stripped = line.to_s.rstrip
      stripped.match?(/\b(?:then|else|elif|do)\s*$/) || stripped.match?(/\{\s*$/)
      end

      def dedent_trigger(char)
      DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
      cols = {}
      apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, VARIABLE_RE, VARIABLE_COLOR)
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
