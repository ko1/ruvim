require_relative "test_helper"

class RenderSnapshotTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    def write(_data); end
  end

  FIXTURE = File.expand_path("fixtures/render_basic_snapshot.txt", __dir__)
  FIXTURE_NONUM = File.expand_path("fixtures/render_basic_snapshot_nonumber.txt", __dir__)
  FIXTURE_UNICODE_SCROLL = File.expand_path("fixtures/render_unicode_scrolled_snapshot.txt", __dir__)

  def test_basic_render_frame_matches_snapshot
    snapshot = build_snapshot(
      lines: ["# title", "", "foo", "bar 日本語 編集", "baz"],
      winsize: [8, 24],
      number: true
    )
    expected = File.read(FIXTURE)
    assert_equal expected, snapshot
  end

  def test_basic_render_frame_without_number_matches_snapshot
    snapshot = build_snapshot(
      lines: ["# title", "", "foo", "bar 日本語 編集", "baz"],
      winsize: [8, 24],
      number: false
    )
    expected = File.read(FIXTURE_NONUM)
    assert_equal expected, snapshot
  end

  def test_unicode_scrolled_render_matches_snapshot
    snapshot = build_snapshot(
      lines: ["# title", "", "foo", "bar 日本語 編集", "baz", "qux", "quux"],
      winsize: [7, 20],
      number: true,
      cursor_y: 3,
      cursor_x: 4
    )
    expected = File.read(FIXTURE_UNICODE_SCROLL)
    assert_equal expected, snapshot
  end

  private

  def build_snapshot(lines:, winsize:, number:, cursor_y: 0, cursor_x: 0)
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(lines)
    editor.set_option("number", number, scope: :window, window: win, buffer: buf)
    win.cursor_y = cursor_y
    win.cursor_x = cursor_x

    term = TerminalStub.new(winsize)
    screen = RuVim::Screen.new(terminal: term)

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    win.ensure_visible(buf, height: text_rows, width: text_cols, tabstop: 2)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    (1..rows).map { |row| strip_ansi(frame[:lines][row].to_s) }.join("\n")
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
  end
end
