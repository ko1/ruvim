# frozen_string_literal: true

module RuVim
  module Highlighter
    KEYWORD_COLOR = "\e[36m"
    STRING_COLOR = "\e[32m"
    NUMBER_COLOR = "\e[33m"
    COMMENT_COLOR = "\e[90m"
    VARIABLE_COLOR = "\e[93m"
    CONSTANT_COLOR = "\e[96m"

    module_function

    def color_columns(filetype, line)
      ft = filetype.to_s
      return {} if line.empty?

      case ft
      when "ruby"
        Lang::Ruby.color_columns(line)
      when "json", "jsonl"
        Lang::Json.color_columns(line)
      when "markdown"
        Lang::Markdown.color_columns(line)
      when "scheme"
        Lang::Scheme.color_columns(line)
      when "diff"
        Lang::Diff.color_columns(line)
      when "c"
        Lang::C.color_columns(line)
      when "cpp"
        Lang::Cpp.color_columns(line)
      when "yaml"
        Lang::Yaml.color_columns(line)
      when "sh"
        Lang::Sh.color_columns(line)
      when "python"
        Lang::Python.color_columns(line)
      when "javascript", "javascriptreact"
        Lang::Javascript.color_columns(line)
      when "typescript", "typescriptreact"
        Lang::Typescript.color_columns(line)
      when "html"
        Lang::Html.color_columns(line)
      when "toml"
        Lang::Toml.color_columns(line)
      when "go"
        Lang::Go.color_columns(line)
      when "rust"
        Lang::Rust.color_columns(line)
      when "make"
        Lang::Makefile.color_columns(line)
      when "dockerfile"
        Lang::Dockerfile.color_columns(line)
      when "sql"
        Lang::Sql.color_columns(line)
      when "elixir"
        Lang::Elixir.color_columns(line)
      when "perl"
        Lang::Perl.color_columns(line)
      when "lua"
        Lang::Lua.color_columns(line)
      when "ocaml"
        Lang::Ocaml.color_columns(line)
      else
        {}
      end
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

    module_function :apply_regex
  end
end
