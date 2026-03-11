# frozen_string_literal: true

module RuVim
  module Lang
    module Perl
      KEYWORDS = %w[
        my our local sub return if elsif else unless while until for
        foreach do given when default last next redo goto
        use require package no BEGIN END
        die warn print say chomp chop push pop shift unshift
        open close read write seek tell
        map grep sort reverse join split
        defined undef delete exists ref bless
        eval try catch finally
        and or not xor
        eq ne lt gt le ge cmp
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      REGEX_RE = %r{(?<=[=~(,;\s])(?:m|s|tr|y)?/(?:\\.|[^/\\])*/[gimxsecpodualn]*}
      QW_RE = /\bqw\s*[({<\/|].*?[)}>\/|]/
      SCALAR_RE = /\$[\w]+/
      ARRAY_RE = /@[\w]+/
      HASH_RE = /%[\w]+/
      SPECIAL_VAR_RE = /\$[_!@&`'+\\\/\-\[\]]/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b/
      COMMENT_RE = /#.*/
      POD_RE = /\A=[a-zA-Z]\w*/

      INDENT_OPEN_RE = /\{\s*(?:#.*)?$/
      INDENT_CLOSE_RE = /\A\s*\}/

      DEDENT_TRIGGERS = {
        "}" => /\A(\s*)\}/
      }.freeze

      module_function

      BUFFER_DEFAULTS = { "runprg" => "perl %" }.freeze

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row].to_s
          line.each_char do |ch|
            case ch
            when "{" then depth += 1
            when "}" then depth -= 1
            end
          end
        end

        target_line = lines[target_row].to_s.lstrip
        depth -= 1 if target_line.match?(INDENT_CLOSE_RE)
        depth = 0 if depth < 0
        depth * shiftwidth
      end

      def indent_trigger?(line)
        line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def dedent_trigger(char)
        DEDENT_TRIGGERS[char]
      end

      def color_columns(text)
        cols = {}
        # POD documentation
        if text.match?(POD_RE)
          text.length.times { |i| cols[i] = Highlighter::COMMENT_COLOR }
          return cols
        end
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, SCALAR_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, ARRAY_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, HASH_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
