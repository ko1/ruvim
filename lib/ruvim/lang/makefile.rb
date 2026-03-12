# frozen_string_literal: true

module RuVim
  module Lang
    class Makefile < Base
      TARGET_RE = /\A[\w.\-\/]+\s*:/
      VARIABLE_DEF_RE = /\A[\w.\-]+\s*[?:+]?=/
      VARIABLE_REF_RE = /\$[({][\w.\-]+[)}]|\$[A-Za-z@<*^?%]/
      DIRECTIVE_RE = /\A\s*(?:ifeq|ifneq|ifdef|ifndef|else|endif|define|endef|include|-include|sinclude|override|export|unexport|vpath)\b/
      FUNCTION_RE = /\$\((?:subst|patsubst|strip|findstring|filter|filter-out|sort|word|wordlist|words|firstword|lastword|dir|notdir|suffix|basename|addsuffix|addprefix|join|wildcard|realpath|abspath|foreach|if|or|and|call|eval|file|value|error|warning|info|shell|origin|flavor|guile)\b/
      COMMENT_RE = /#.*/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      AUTO_VAR_RE = /\$[@<*^?%]/

      def color_columns(text)
        cols = {}
        apply_regex(cols, text, TARGET_RE, "\e[1;33m")
        apply_regex(cols, text, VARIABLE_DEF_RE, KEYWORD_COLOR)
        apply_regex(cols, text, DIRECTIVE_RE, KEYWORD_COLOR)
        apply_regex(cols, text, STRING_DOUBLE_RE, STRING_COLOR)
        apply_regex(cols, text, STRING_SINGLE_RE, STRING_COLOR)
        apply_regex(cols, text, FUNCTION_RE, "\e[35m")
        apply_regex(cols, text, VARIABLE_REF_RE, VARIABLE_COLOR)
        apply_regex(cols, text, AUTO_VAR_RE, VARIABLE_COLOR)
        apply_regex(cols, text, COMMENT_RE, COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
