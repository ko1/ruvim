# frozen_string_literal: true

require "open3"

module RuVim
  module Lang
    module C
      KEYWORDS = %w[
        if else for while return struct enum typedef switch case break
        continue do static const extern unsigned signed sizeof union
        goto default volatile register inline restrict
      ].freeze

      TYPES = %w[
        int char float double long short void size_t
        uint8_t uint16_t uint32_t uint64_t
        int8_t int16_t int32_t int64_t
        ssize_t ptrdiff_t intptr_t uintptr_t
        bool FILE
      ].freeze

      ALL_KEYWORDS = (KEYWORDS + TYPES).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.join("|")})\b/
      STRING_RE = /"(?:\\.|[^"\\])*"/
      CHAR_RE = /'(?:\\.|[^'\\])'/
      NUMBER_RE = /\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[fFlLuU]*\b/
      LINE_COMMENT_RE = %r{//.*}
      BLOCK_COMMENT_RE = %r{/\*.*?\*/}
      PREPROCESSOR_RE = /\A\s*#\s*\w+.*/
      CONSTANT_RE = /\b[A-Z][A-Z0-9_]{1,}\b/

      INDENT_OPEN_RE = /\{\s*$/
      INDENT_CLOSE_RE = /\A\s*\}/
      CASE_RE = /\A\s*(?:case\b.*:|default\s*:)/

      DEDENT_TRIGGERS = {
        "}" => /\A(\s*)\}/
      }.freeze

      module_function

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
        depth -= 1 if target_line.match?(CASE_RE) && depth > 0
        depth = 0 if depth < 0
        depth * shiftwidth
      end

      def indent_trigger?(line)
        line.to_s.rstrip.match?(INDENT_OPEN_RE)
      end

      def dedent_trigger(char)
        DEDENT_TRIGGERS[char]
      end

      def on_save(ctx, path)
        return unless path && File.exist?(path)
        return if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

        gcc = ENV["CC"] || "gcc"
        begin
          output, status = Open3.capture2e(gcc, "-fsyntax-only", "-Wall", path)
        rescue Errno::ENOENT
          return
        end

        if !status.success?
          buffer_id = ctx.buffer.id
          items = output.lines.filter_map { |line|
            if line =~ /\A.+?:(\d+):\d+:/
              { buffer_id: buffer_id, row: $1.to_i - 1, col: 0, text: line.strip }
            end
          }
          items = [{ buffer_id: buffer_id, row: 0, col: 0, text: output.strip }] if items.empty?
          ctx.editor.set_quickfix_list(items)
          first = output.lines.first.to_s.strip
          hint = items.size > 1 ? " (Q to see all, #{items.size} total)" : ""
          ctx.editor.echo_error("#{first}#{hint}")
        else
          ctx.editor.set_quickfix_list([])
        end
      end

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, CHAR_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, CONSTANT_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, PREPROCESSOR_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("c", mod: C,
      extensions: %w[.c .h],
      buffer_defaults: { "runprg" => "gcc -Wall -o /tmp/a.out % && /tmp/a.out" })
  end
end
