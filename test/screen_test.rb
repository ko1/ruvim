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
end
