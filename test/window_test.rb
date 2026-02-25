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
end
