require_relative "test_helper"

class AppDotRepeatTest < Minitest::Test
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

  def test_dot_repeats_x
    @buffer.replace_all_lines!(["abcd"])
    @win.cursor_x = 0

    press("x")
    press(".")

    assert_equal "cd", @buffer.line_at(0)
  end

  def test_dot_repeats_dd
    @buffer.replace_all_lines!(["one", "two", "three"])

    press("d", "d")
    press(".")

    assert_equal ["three"], @buffer.lines
  end

  def test_dot_repeats_paste
    @buffer.replace_all_lines!(["one", "two"])
    press("y", "y")
    press("p")
    press(".")

    assert_equal ["one", "one", "one", "two"], @buffer.lines
  end

  def test_dot_repeats_replace_char
    @buffer.replace_all_lines!(["abcd"])
    @win.cursor_x = 0

    press("r", "x")
    press("l")
    press(".")

    assert_equal "xxcd", @buffer.line_at(0)
  end
end
