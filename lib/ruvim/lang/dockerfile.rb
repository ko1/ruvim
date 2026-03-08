# frozen_string_literal: true

module RuVim
  module Lang
    module Dockerfile
      INSTRUCTIONS = %w[
        FROM AS RUN CMD EXPOSE ENV ADD COPY ENTRYPOINT VOLUME
        USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL LABEL MAINTAINER
      ].freeze

      INSTRUCTION_RE = /\A\s*(?:#{INSTRUCTIONS.join("|")})\b/i
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      VARIABLE_RE = /\$\{?[\w]+\}?/
      COMMENT_RE = /\A\s*#.*/
      FLAG_RE = /--[\w\-]+=?/

      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, INSTRUCTION_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, FLAG_RE, Highlighter::CONSTANT_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, VARIABLE_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end

    Registry.register("dockerfile", mod: Dockerfile,
      basenames: %w[Dockerfile],
      basename_prefix: "Dockerfile")
  end
end
