# frozen_string_literal: true

require_relative "test_helper"

class LangTest < Minitest::Test
  private

  def color_columns(filetype, line)
    mod = RuVim::Lang::Registry.resolve_module(filetype)
    mod.respond_to?(:color_columns) ? mod.color_columns(line) : {}
  end

  public

  # --- YAML ---

  def test_yaml_key_highlighted
    cols = color_columns("yaml", "name: value")
    assert_equal "\e[36m", cols[0] # "name" as key
  end

  def test_yaml_string_highlighted
    cols = color_columns("yaml", 'key: "hello"')
    assert_equal "\e[32m", cols[5] # opening quote
  end

  def test_yaml_boolean_highlighted
    cols = color_columns("yaml", "enabled: true")
    assert_equal "\e[35m", cols[9] # "true"
  end

  def test_yaml_comment_overrides
    cols = color_columns("yaml", "# comment")
    assert_equal "\e[90m", cols[0]
    assert_equal "\e[90m", cols[8]
  end

  def test_yaml_anchor
    cols = color_columns("yaml", "base: &default")
    assert_equal "\e[93m", cols[6] # "&default"
  end

  def test_yaml_empty
    cols = color_columns("yaml", "")
    assert_empty cols
  end

  # --- Shell ---

  def test_sh_keyword_if
    cols = color_columns("sh", "if [ -f foo ]; then")
    assert_equal "\e[36m", cols[0] # "if"
  end

  def test_sh_variable
    cols = color_columns("sh", 'echo $HOME')
    assert_equal "\e[93m", cols[5] # "$HOME"
  end

  def test_sh_string
    cols = color_columns("sh", 'x="hello"')
    assert_equal "\e[32m", cols[2] # opening quote
  end

  def test_sh_comment
    cols = color_columns("sh", "# comment here")
    assert_equal "\e[90m", cols[0]
  end

  def test_sh_empty
    cols = color_columns("sh", "")
    assert_empty cols
  end

  # --- Python ---

  def test_python_keyword_def
    cols = color_columns("python", "def foo():")
    assert_equal "\e[36m", cols[0] # "def"
  end

  def test_python_decorator
    cols = color_columns("python", "@staticmethod")
    assert_equal "\e[35m", cols[0] # "@"
  end

  def test_python_string
    cols = color_columns("python", 'x = "hello"')
    assert_equal "\e[32m", cols[4] # opening quote
  end

  def test_python_builtin
    cols = color_columns("python", "print(len(x))")
    assert_equal "\e[35m", cols[0] # "print"
  end

  def test_python_comment
    cols = color_columns("python", "x = 1  # comment")
    assert_equal "\e[90m", cols[7]
  end

  def test_python_empty
    cols = color_columns("python", "")
    assert_empty cols
  end

  # --- JavaScript ---

  def test_javascript_keyword_const
    cols = color_columns("javascript", "const x = 42;")
    assert_equal "\e[36m", cols[0] # "const"
  end

  def test_javascript_string
    cols = color_columns("javascript", "let s = 'hello';")
    assert_equal "\e[32m", cols[8] # opening quote
  end

  def test_javascript_template_string
    cols = color_columns("javascript", "let s = `hello`;")
    assert_equal "\e[32m", cols[8] # opening backtick
  end

  def test_javascript_number
    cols = color_columns("javascript", "let x = 42;")
    assert_equal "\e[33m", cols[8]
  end

  def test_javascript_line_comment
    cols = color_columns("javascript", "x = 1; // comment")
    assert_equal "\e[90m", cols[7]
  end

  def test_javascript_empty
    cols = color_columns("javascript", "")
    assert_empty cols
  end

  # --- TypeScript ---

  def test_typescript_keyword_interface
    cols = color_columns("typescript", "interface Foo {}")
    assert_equal "\e[36m", cols[0] # "interface"
  end

  def test_typescript_inherits_js_string
    cols = color_columns("typescript", 'let s = "hello";')
    assert_equal "\e[32m", cols[8]
  end

  def test_typescript_empty
    cols = color_columns("typescript", "")
    assert_empty cols
  end

  # --- HTML ---

  def test_html_tag
    cols = color_columns("html", "<div>hello</div>")
    assert_equal "\e[36m", cols[0] # "<div"
  end

  def test_html_attribute_string
    cols = color_columns("html", '<a href="url">')
    assert_equal "\e[32m", cols[8] # opening quote
  end

  def test_html_comment
    cols = color_columns("html", "<!-- comment -->")
    assert_equal "\e[90m", cols[0]
  end

  def test_html_empty
    cols = color_columns("html", "")
    assert_empty cols
  end

  # --- TOML ---

  def test_toml_table_header
    cols = color_columns("toml", "[package]")
    assert_equal "\e[1;36m", cols[0]
  end

  def test_toml_key
    cols = color_columns("toml", "name = \"test\"")
    assert_equal "\e[36m", cols[0] # "name"
  end

  def test_toml_string
    cols = color_columns("toml", 'name = "test"')
    assert_equal "\e[32m", cols[7] # opening quote
  end

  def test_toml_comment
    cols = color_columns("toml", "# comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_toml_empty
    cols = color_columns("toml", "")
    assert_empty cols
  end

  # --- Go ---

  def test_go_keyword_func
    cols = color_columns("go", "func main() {")
    assert_equal "\e[36m", cols[0] # "func"
  end

  def test_go_type
    cols = color_columns("go", "var x int = 42")
    assert_equal "\e[36m", cols[6] # "int"
  end

  def test_go_string
    cols = color_columns("go", 'fmt.Println("hello")')
    assert_equal "\e[32m", cols[12] # opening quote
  end

  def test_go_line_comment
    cols = color_columns("go", "x := 1 // comment")
    assert_equal "\e[90m", cols[7]
  end

  def test_go_empty
    cols = color_columns("go", "")
    assert_empty cols
  end

  # --- Rust ---

  def test_rust_keyword_fn
    cols = color_columns("rust", "fn main() {")
    assert_equal "\e[36m", cols[0] # "fn"
  end

  def test_rust_keyword_let
    cols = color_columns("rust", "let mut x = 42;")
    assert_equal "\e[36m", cols[0] # "let"
    assert_equal "\e[36m", cols[4] # "mut"
  end

  def test_rust_string
    cols = color_columns("rust", 'println!("hello");')
    assert_equal "\e[32m", cols[9] # opening quote
  end

  def test_rust_lifetime
    cols = color_columns("rust", "fn foo<'a>(x: &'a str)")
    assert_equal "\e[35m", cols[7] # "'a"
  end

  def test_rust_line_comment
    cols = color_columns("rust", "x = 1; // comment")
    assert_equal "\e[90m", cols[7]
  end

  def test_rust_empty
    cols = color_columns("rust", "")
    assert_empty cols
  end

  # --- Makefile ---

  def test_makefile_target
    cols = color_columns("make", "all:")
    assert_equal "\e[1;33m", cols[0]
  end

  def test_makefile_variable_ref
    cols = color_columns("make", "\t$(CC) -o $@ $<")
    assert_equal "\e[93m", cols[1] # "$(CC)"
  end

  def test_makefile_comment
    cols = color_columns("make", "# comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_makefile_empty
    cols = color_columns("make", "")
    assert_empty cols
  end

  # --- Dockerfile ---

  def test_dockerfile_instruction
    cols = color_columns("dockerfile", "FROM ubuntu:22.04")
    assert_equal "\e[36m", cols[0] # "FROM"
  end

  def test_dockerfile_variable
    cols = color_columns("dockerfile", "ENV PATH=$PATH:/app")
    assert_equal "\e[93m", cols[9] # "$PATH"
  end

  def test_dockerfile_comment
    cols = color_columns("dockerfile", "# comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_dockerfile_empty
    cols = color_columns("dockerfile", "")
    assert_empty cols
  end

  # --- SQL ---

  def test_sql_keyword_select
    cols = color_columns("sql", "SELECT * FROM users;")
    assert_equal "\e[36m", cols[0] # "SELECT"
  end

  def test_sql_string
    cols = color_columns("sql", "WHERE name = 'foo'")
    assert_equal "\e[32m", cols[13] # opening quote
  end

  def test_sql_line_comment
    cols = color_columns("sql", "-- comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_sql_empty
    cols = color_columns("sql", "")
    assert_empty cols
  end

  # --- Elixir ---

  def test_elixir_keyword_def
    cols = color_columns("elixir", "def hello do")
    assert_equal "\e[36m", cols[0] # "def"
  end

  def test_elixir_atom
    cols = color_columns("elixir", ":ok")
    assert_equal "\e[96m", cols[0] # ":ok"
  end

  def test_elixir_module_attribute
    cols = color_columns("elixir", "@moduledoc false")
    assert_equal "\e[93m", cols[0] # "@moduledoc"
  end

  def test_elixir_string
    cols = color_columns("elixir", 'IO.puts("hello")')
    assert_equal "\e[32m", cols[8] # opening quote
  end

  def test_elixir_comment
    cols = color_columns("elixir", "# comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_elixir_empty
    cols = color_columns("elixir", "")
    assert_empty cols
  end

  # --- Perl ---

  def test_perl_keyword_my
    cols = color_columns("perl", "my $x = 42;")
    assert_equal "\e[36m", cols[0] # "my"
  end

  def test_perl_scalar_variable
    cols = color_columns("perl", "my $name = 1;")
    assert_equal "\e[93m", cols[3] # "$name"
  end

  def test_perl_array_variable
    cols = color_columns("perl", "my @list = (1,2);")
    assert_equal "\e[35m", cols[3] # "@list"
  end

  def test_perl_hash_variable
    cols = color_columns("perl", 'my %hash = (a => 1);')
    assert_equal "\e[96m", cols[3] # "%hash"
  end

  def test_perl_string
    cols = color_columns("perl", 'print "hello";')
    assert_equal "\e[32m", cols[6] # opening quote
  end

  def test_perl_comment
    cols = color_columns("perl", "# comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_perl_pod_line
    cols = color_columns("perl", "=head1 NAME")
    assert_equal "\e[90m", cols[0]
    assert_equal "\e[90m", cols[10]
  end

  def test_perl_empty
    cols = color_columns("perl", "")
    assert_empty cols
  end

  # --- Lua ---

  def test_lua_keyword_function
    cols = color_columns("lua", "function hello()")
    assert_equal "\e[36m", cols[0] # "function"
  end

  def test_lua_keyword_local
    cols = color_columns("lua", "local x = 42")
    assert_equal "\e[36m", cols[0] # "local"
  end

  def test_lua_string
    cols = color_columns("lua", 'print("hello")')
    assert_equal "\e[32m", cols[6] # opening quote
  end

  def test_lua_builtin
    cols = color_columns("lua", "print(type(x))")
    assert_equal "\e[35m", cols[0] # "print"
  end

  def test_lua_line_comment
    cols = color_columns("lua", "-- comment")
    assert_equal "\e[90m", cols[0]
  end

  def test_lua_number
    cols = color_columns("lua", "local x = 42")
    assert_equal "\e[33m", cols[10] # "4"
  end

  def test_lua_empty
    cols = color_columns("lua", "")
    assert_empty cols
  end

  # --- OCaml ---

  def test_ocaml_keyword_let
    cols = color_columns("ocaml", "let x = 42")
    assert_equal "\e[36m", cols[0] # "let"
  end

  def test_ocaml_keyword_match
    cols = color_columns("ocaml", "match x with")
    assert_equal "\e[36m", cols[0] # "match"
  end

  def test_ocaml_string
    cols = color_columns("ocaml", 'let s = "hello"')
    assert_equal "\e[32m", cols[8] # opening quote
  end

  def test_ocaml_block_comment
    cols = color_columns("ocaml", "(* comment *)")
    assert_equal "\e[90m", cols[0]
    assert_equal "\e[90m", cols[12]
  end

  def test_ocaml_type_variable
    cols = color_columns("ocaml", "type 'a list")
    assert_equal "\e[93m", cols[5] # "'a"
  end

  def test_ocaml_number
    cols = color_columns("ocaml", "let x = 42")
    assert_equal "\e[33m", cols[8] # "4"
  end

  def test_ocaml_empty
    cols = color_columns("ocaml", "")
    assert_empty cols
  end

  # --- Filetype detection ---

  def test_detect_filetype_yaml
    editor = fresh_editor
    assert_equal "yaml", editor.detect_filetype("config.yml")
    assert_equal "yaml", editor.detect_filetype("config.yaml")
  end

  def test_detect_filetype_sh
    editor = fresh_editor
    assert_equal "sh", editor.detect_filetype("script.sh")
    assert_equal "sh", editor.detect_filetype("script.bash")
    assert_equal "sh", editor.detect_filetype("script.zsh")
  end

  def test_detect_filetype_python
    editor = fresh_editor
    assert_equal "python", editor.detect_filetype("app.py")
  end

  def test_detect_filetype_javascript
    editor = fresh_editor
    assert_equal "javascript", editor.detect_filetype("app.js")
    assert_equal "javascript", editor.detect_filetype("app.mjs")
  end

  def test_detect_filetype_typescript
    editor = fresh_editor
    assert_equal "typescript", editor.detect_filetype("app.ts")
    assert_equal "typescriptreact", editor.detect_filetype("app.tsx")
  end

  def test_detect_filetype_html
    editor = fresh_editor
    assert_equal "html", editor.detect_filetype("index.html")
    assert_equal "html", editor.detect_filetype("index.htm")
  end

  def test_detect_filetype_toml
    editor = fresh_editor
    assert_equal "toml", editor.detect_filetype("Cargo.toml")
  end

  def test_detect_filetype_go
    editor = fresh_editor
    assert_equal "go", editor.detect_filetype("main.go")
  end

  def test_detect_filetype_rust
    editor = fresh_editor
    assert_equal "rust", editor.detect_filetype("main.rs")
  end

  def test_detect_filetype_makefile
    editor = fresh_editor
    assert_equal "make", editor.detect_filetype("Makefile")
    assert_equal "make", editor.detect_filetype("GNUmakefile")
  end

  def test_detect_filetype_dockerfile
    editor = fresh_editor
    assert_equal "dockerfile", editor.detect_filetype("Dockerfile")
    assert_equal "dockerfile", editor.detect_filetype("Dockerfile.prod")
  end

  def test_detect_filetype_sql
    editor = fresh_editor
    assert_equal "sql", editor.detect_filetype("schema.sql")
  end

  def test_detect_filetype_elixir
    editor = fresh_editor
    assert_equal "elixir", editor.detect_filetype("app.ex")
    assert_equal "elixir", editor.detect_filetype("app.exs")
  end

  def test_detect_filetype_perl
    editor = fresh_editor
    assert_equal "perl", editor.detect_filetype("script.pl")
    assert_equal "perl", editor.detect_filetype("Module.pm")
  end

  def test_detect_filetype_lua
    editor = fresh_editor
    assert_equal "lua", editor.detect_filetype("init.lua")
  end

  def test_detect_filetype_ocaml
    editor = fresh_editor
    assert_equal "ocaml", editor.detect_filetype("main.ml")
    assert_equal "ocaml", editor.detect_filetype("main.mli")
  end

  # --- Indent support ---

  def test_python_indent_after_colon
    assert RuVim::Lang::Python.indent_trigger?("def foo():")
    assert RuVim::Lang::Python.indent_trigger?("if x > 0:")
  end

  def test_javascript_indent_after_brace
    assert RuVim::Lang::Javascript.indent_trigger?("function foo() {")
  end

  def test_go_indent_after_brace
    assert RuVim::Lang::Go.indent_trigger?("func main() {")
  end

  def test_rust_indent_after_brace
    assert RuVim::Lang::Rust.indent_trigger?("fn main() {")
  end

  def test_elixir_indent_after_do
    assert RuVim::Lang::Elixir.indent_trigger?("def hello do")
  end

  def test_lua_indent_after_function
    assert RuVim::Lang::Lua.indent_trigger?("function hello()")
  end

  def test_sh_indent_after_then
    assert RuVim::Lang::Sh.indent_trigger?("if [ -f foo ]; then")
  end

  def test_yaml_indent_after_key_colon
    assert RuVim::Lang::Yaml.indent_trigger?("services:")
  end

  # --- ERB ---

  def test_erb_html_tag_highlighted
    cols = color_columns("erb", "<div>hello</div>")
    assert_equal "\e[36m", cols[0] # "<div"
  end

  def test_erb_ruby_tag_highlighted
    cols = color_columns("erb", '<%= link_to "home", root_path %>')
    # <%= and %> delimiters should be highlighted
    assert_equal "\e[35m", cols[0] # "<%="
  end

  def test_erb_ruby_comment_tag
    cols = color_columns("erb", "<%# this is a comment %>")
    assert_equal "\e[90m", cols[0]
  end

  def test_erb_mixed_html_and_ruby
    cols = color_columns("erb", '<p><%= "hi" %></p>')
    assert_equal "\e[36m", cols[0] # "<p"
    assert_equal "\e[35m", cols[3] # "<%="
  end

  def test_erb_empty
    cols = color_columns("erb", "")
    assert_empty cols
  end

  def test_detect_filetype_erb
    editor = fresh_editor
    assert_equal "erb", editor.detect_filetype("index.html.erb")
    assert_equal "erb", editor.detect_filetype("show.erb")
  end
end
