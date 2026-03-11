# frozen_string_literal: true

module RuVim
  module Lang
    module Scheme
      KEYWORDS = %w[
        define define-syntax define-record-type define-values define-library
        lambda let let* letrec letrec* let-values let-syntax letrec-syntax
        if cond case when unless and or not
        begin do set! quote quasiquote unquote unquote-splicing
        syntax-rules syntax-case
        import export library
        else =>
        call-with-current-continuation call/cc
        call-with-values values
        dynamic-wind
        guard raise raise-continuable with-exception-handler
        parameterize make-parameter
        include include-ci
      ].freeze

      KEYWORD_RE = /(?<=[\s(])(#{KEYWORDS.map { |k| Regexp.escape(k) }.join("|")})(?=[\s()\]]|$)/
      COMMENT_RE = /;.*/
      STRING_RE = /"(?:\\.|[^"\\])*"/
      CHAR_RE = /#\\(?:space|newline|tab|alarm|backspace|delete|escape|null|return|[^\s()])/
      BOOLEAN_RE = /#[tf]\b/
      NUMBER_RE = /(?<=[\s(])[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?(?=[\s()\]]|$)/

      module_function

      BUFFER_DEFAULTS = { "runprg" => "gosh %" }.freeze

      def color_columns(text)
        cols = {}
        # Order matters: comment overrides all, then strings, then others
        Highlighter.apply_regex(cols, text, CHAR_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, BOOLEAN_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
