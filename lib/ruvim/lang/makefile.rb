# frozen_string_literal: true

module RuVim
  module Lang
    module Makefile
      TARGET_RE = /\A[\w.\-\/]+\s*:/
      VARIABLE_DEF_RE = /\A[\w.\-]+\s*[?:+]?=/
      VARIABLE_REF_RE = /\$[({][\w.\-]+[)}]|\$[A-Za-z@<*^?%]/
      DIRECTIVE_RE = /\A\s*(?:ifeq|ifneq|ifdef|ifndef|else|endif|define|endef|include|-include|sinclude|override|export|unexport|vpath)\b/
      FUNCTION_RE = /\$\((?:subst|patsubst|strip|findstring|filter|filter-out|sort|word|wordlist|words|firstword|lastword|dir|notdir|suffix|basename|addsuffix|addprefix|join|wildcard|realpath|abspath|foreach|if|or|and|call|eval|file|value|error|warning|info|shell|origin|flavor|guile)\b/
      COMMENT_RE = /#.*/
      STRING_DOUBLE_RE = /"(?:\\.|[^"\\])*"/
      STRING_SINGLE_RE = /'(?:\\.|[^'\\])*'/
      AUTO_VAR_RE = /\$[@<*^?%]/

      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, TARGET_RE, "\e[1;33m")
        Highlighter.apply_regex(cols, text, VARIABLE_DEF_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, DIRECTIVE_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, FUNCTION_RE, "\e[35m")
        Highlighter.apply_regex(cols, text, VARIABLE_REF_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, AUTO_VAR_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
