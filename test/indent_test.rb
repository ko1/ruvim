require_relative "test_helper"

class JsonIndentTest < Minitest::Test
  def calc(lines, target_row, sw = 2)
    RuVim::Lang::Json.new.calculate_indent(lines, target_row, sw)
  end

  def test_first_line_is_zero
    assert_equal 0, calc(["{"], 0)
  end

  def test_after_open_brace
    lines = ["{", '  "key": "value"']
    assert_equal 2, calc(lines, 1)
  end

  def test_close_brace
    lines = ["{", '  "key": "value"', "}"]
    assert_equal 0, calc(lines, 2)
  end

  def test_after_open_bracket
    lines = ["[", "  1"]
    assert_equal 2, calc(lines, 1)
  end

  def test_close_bracket
    lines = ["[", "  1,", "  2", "]"]
    assert_equal 0, calc(lines, 3)
  end

  def test_nested_objects
    lines = [
      "{",
      '  "a": {',
      '    "b": 1',
      "  }",
      "}"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 4, calc(lines, 2)
    assert_equal 2, calc(lines, 3)
    assert_equal 0, calc(lines, 4)
  end

  def test_array_in_object
    lines = [
      "{",
      '  "items": [',
      "    1,",
      "    2",
      "  ]",
      "}"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 4, calc(lines, 2)
    assert_equal 4, calc(lines, 3)
    assert_equal 2, calc(lines, 4)
    assert_equal 0, calc(lines, 5)
  end

  def test_shiftwidth_4
    lines = ["{", '    "key": 1', "}"]
    assert_equal 4, calc(lines, 1, 4)
    assert_equal 0, calc(lines, 2, 4)
  end

  def test_indent_trigger_open_brace
    assert RuVim::Lang::Json.new.indent_trigger?("{")
    assert RuVim::Lang::Json.new.indent_trigger?('  "key": {')
    assert RuVim::Lang::Json.new.indent_trigger?('  "key": [')
  end

  def test_indent_trigger_no_trigger
    refute RuVim::Lang::Json.new.indent_trigger?('  "key": "value"')
    refute RuVim::Lang::Json.new.indent_trigger?("}")
  end

  def test_dedent_trigger_close_brace
    assert_kind_of Regexp, RuVim::Lang::Json.new.dedent_trigger("}")
    assert_kind_of Regexp, RuVim::Lang::Json.new.dedent_trigger("]")
  end

  def test_dedent_trigger_no_trigger
    assert_nil RuVim::Lang::Json.new.dedent_trigger("a")
  end
end

class RubyIndentTest < Minitest::Test
  def calc(lines, target_row, sw = 2)
    RuVim::Lang::Ruby.new.calculate_indent(lines, target_row, sw)
  end

  def test_first_line_is_zero
    assert_equal 0, calc(["hello"], 0)
  end

  def test_after_def
    lines = ["def foo", "  bar"]
    assert_equal 2, calc(lines, 1)
  end

  def test_end_returns_to_zero
    lines = ["def foo", "  bar", "end"]
    assert_equal 0, calc(lines, 2)
  end

  def test_class_def_end_nesting
    lines = [
      "class Foo",
      "  def bar",
      "    baz",
      "  end",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # def bar
    assert_equal 4, calc(lines, 2)  # baz
    assert_equal 2, calc(lines, 3)  # end (inner)
    assert_equal 0, calc(lines, 4)  # end (outer)
  end

  def test_if_else_end
    lines = [
      "if cond",
      "  a",
      "else",
      "  b",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # a
    assert_equal 0, calc(lines, 2)  # else
    assert_equal 2, calc(lines, 3)  # b
    assert_equal 0, calc(lines, 4)  # end
  end

  def test_if_elsif_else_end
    lines = [
      "if a",
      "  x",
      "elsif b",
      "  y",
      "else",
      "  z",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # x
    assert_equal 0, calc(lines, 2)  # elsif
    assert_equal 2, calc(lines, 3)  # y
    assert_equal 0, calc(lines, 4)  # else
    assert_equal 2, calc(lines, 5)  # z
    assert_equal 0, calc(lines, 6)  # end
  end

  def test_modifier_if_does_not_increase_indent
    lines = [
      "def foo",
      "  return if true",
      "  bar",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # return if true
    assert_equal 2, calc(lines, 2)  # bar
    assert_equal 0, calc(lines, 3)  # end
  end

  def test_do_end_block
    lines = [
      "items.each do |x|",
      "  puts x",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # puts x
    assert_equal 0, calc(lines, 2)  # end
  end

  def test_brace_block
    lines = [
      "items.map {",
      "  |x| x + 1",
      "}"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 0, calc(lines, 2)
  end

  def test_case_when
    lines = [
      "case x",
      "when 1",
      "  a",
      "when 2",
      "  b",
      "end"
    ]
    assert_equal 0, calc(lines, 1)  # when 1
    assert_equal 2, calc(lines, 2)  # a
    assert_equal 0, calc(lines, 3)  # when 2
    assert_equal 2, calc(lines, 4)  # b
    assert_equal 0, calc(lines, 5)  # end
  end

  def test_rescue_ensure
    lines = [
      "begin",
      "  risky",
      "rescue => e",
      "  handle",
      "ensure",
      "  cleanup",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # risky
    assert_equal 0, calc(lines, 2)  # rescue
    assert_equal 2, calc(lines, 3)  # handle
    assert_equal 0, calc(lines, 4)  # ensure
    assert_equal 2, calc(lines, 5)  # cleanup
    assert_equal 0, calc(lines, 6)  # end
  end

  def test_unless_until_while_for
    %w[unless until while for].each do |kw|
      lines = ["#{kw} cond", "  body", "end"]
      assert_equal 2, calc(lines, 1), "body after #{kw}"
      assert_equal 0, calc(lines, 2), "end after #{kw}"
    end
  end

  def test_module_nesting
    lines = [
      "module A",
      "  module B",
      "    def foo",
      "      bar",
      "    end",
      "  end",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # module B
    assert_equal 4, calc(lines, 2)  # def foo
    assert_equal 6, calc(lines, 3)  # bar
    assert_equal 4, calc(lines, 4)  # end (inner)
    assert_equal 2, calc(lines, 5)  # end (mid)
    assert_equal 0, calc(lines, 6)  # end (outer)
  end

  def test_comment_lines_are_skipped
    lines = [
      "def foo",
      "  # comment",
      "  bar",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # comment
    assert_equal 2, calc(lines, 2)  # bar
    assert_equal 0, calc(lines, 3)  # end
  end

  def test_shiftwidth_4
    lines = ["def foo", "    bar", "end"]
    assert_equal 4, calc(lines, 1, 4)
    assert_equal 0, calc(lines, 2, 4)
  end

  def test_paren_bracket_nesting
    lines = [
      "x = [",
      "  1,",
      "  2",
      "]"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 2, calc(lines, 2)
    assert_equal 0, calc(lines, 3)
  end

  def test_empty_lines_preserve_depth
    lines = [
      "def foo",
      "",
      "  bar",
      "end"
    ]
    assert_equal 2, calc(lines, 1)  # empty line inside def
    assert_equal 2, calc(lines, 2)  # bar
    assert_equal 0, calc(lines, 3)  # end
  end
end

class CIndentTest < Minitest::Test
  def calc(lines, target_row, sw = 2)
    RuVim::Lang::C.new.calculate_indent(lines, target_row, sw)
  end

  def test_first_line_is_zero
    assert_equal 0, calc(["int main() {"], 0)
  end

  def test_after_open_brace
    lines = ["int main() {", "  return 0;"]
    assert_equal 2, calc(lines, 1)
  end

  def test_close_brace
    lines = ["int main() {", "  return 0;", "}"]
    assert_equal 0, calc(lines, 2)
  end

  def test_nested_braces
    lines = [
      "void foo() {",
      "  if (x) {",
      "    bar();",
      "  }",
      "}"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 4, calc(lines, 2)
    assert_equal 2, calc(lines, 3)
    assert_equal 0, calc(lines, 4)
  end

  def test_switch_case
    lines = [
      "switch (x) {",
      "case 1:",
      "  foo();",
      "  break;",
      "case 2:",
      "  bar();",
      "  break;",
      "default:",
      "  baz();",
      "}"
    ]
    assert_equal 0, calc(lines, 1)  # case 1:
    assert_equal 2, calc(lines, 2)  # foo()
    assert_equal 2, calc(lines, 3)  # break
    assert_equal 0, calc(lines, 4)  # case 2:
    assert_equal 2, calc(lines, 5)  # bar()
    assert_equal 0, calc(lines, 7)  # default:
    assert_equal 2, calc(lines, 8)  # baz()
    assert_equal 0, calc(lines, 9)  # }
  end

  def test_shiftwidth_4
    lines = ["void foo() {", "    bar();", "}"]
    assert_equal 4, calc(lines, 1, 4)
    assert_equal 0, calc(lines, 2, 4)
  end

  def test_indent_trigger_open_brace
    assert RuVim::Lang::C.new.indent_trigger?("int main() {")
    assert RuVim::Lang::C.new.indent_trigger?("if (x) {")
  end

  def test_indent_trigger_no_trigger
    refute RuVim::Lang::C.new.indent_trigger?("return 0;")
    refute RuVim::Lang::C.new.indent_trigger?("}")
  end

  def test_dedent_trigger_close_brace
    assert_kind_of Regexp, RuVim::Lang::C.new.dedent_trigger("}")
  end

  def test_dedent_trigger_no_trigger
    assert_nil RuVim::Lang::C.new.dedent_trigger("a")
  end
end

class CppIndentTest < Minitest::Test
  def calc(lines, target_row, sw = 2)
    RuVim::Lang::Cpp.new.calculate_indent(lines, target_row, sw)
  end

  def test_class_body
    lines = [
      "class Foo {",
      "  int x;",
      "};"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 0, calc(lines, 2)
  end

  def test_namespace_body
    lines = [
      "namespace ns {",
      "  class Bar {",
      "    void f();",
      "  };",
      "}"
    ]
    assert_equal 2, calc(lines, 1)
    assert_equal 4, calc(lines, 2)
    assert_equal 2, calc(lines, 3)
    assert_equal 0, calc(lines, 4)
  end

  def test_access_specifier_dedent
    lines = [
      "class Foo {",
      "public:",
      "  int x;",
      "private:",
      "  int y;",
      "};"
    ]
    assert_equal 0, calc(lines, 1)  # public:
    assert_equal 2, calc(lines, 2)  # int x
    assert_equal 0, calc(lines, 3)  # private:
    assert_equal 2, calc(lines, 4)  # int y
    assert_equal 0, calc(lines, 5)  # };
  end

  def test_indent_trigger
    assert RuVim::Lang::Cpp.new.indent_trigger?("class Foo {")
    assert RuVim::Lang::Cpp.new.indent_trigger?("namespace ns {")
  end

  def test_dedent_trigger
    assert_kind_of Regexp, RuVim::Lang::Cpp.new.dedent_trigger("}")
    assert_nil RuVim::Lang::Cpp.new.dedent_trigger("x")
  end
end
