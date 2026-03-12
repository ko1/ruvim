# frozen_string_literal: true

module RuVim
  module Lang
    class Dockerfile < Base
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

      def color_columns(text)
        cols = {}
        apply_regex(cols, text, INSTRUCTION_RE, KEYWORD_COLOR)
        apply_regex(cols, text, FLAG_RE, CONSTANT_COLOR)
        apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
        apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
        apply_regex(cols, text, VARIABLE_RE, VARIABLE_COLOR)
        apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
