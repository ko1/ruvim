require_relative "test_helper"

class WindowTest < Minitest::Test
  def test_ensure_visible_uses_screen_width_for_wide_chars
    buffer = RuVim::Buffer.new(id: 1, lines: ["ab日本cdef"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)

    win.cursor_y = 0
    win.cursor_x = 4 # after "本" (screen col 6)
    win.col_offset = 0
    win.ensure_visible(buffer, height: 5, width: 4, tabstop: 2)

    line = buffer.line_at(0)
    cursor_col = RuVim::TextMetrics.screen_col_for_char_index(line, win.cursor_x, tabstop: 2)
    offset_col = RuVim::TextMetrics.screen_col_for_char_index(line, win.col_offset, tabstop: 2)

    assert_operator cursor_col, :>=, offset_col
    assert_operator cursor_col, :<, offset_col + 4
    assert_equal 3, win.col_offset
  end

  def test_ensure_visible_respects_scrolloff_and_sidescrolloff
    buffer = RuVim::Buffer.new(id: 1, lines: ["0123456789", "aaaaa", "bbbbb", "ccccc", "0123456789", "eeeee"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_y = 4
    win.cursor_x = 8

    win.ensure_visible(buffer, height: 3, width: 5, tabstop: 2, scrolloff: 1, sidescrolloff: 1)

    assert_equal 3, win.row_offset
    assert_operator win.col_offset, :>, 0
  end

  def test_move_left
    buffer = RuVim::Buffer.new(id: 1, lines: ["abcde"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_x = 3

    win.move_left(buffer)
    assert_equal 2, win.cursor_x

    win.move_left(buffer, 2)
    assert_equal 0, win.cursor_x

    # Should not go below 0
    win.move_left(buffer)
    assert_equal 0, win.cursor_x
  end

  def test_move_right
    buffer = RuVim::Buffer.new(id: 1, lines: ["abcde"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_x = 0

    win.move_right(buffer)
    assert_equal 1, win.cursor_x

    win.move_right(buffer, 2)
    assert_equal 3, win.cursor_x

    # Should not go beyond line length
    win.move_right(buffer, 10)
    assert_equal 5, win.cursor_x
  end

  def test_move_left_with_multibyte
    buffer = RuVim::Buffer.new(id: 1, lines: ["ab日本c"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_x = 4 # on "c"

    win.move_left(buffer)
    assert_equal 3, win.cursor_x # on "本"

    win.move_left(buffer)
    assert_equal 2, win.cursor_x # on "日"
  end

  def test_move_up
    buffer = RuVim::Buffer.new(id: 1, lines: ["abc", "def", "ghi"])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_y = 2
    win.cursor_x = 1

    win.move_up(buffer)
    assert_equal 1, win.cursor_y
    assert_equal 1, win.cursor_x

    # Should not go below 0
    win.move_up(buffer, 5)
    assert_equal 0, win.cursor_y
  end

  def test_move_down_preserves_preferred_column_across_empty_line
    long = "x" * 80
    buffer = RuVim::Buffer.new(id: 1, lines: [long, "", long])
    win = RuVim::Window.new(id: 1, buffer_id: 1)
    win.cursor_y = 0
    win.cursor_x = 50

    win.move_down(buffer)
    assert_equal [1, 0], [win.cursor_y, win.cursor_x]

    win.move_down(buffer)
    assert_equal [2, 50], [win.cursor_y, win.cursor_x]
  end
end
