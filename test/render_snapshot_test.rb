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

  def build_raw_frame(lines:, winsize:, number: false, rich_format: nil, cursor_y: 0, cursor_x: 0)
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(lines)
    editor.set_option("number", number, scope: :window, window: win, buffer: buf)
    win.cursor_y = cursor_y
    win.cursor_x = cursor_x
    if rich_format
      editor.instance_variable_set(:@rich_state, { format: rich_format })
    end

    term = TerminalStub.new(winsize)
    screen = RuVim::Screen.new(terminal: term)

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    win.ensure_visible(buf, height: text_rows, width: text_cols, tabstop: 2)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    (1..rows).map { |row| frame[:lines][row].to_s }.join("\n")
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
  end
end

class RenderSanitizeTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    def write(_data); end
  end

  def test_normal_buffer_sanitizes_escape_sequences
    # ESC (0x1B) should be replaced with "?" in normal rendering
    lines = ["hello\x1b]52;c;dGVzdA==\x07world"]
    snapshot = build_raw_frame(lines: lines, winsize: [5, 40])
    refute_includes snapshot, "\x1b]52"
    refute_includes snapshot, "\x07"
  end

  def test_rich_view_sanitizes_escape_sequences_in_tsv
    lines = ["col1\tcol2", "val1\t\x1b]52;c;dGVzdA==\x07evil"]
    snapshot = build_raw_frame(lines: lines, winsize: [6, 40], rich_format: :tsv)
    refute_includes snapshot, "\x1b]52"
    refute_includes snapshot, "\x07"
  end

  def test_rich_view_sanitizes_escape_sequences_in_markdown
    lines = ["# heading", "\x1b]52;c;dGVzdA==\x07evil text"]
    snapshot = build_raw_frame(lines: lines, winsize: [6, 40], rich_format: :markdown)
    refute_includes snapshot, "\x1b]52"
    refute_includes snapshot, "\x07"
  end

  private

  def build_raw_frame(lines:, winsize:, number: false, rich_format: nil, cursor_y: 0, cursor_x: 0)
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(lines)
    editor.set_option("number", number, scope: :window, window: win, buffer: buf)
    win.cursor_y = cursor_y
    win.cursor_x = cursor_x
    if rich_format
      editor.instance_variable_set(:@rich_state, { format: rich_format })
    end

    term = TerminalStub.new(winsize)
    screen = RuVim::Screen.new(terminal: term)

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    win.ensure_visible(buf, height: text_rows, width: text_cols, tabstop: 2)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    (1..rows).map { |row| frame[:lines][row].to_s }.join("\n")
  end
end
