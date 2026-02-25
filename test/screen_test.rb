require_relative "test_helper"

class ScreenTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    attr_reader :writes

    def write(data)
      @writes ||= []
      @writes << data
    end
  end

  def test_horizontal_render_draws_all_visible_rows
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["# title", "", "foo", "bar 日本語 編集", "baz"])

    term = TerminalStub.new([8, 20])
    screen = RuVim::Screen.new(terminal: term)

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    editor.window_order.each do |win_id|
      w = editor.windows.fetch(win_id)
      b = editor.buffers.fetch(w.buffer_id)
      w.ensure_visible(b, height: text_rows, width: text_cols)
    end
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    assert_includes frame[:lines][1], "#"
    assert frame[:lines].key?(2), "row 2 should be rendered"
    assert_includes frame[:lines][3], "foo"
    assert_includes frame[:lines][4], "bar"
    assert_includes frame[:lines][5], "baz"
  end

  def test_line_number_prefix_supports_relativenumber
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["aa", "bb", "cc", "dd"])
    win.cursor_y = 2
    editor.set_option("relativenumber", true, scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([8, 20])
    screen = RuVim::Screen.new(terminal: term)

    assert_equal " 2 ", screen.send(:line_number_prefix, editor, win, buf, 0, 3)
    assert_equal " 1 ", screen.send(:line_number_prefix, editor, win, buf, 1, 3)
    assert_equal " 0 ", screen.send(:line_number_prefix, editor, win, buf, 2, 3)

    editor.set_option("number", true, scope: :window, window: win, buffer: buf)
    assert_equal " 3 ", screen.send(:line_number_prefix, editor, win, buf, 2, 3) # current line is absolute when both enabled
  end
end
