require_relative "test_helper"

class RubyIndentTest < Minitest::Test
  def calc(lines, target_row, sw = 2)
    RuVim::Lang::Ruby.calculate_indent(lines, target_row, sw)
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
