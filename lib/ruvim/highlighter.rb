module RuVim
  module Highlighter
    require "prism"

    KEYWORD_COLOR = "\e[36m"
    STRING_COLOR = "\e[32m"
    NUMBER_COLOR = "\e[33m"
    COMMENT_COLOR = "\e[90m"
    VARIABLE_COLOR = "\e[93m"
    CONSTANT_COLOR = "\e[96m"

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
      when "markdown"
        Lang::Markdown.color_columns(text)
      else
        {}
      end
    end

    def ruby_color_columns(text)
      cols = {}
      Prism.lex(text).value.each do |entry|
        token = entry[0]
        type = token.type
        range = token.location.start_offset...token.location.end_offset
        if PRISM_STRING_TYPES.include?(type)
          range.each { |idx| cols[idx] = STRING_COLOR unless cols.key?(idx) }
        elsif PRISM_KEYWORD_TYPES.include?(type)
          range.each { |idx| cols[idx] = KEYWORD_COLOR unless cols.key?(idx) }
        elsif PRISM_NUMBER_TYPES.include?(type)
          range.each { |idx| cols[idx] = NUMBER_COLOR unless cols.key?(idx) }
        elsif PRISM_VARIABLE_TYPES.include?(type)
          range.each { |idx| cols[idx] = VARIABLE_COLOR unless cols.key?(idx) }
        elsif PRISM_CONSTANT_TYPES.include?(type)
          range.each { |idx| cols[idx] = CONSTANT_COLOR unless cols.key?(idx) }
        elsif PRISM_COMMENT_TYPES.include?(type)
          range.each { |idx| cols[idx] = COMMENT_COLOR }
        end
      end
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
