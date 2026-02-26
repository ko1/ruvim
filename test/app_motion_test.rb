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

    @editor.current_window_view_height_hint = 5

    @app.send(:handle_normal_key, :pagedown)
    assert_equal 4, @editor.current_window.cursor_y

    @editor.pending_count = 2
    @app.send(:handle_normal_key, :pagedown)
    assert_equal 12, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :pageup)
    assert_equal 8, @editor.current_window.cursor_y
  end

  def test_ctrl_d_u_and_ctrl_f_b_move_by_half_and_full_page
    b = @editor.current_buffer
    b.replace_all_lines!((1..40).map { |i| "line#{i}" })
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    @editor.current_window_view_height_hint = 10

    @app.send(:handle_normal_key, :ctrl_d)
    assert_equal 5, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :ctrl_u)
    assert_equal 0, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :ctrl_f)
    assert_equal 9, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :ctrl_b)
    assert_equal 0, @editor.current_window.cursor_y
  end

  def test_ctrl_e_and_ctrl_y_scroll_window_without_primary_cursor_motion
    b = @editor.current_buffer
    b.replace_all_lines!((1..40).map { |i| "line#{i}" })
    @editor.current_window.cursor_y = 6
    @editor.current_window.cursor_x = 0
    @editor.current_window.row_offset = 5

    @editor.current_window_view_height_hint = 10

    @app.send(:handle_normal_key, :ctrl_e)
    assert_equal 6, @editor.current_window.row_offset
    assert_equal 6, @editor.current_window.cursor_y

    @app.send(:handle_normal_key, :ctrl_y)
    assert_equal 5, @editor.current_window.row_offset
    assert_equal 6, @editor.current_window.cursor_y
  end

  def test_ctrl_d_can_be_overridden_by_normal_keymap
    b = @editor.current_buffer
    b.replace_all_lines!((1..40).map { |i| "line#{i}" })
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    keymaps = @app.instance_variable_get(:@keymaps)
    keymaps.bind(:normal, ["<C-d>"], "cursor.down")

    @app.send(:handle_normal_key, :ctrl_d)
    assert_equal 1, @editor.current_window.cursor_y
  end

  def test_pagedown_can_be_overridden_by_normal_keymap
    b = @editor.current_buffer
    b.replace_all_lines!((1..40).map { |i| "line#{i}" })
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    keymaps = @app.instance_variable_get(:@keymaps)
    keymaps.bind(:normal, ["<PageDown>"], "cursor.down")

    @app.send(:handle_normal_key, :pagedown)
    assert_equal 1, @editor.current_window.cursor_y
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

  def test_virtualedit_all_allows_multiple_columns_past_eol
    b = @editor.current_buffer
    b.replace_all_lines!(["abc"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 3
    @editor.set_option("virtualedit", "all", scope: :global)

    press("l", "l", "l")
    assert_equal 6, @editor.current_window.cursor_x

    press("h", "h")
    assert_equal 4, @editor.current_window.cursor_x
  end

  def test_e_moves_to_next_word_end_when_already_on_word_end
    b = @editor.current_buffer
    b.replace_all_lines!(["one two three"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 2 # end of "one"

    press("e")
    assert_equal 6, @editor.current_window.cursor_x # end of "two"

    press("e")
    assert_equal 12, @editor.current_window.cursor_x # end of "three"
  end
end
