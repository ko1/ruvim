require_relative "test_helper"

class HighlighterTest < Minitest::Test
  def test_ruby_highlighter_marks_keyword_and_string
    cols = RuVim::Highlighter.color_columns("ruby", 'def x; "hi"; end')
    refute_empty cols
    assert_equal "\e[36m", cols[0] # "def"
    assert_equal "\e[32m", cols[7] # opening quote
  end

  def test_json_highlighter_marks_key_and_number
    cols = RuVim::Highlighter.color_columns("json", '{"a": 10}')
    assert_equal "\e[36m", cols[1] # key chars
    assert_equal "\e[33m", cols[6] # number start
  end

  def test_jsonl_highlighter_reuses_json_colors
    cols = RuVim::Highlighter.color_columns("jsonl", '{"a": 10}')
    assert_equal "\e[36m", cols[1] # key chars
    assert_equal "\e[33m", cols[6] # number start
  end

  def test_ruby_highlighter_marks_instance_variables_and_constants
    cols = RuVim::Highlighter.color_columns("ruby", "@x = Foo")
    assert_equal "\e[93m", cols[0] # @x
    assert_equal "\e[96m", cols[5] # F
  end

  # --- Markdown ---

  def test_markdown_heading_h1
    cols = RuVim::Highlighter.color_columns("markdown", "# Hello")
    refute_empty cols
    assert_equal "\e[1;33m", cols[0]  # bold yellow for H1
    assert_equal "\e[1;33m", cols[6]  # entire line colored
  end

  def test_markdown_heading_h2
    cols = RuVim::Highlighter.color_columns("markdown", "## Section")
    assert_equal "\e[1;36m", cols[0]  # bold cyan for H2
  end

  def test_markdown_heading_h3_to_h6
    colors = {
      3 => "\e[1;32m",
      4 => "\e[1;35m",
      5 => "\e[1;34m",
      6 => "\e[1;90m"
    }
    colors.each do |level, expected_color|
      line = "#{"#" * level} Title"
      cols = RuVim::Highlighter.color_columns("markdown", line)
      assert_equal expected_color, cols[0], "H#{level} should use correct color"
    end
  end

  def test_markdown_fence_line
    cols = RuVim::Highlighter.color_columns("markdown", "```ruby")
    refute_empty cols
    assert_equal "\e[90m", cols[0]  # dim
  end

  def test_markdown_hr
    cols = RuVim::Highlighter.color_columns("markdown", "---")
    refute_empty cols
    assert_equal "\e[90m", cols[0]  # dim
  end

  def test_markdown_block_quote_marker
    cols = RuVim::Highlighter.color_columns("markdown", "> quoted text")
    assert_equal "\e[36m", cols[0]  # cyan for >
  end

  def test_markdown_inline_bold
    cols = RuVim::Highlighter.color_columns("markdown", "hello **bold** world")
    # ** markers and content should be bold
    assert_equal "\e[1m", cols[6]   # first *
    assert_equal "\e[1m", cols[13]  # last *
  end

  def test_markdown_inline_code
    cols = RuVim::Highlighter.color_columns("markdown", "use `foo()` here")
    assert_equal "\e[33m", cols[4]  # backtick
  end

  def test_markdown_empty_line
    cols = RuVim::Highlighter.color_columns("markdown", "")
    assert_empty cols
  end

  def test_markdown_plain_text
    cols = RuVim::Highlighter.color_columns("markdown", "plain text")
    assert_empty cols
  end

  # --- Scheme ---

  def test_scheme_keyword_define
    cols = RuVim::Highlighter.color_columns("scheme", "(define x 42)")
    assert_equal "\e[36m", cols[1]  # "define" keyword
    assert_equal "\e[36m", cols[6]  # end of "define"
  end

  def test_scheme_keyword_lambda
    cols = RuVim::Highlighter.color_columns("scheme", "(lambda (x) x)")
    assert_equal "\e[36m", cols[1]  # "lambda"
  end

  def test_scheme_string
    cols = RuVim::Highlighter.color_columns("scheme", '(display "hello")')
    assert_equal "\e[32m", cols[9]  # opening quote
    assert_equal "\e[32m", cols[15] # closing quote
  end

  def test_scheme_number
    cols = RuVim::Highlighter.color_columns("scheme", "(+ 1 2.5)")
    assert_equal "\e[33m", cols[3]  # "1"
    assert_equal "\e[33m", cols[5]  # "2"
  end

  def test_scheme_boolean
    cols = RuVim::Highlighter.color_columns("scheme", "(if #t #f)")
    assert_equal "\e[35m", cols[4]  # "#t"
    assert_equal "\e[35m", cols[7]  # "#f"
  end

  def test_scheme_comment
    cols = RuVim::Highlighter.color_columns("scheme", "; this is a comment")
    assert_equal "\e[90m", cols[0]  # ";"
    assert_equal "\e[90m", cols[18] # end of comment
  end

  def test_scheme_char_literal
    cols = RuVim::Highlighter.color_columns("scheme", '#\a #\space')
    assert_equal "\e[32m", cols[0]  # "#\a"
    assert_equal "\e[32m", cols[4]  # "#\space"
  end

  def test_scheme_empty_line
    cols = RuVim::Highlighter.color_columns("scheme", "")
    assert_empty cols
  end

  # --- Diff ---

  def test_diff_add_line_green
    cols = RuVim::Highlighter.color_columns("diff", "+added line")
    refute_empty cols
    assert_equal "\e[32m", cols[0]
    assert_equal "\e[32m", cols[5]
  end

  def test_diff_delete_line_red
    cols = RuVim::Highlighter.color_columns("diff", "-removed line")
    refute_empty cols
    assert_equal "\e[31m", cols[0]
  end

  def test_diff_hunk_header_cyan
    cols = RuVim::Highlighter.color_columns("diff", "@@ -1,3 +1,4 @@ def foo")
    refute_empty cols
    assert_equal "\e[36m", cols[0]
  end

  def test_diff_header_bold
    cols = RuVim::Highlighter.color_columns("diff", "diff --git a/foo.rb b/foo.rb")
    refute_empty cols
    assert_equal "\e[1m", cols[0]
  end

  def test_diff_context_line_no_color
    cols = RuVim::Highlighter.color_columns("diff", " context line")
    assert_empty cols
  end

  def test_diff_meta_line_yellow
    cols = RuVim::Highlighter.color_columns("diff", "index abc..def 100644")
    refute_empty cols
    assert_equal "\e[33m", cols[0]
  end

  # --- C ---

  def test_c_keyword_if
    cols = RuVim::Highlighter.color_columns("c", "if (x > 0) {")
    assert_equal "\e[36m", cols[0]  # "if"
    assert_equal "\e[36m", cols[1]
  end

  def test_c_keyword_return
    cols = RuVim::Highlighter.color_columns("c", "  return 0;")
    assert_equal "\e[36m", cols[2]  # "return"
  end

  def test_c_type_keyword
    cols = RuVim::Highlighter.color_columns("c", "int main(void) {")
    assert_equal "\e[36m", cols[0]  # "int"
    assert_equal "\e[36m", cols[9]  # "void"
  end

  def test_c_string
    cols = RuVim::Highlighter.color_columns("c", 'printf("hello");')
    assert_equal "\e[32m", cols[7]  # opening quote
    assert_equal "\e[32m", cols[13] # closing quote
  end

  def test_c_char_literal
    cols = RuVim::Highlighter.color_columns("c", "char c = 'a';")
    assert_equal "\e[32m", cols[9]  # opening quote
    assert_equal "\e[32m", cols[11] # closing quote
  end

  def test_c_number_decimal
    cols = RuVim::Highlighter.color_columns("c", "int x = 42;")
    assert_equal "\e[33m", cols[8]  # "4"
    assert_equal "\e[33m", cols[9]  # "2"
  end

  def test_c_number_hex
    cols = RuVim::Highlighter.color_columns("c", "int x = 0xFF;")
    assert_equal "\e[33m", cols[8]  # "0"
    assert_equal "\e[33m", cols[11] # "F"
  end

  def test_c_line_comment
    cols = RuVim::Highlighter.color_columns("c", "x = 1; // comment")
    assert_equal "\e[90m", cols[7]  # "//"
    assert_equal "\e[90m", cols[16] # end of comment
  end

  def test_c_block_comment_single_line
    cols = RuVim::Highlighter.color_columns("c", "x = 1; /* comment */")
    assert_equal "\e[90m", cols[7]  # "/*"
    assert_equal "\e[90m", cols[19] # "*/"
  end

  def test_c_preprocessor
    cols = RuVim::Highlighter.color_columns("c", "#include <stdio.h>")
    assert_equal "\e[35m", cols[0]  # "#"
    assert_equal "\e[35m", cols[7]  # "e" of include
  end

  def test_c_define_preprocessor
    cols = RuVim::Highlighter.color_columns("c", "#define MAX 100")
    assert_equal "\e[35m", cols[0]  # "#"
  end

  def test_c_constant_macro
    cols = RuVim::Highlighter.color_columns("c", "if (ptr == NULL) {")
    assert_equal "\e[96m", cols[11] # "N" of NULL
  end

  def test_c_all_caps_identifier
    cols = RuVim::Highlighter.color_columns("c", "x = MAX_SIZE;")
    assert_equal "\e[96m", cols[4]  # "M"
  end

  def test_c_empty_line
    cols = RuVim::Highlighter.color_columns("c", "")
    assert_empty cols
  end

  # --- C++ ---

  def test_cpp_keyword_class
    cols = RuVim::Highlighter.color_columns("cpp", "class Foo {")
    assert_equal "\e[36m", cols[0]  # "class"
    assert_equal "\e[36m", cols[4]
  end

  def test_cpp_keyword_namespace
    cols = RuVim::Highlighter.color_columns("cpp", "namespace std {")
    assert_equal "\e[36m", cols[0]  # "namespace"
  end

  def test_cpp_keyword_template
    cols = RuVim::Highlighter.color_columns("cpp", "template <typename T>")
    assert_equal "\e[36m", cols[0]  # "template"
    assert_equal "\e[36m", cols[10] # "typename"
  end

  def test_cpp_keyword_nullptr
    cols = RuVim::Highlighter.color_columns("cpp", "int* p = nullptr;")
    assert_equal "\e[36m", cols[9]  # "nullptr"
  end

  def test_cpp_keyword_auto
    cols = RuVim::Highlighter.color_columns("cpp", "auto x = 42;")
    assert_equal "\e[36m", cols[0]  # "auto"
  end

  def test_cpp_inherits_c_string
    cols = RuVim::Highlighter.color_columns("cpp", 'std::cout << "hello";')
    assert_equal "\e[32m", cols[13] # opening quote
  end

  def test_cpp_inherits_c_comment
    cols = RuVim::Highlighter.color_columns("cpp", "x = 1; // comment")
    assert_equal "\e[90m", cols[7]  # "//"
  end

  def test_cpp_empty_line
    cols = RuVim::Highlighter.color_columns("cpp", "")
    assert_empty cols
  end
end
