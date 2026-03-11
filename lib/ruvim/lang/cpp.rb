# frozen_string_literal: true

require "open3"

module RuVim
  module Lang
    module Cpp
      CPP_KEYWORDS = %w[
        class namespace template typename virtual override final
        public private protected friend
        new delete dynamic_cast static_cast reinterpret_cast const_cast
        try catch throw noexcept
        using auto decltype nullptr constexpr consteval constinit
        concept requires co_await co_return co_yield
        mutable explicit export
      ].freeze

      CPP_TYPES = %w[
        string vector map set list deque array
        shared_ptr unique_ptr weak_ptr
        string_view optional variant any
        wchar_t char8_t char16_t char32_t
      ].freeze

      ALL_KEYWORDS = (C::ALL_KEYWORDS + CPP_KEYWORDS + CPP_TYPES).uniq.freeze

      KEYWORD_RE = /\b(?:#{ALL_KEYWORDS.join("|")})\b/

      ACCESS_RE = /\A\s*(?:public|private|protected)\s*:/

      module_function

      BUFFER_DEFAULTS = { "runprg" => "g++ -Wall -o /tmp/a.out % && /tmp/a.out" }.freeze

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
        depth -= 1 if target_line.match?(C::INDENT_CLOSE_RE)
        depth -= 1 if target_line.match?(C::CASE_RE) && depth > 0
        depth -= 1 if target_line.match?(ACCESS_RE) && depth > 0
        depth = 0 if depth < 0
        depth * shiftwidth
      end

      def indent_trigger?(line)
        C.indent_trigger?(line)
      end

      def dedent_trigger(char)
        C.dedent_trigger(char)
      end

      def on_save(ctx, path)
        return unless path && File.exist?(path)
        return if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

        compiler = ENV["CXX"] || "g++"
        begin
          output, status = Open3.capture2e(compiler, "-fsyntax-only", "-Wall", path)
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
        Highlighter.apply_regex(cols, text, C::CHAR_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, C::STRING_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, C::NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, C::CONSTANT_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, C::PREPROCESSOR_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, C::BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, C::LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
