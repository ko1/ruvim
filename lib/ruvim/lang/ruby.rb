# frozen_string_literal: true

require "prism"
require "open3"

module RuVim
  module Lang
    module Ruby
      PRISM_KEYWORD_TYPES = %i[
        KEYWORD_ALIAS
        KEYWORD_AND
        KEYWORD_BEGIN
        KEYWORD_BEGIN_UPCASE
        KEYWORD_BREAK
        KEYWORD_CASE
        KEYWORD_CLASS
        KEYWORD_DEF
        KEYWORD_DEFINED
        KEYWORD_DO
        KEYWORD_ELSE
        KEYWORD_ELSIF
        KEYWORD_END
        KEYWORD_ENSURE
        KEYWORD_FALSE
        KEYWORD_FOR
        KEYWORD_IF
        KEYWORD_IF_MODIFIER
        KEYWORD_IN
        KEYWORD_MODULE
        KEYWORD_NEXT
        KEYWORD_NIL
        KEYWORD_NOT
        KEYWORD_OR
        KEYWORD_REDO
        KEYWORD_RESCUE
        KEYWORD_RESCUE_MODIFIER
        KEYWORD_RETRY
        KEYWORD_RETURN
        KEYWORD_SELF
        KEYWORD_SUPER
        KEYWORD_THEN
        KEYWORD_TRUE
        KEYWORD_UNDEF
        KEYWORD_UNLESS
        KEYWORD_UNLESS_MODIFIER
        KEYWORD_UNTIL
        KEYWORD_UNTIL_MODIFIER
        KEYWORD_WHEN
        KEYWORD_WHILE
        KEYWORD_WHILE_MODIFIER
        KEYWORD_YIELD
        MISSING
      ].freeze

      PRISM_STRING_TYPES = %i[
        STRING_BEGIN
        STRING_CONTENT
        STRING_END
        SYMBOL_BEGIN
        REGEXP_BEGIN
        REGEXP_CONTENT
        REGEXP_END
        XSTRING_BEGIN
        XSTRING_CONTENT
        XSTRING_END
        WORDS_BEGIN
        QWORDS_BEGIN
        WORDS_SEPARATOR
        STRING
        CHARACTER_LITERAL
      ].freeze

      PRISM_NUMBER_TYPES = %i[
        INTEGER
        FLOAT
        RATIONAL_NUMBER
        IMAGINARY_NUMBER
        UINTEGER
      ].freeze

      PRISM_COMMENT_TYPES = %i[
        COMMENT
        EMBDOC_BEGIN
        EMBDOC_LINE
        EMBDOC_END
      ].freeze

      PRISM_VARIABLE_TYPES = %i[
        INSTANCE_VARIABLE
        CLASS_VARIABLE
        GLOBAL_VARIABLE
      ].freeze

      PRISM_CONSTANT_TYPES = %i[
        CONSTANT
      ].freeze

      # Keywords that open a new indentation level
      INDENT_OPEN_RE = /\A\s*(?:def|class|module|if|unless|while|until|for|begin|case)\b/
      # `do` at end of line (block form)
      INDENT_DO_RE = /\bdo\s*(\|[^|]*\|)?\s*$/
      # Opening brackets at end of line
      INDENT_BRACKET_OPEN_RE = /[\[({]\s*$/
      # Keywords that close an indentation level
      INDENT_CLOSE_RE = /\A\s*(?:end|[}\])])/
      # Keywords at same level as their opening keyword (dedent for the line itself)
      INDENT_MID_RE = /\A\s*(?:else|elsif|when|rescue|ensure|in)\b/
      # Modifier keywords that do NOT open indentation
      MODIFIER_RE = /\b(?:if|unless|while|until|rescue)\b/

      module_function

      def calculate_indent(lines, target_row, shiftwidth)
        depth = 0
        (0...target_row).each do |row|
          line = lines[row]
          stripped = line.to_s.lstrip

          # Skip blank and comment lines for indent computation
          next if stripped.empty? || stripped.start_with?("#")

          # Check if the line opens a new level
          if stripped.match?(INDENT_OPEN_RE)
            # Check for modifier form: something before the keyword on the same line
            # e.g. "return if true" — if keyword is not at start, it's a modifier
            first_word = stripped[/\A(\w+)/, 1]
            if %w[if unless while until rescue].include?(first_word)
              depth += 1
            elsif %w[def class module begin case for].include?(first_word)
              depth += 1
            end
          elsif stripped.match?(INDENT_DO_RE)
            depth += 1
          end

          # Count opening brackets (not at end-of-line pattern, but individual)
          stripped.each_char do |ch|
            case ch
            when "{", "[", "("
              depth += 1
            when "}", "]", ")"
              depth -= 1
            end
          end if !stripped.match?(INDENT_OPEN_RE) && !stripped.match?(INDENT_DO_RE)

          # Handle closing keywords
          if stripped.match?(/\A\s*end\b/)
            depth -= 1
          end

          # Handle mid keywords (else/elsif/when/rescue/ensure) — they don't change depth for following lines
        end

        # Now compute indent for target_row
        target_line = lines[target_row].to_s.lstrip

        # If target line is a closing keyword, dedent
        if target_line.match?(INDENT_CLOSE_RE)
          depth -= 1
        elsif target_line.match?(INDENT_MID_RE)
          depth -= 1
        end

        depth = 0 if depth < 0
        depth * shiftwidth
      end

      # Returns true if the line should increase indent for the next line
      def indent_trigger?(line)
        stripped = line.to_s.rstrip.lstrip
        first_word = stripped[/\A(\w+)/, 1].to_s
        return true if %w[def class module if unless while until for begin case].include?(first_word)
        return true if stripped.match?(/\bdo\s*(\|[^|]*\|)?\s*$/)
        false
      end

      # Dedent trigger patterns keyed by the last character typed
      DEDENT_TRIGGERS = {
        "d" => /\A(\s*)end\z/,
        "e" => /\A(\s*)(?:else|rescue|ensure)\z/,
        "f" => /\A(\s*)elsif\z/,
        "n" => /\A(\s*)(?:when|in)\z/
      }.freeze

      # Returns the dedent pattern for the given character, or nil
      def dedent_trigger(char)
        DEDENT_TRIGGERS[char]
      end

      def on_save(ctx, path)
        return unless path && File.exist?(path)
        return if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?
        output, status = Open3.capture2e("ruby", "-wc", path)
        message = output.sub(/^Syntax OK\n?\z/m, "").strip

        if !status.success? || !message.empty?
          buffer_id = ctx.buffer.id
          items = message.lines.filter_map { |line|
            if line =~ /\A.+?:(\d+):/
              { buffer_id: buffer_id, row: $1.to_i - 1, col: 0, text: line.strip }
            end
          }
          items = [{ buffer_id: buffer_id, row: 0, col: 0, text: message }] if items.empty?
          ctx.editor.set_quickfix_list(items)
          first = message.lines.first.to_s.strip
          hint = items.size > 1 ? " (Q to see all, #{items.size} total)" : ""
          ctx.editor.echo_error("#{first}#{hint}")
        else
          ctx.editor.set_quickfix_list([])
        end
      end

      def color_columns(text)
        cols = {}
        Prism.lex(text).value.each do |entry|
          token = entry[0]
          type = token.type
          range = token.location.start_offset...token.location.end_offset
          if PRISM_STRING_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::STRING_COLOR unless cols.key?(idx) }
          elsif PRISM_KEYWORD_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::KEYWORD_COLOR unless cols.key?(idx) }
          elsif PRISM_NUMBER_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::NUMBER_COLOR unless cols.key?(idx) }
          elsif PRISM_VARIABLE_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::VARIABLE_COLOR unless cols.key?(idx) }
          elsif PRISM_CONSTANT_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::CONSTANT_COLOR unless cols.key?(idx) }
          elsif PRISM_COMMENT_TYPES.include?(type)
            range.each { |idx| cols[idx] = Highlighter::COMMENT_COLOR }
          end
        end
        cols
      end
    end

    Registry.register("ruby", mod: Ruby,
      extensions: %w[.rb .rake .ru],
      basenames: %w[Gemfile Rakefile Guardfile Vagrantfile],
      shebangs: [/\Aruby(?:\d+(?:\.\d+)*)?\z/],
      buffer_defaults: { "runprg" => "ruby -w %" })
  end
end
