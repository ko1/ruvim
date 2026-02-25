require_relative "test_helper"

class AppMotionTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @editor.materialize_intro_buffer!
  end

  def press(*keys)
    keys.each { |k| @app.send(:handle_normal_key, k) }
  end

  def test_find_char_and_repeat
    b = @editor.current_buffer
    b.replace_all_lines!(["abcabc"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    press("f", "c")
    assert_equal 2, @editor.current_window.cursor_x

    press(";")
    assert_equal 5, @editor.current_window.cursor_x

    press(",")
    assert_equal 2, @editor.current_window.cursor_x
  end

  def test_till_char_moves_before_match
    b = @editor.current_buffer
    b.replace_all_lines!(["abcabc"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    press("t", "c")

    assert_equal 1, @editor.current_window.cursor_x
  end

  def test_match_bracket_with_percent
    b = @editor.current_buffer
    b.replace_all_lines!(["x(a[b]c)d"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 1 # (

    press("%")
    assert_equal 7, @editor.current_window.cursor_x

    press("%")
    assert_equal 1, @editor.current_window.cursor_x
  end

  def test_pageup_and_pagedown_move_by_visible_page_height
    b = @editor.current_buffer
    b.replace_all_lines!((1..20).map { |i| "line#{i}" })
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    screen = @app.instance_variable_get(:@screen)
    screen.define_singleton_method(:current_window_view_height) { |_editor| 5 }

    @app.send(:handle_normal_key, :pagedown)
    assert_equal 4, @editor.current_window.cursor_y

    @editor.pending_count = 2
    @app.send(:handle_normal_key, :pagedown)
    assert_equal 12, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :pageup)
    assert_equal 8, @editor.current_window.cursor_y
  end

  def test_virtualedit_onemore_allows_right_move_past_eol_once
    b = @editor.current_buffer
    b.replace_all_lines!(["abc"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 3

    press("l")
    assert_equal 3, @editor.current_window.cursor_x

    @editor.set_option("virtualedit", "onemore", scope: :global)
    press("l")
    assert_equal 4, @editor.current_window.cursor_x

    press("l")
    assert_equal 4, @editor.current_window.cursor_x
  end
end
