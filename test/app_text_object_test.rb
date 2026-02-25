require_relative "test_helper"

class AppTextObjectTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @editor.materialize_intro_buffer!
    @buffer = @editor.current_buffer
    @win = @editor.current_window
  end

  def press(*keys)
    keys.each { |k| @app.send(:handle_normal_key, k) }
  end

  def test_delete_inside_square_brackets
    @buffer.replace_all_lines!(["x[abc]y"])
    @win.cursor_x = 2

    press("d", "i", "]")

    assert_equal "x[]y", @buffer.line_at(0)
  end

  def test_delete_inside_backticks
    @buffer.replace_all_lines!(["a`bc`d"])
    @win.cursor_x = 2

    press("d", "i", "`")

    assert_equal "a``d", @buffer.line_at(0)
  end

  def test_yank_inner_paragraph
    @buffer.replace_all_lines!(["foo", "bar", "", "baz"])
    @win.cursor_y = 1
    @win.cursor_x = 1

    press("y", "i", "p")

    assert_equal({ text: "foo\nbar", type: :charwise }, @editor.get_register("\""))
    assert_equal({ text: "foo\nbar", type: :charwise }, @editor.get_register("0"))
  end

  def test_delete_around_paragraph_includes_separator_blank_line
    @buffer.replace_all_lines!(["foo", "bar", "", "baz"])
    @win.cursor_y = 0
    @win.cursor_x = 0

    press("d", "a", "p")

    assert_equal ["baz"], @buffer.lines
  end
end
