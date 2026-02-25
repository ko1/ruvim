require_relative "test_helper"

class RenderSnapshotTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    def write(_data); end
  end

  FIXTURE = File.expand_path("fixtures/render_basic_snapshot.txt", __dir__)

  def test_basic_render_frame_matches_snapshot
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["# title", "", "foo", "bar 日本語 編集", "baz"])
    editor.set_option("number", true, scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([8, 24])
    screen = RuVim::Screen.new(terminal: term)

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    win.ensure_visible(buf, height: text_rows, width: text_cols, tabstop: 2)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    snapshot = (1..rows).map { |row| strip_ansi(frame[:lines][row].to_s) }.join("\n")
    expected = File.read(FIXTURE)
    assert_equal expected, snapshot
  end

  private

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
  end
end
