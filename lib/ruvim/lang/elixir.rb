# frozen_string_literal: true

module RuVim
  module Lang
    class Elixir < Base
      KEYWORDS = %w[
        def defp defmodule defmacro defmacrop defstruct defprotocol defimpl
        defguard defguardp defdelegate defoverridable defexception
        do end fn if else unless cond case when with for receive after
        raise rescue try catch throw
        import use alias require
        and or not in
        true false nil
        quote unquote
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      HEREDOC_RE = /"""/
      SIGIL_RE = /~[a-zA-Z](?:\(.*?\)|\[.*?\]|\{.*?\}|<.*?>|\/.*?\/|".*?"|\|.*?\|)/
      ATOM_RE = /:\w+|:"(?:\\.|[^"\\])*"/
      MODULE_RE = /\b[A-Z]\w*(?:\.[A-Z]\w*)*/
      NUMBER_RE = /\b(?:0[xXoObB][\da-fA-F_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b/
      COMMENT_RE = /#.*/
      VARIABLE_RE = /@\w+/

      INDENT_OPEN_RE = /\b(?:do|fn)\s*(?:->)?\s*$/
      INDENT_CLOSE_RE = /\A\s*end\b/
      INDENT_MID_RE = /\A\s*(?:else|rescue|catch|after)\b/

      DEDENT_TRIGGERS = {
        "d" => /\A(\s*)end\z/,
        "e" => /\A(\s*)(?:else|rescue)\z/,
        "h" => /\A(\s*)catch\z/,
        "r" => /\A(\s*)after\z/
      }.freeze

      def buffer_defaults

        { "runprg" => "elixir %" }

      end

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row].to_s.strip
          next if line.empty? || line.start_with?("#")

          depth += 1 if line.match?(/\b(?:do|fn)\b/) || line.match?(/->$/)
          depth -= 1 if line.match?(/\Aend\b/)
        end

        target_line = lines[target_row].to_s.strip
        depth -= 1 if target_line.match?(INDENT_CLOSE_RE) || target_line.match?(INDENT_MID_RE)
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
        apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
        apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
        apply_regex(cols, text, ATOM_RE, CONSTANT_COLOR)
        apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
        apply_regex(cols, text, MODULE_RE, CONSTANT_COLOR)
        apply_regex(cols, text, VARIABLE_RE, VARIABLE_COLOR)
        apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
        apply_regex(cols, text, SIGIL_RE, STRING_COLOR)
        apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
