# frozen_string_literal: true

module RuVim
  module Lang
    class Scheme < Base
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

      def buffer_defaults

        { "runprg" => "gosh %" }

      end

      def color_columns(text)
      cols = {}
      # Order matters: comment overrides all, then strings, then others
      apply_regex(cols, text, CHAR_RE, STRING_COLOR)
      apply_regex(cols, text, STRING_RE, STRING_COLOR)
      apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)
      apply_regex(cols, text, BOOLEAN_RE, "\e[35m")
      apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)
      apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
      cols
      end
    end
  end
end
