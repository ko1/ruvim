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

  def test_render_shows_error_message_on_command_line_row_with_highlight
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    editor.add_window(buffer_id: buf.id)
    term = TerminalStub.new([6, 20])
    screen = RuVim::Screen.new(terminal: term)

    editor.echo_error("boom")
    screen.render(editor)
    out = term.writes.last
    assert_includes out, "\e[97;41m"
    assert_includes out, "boom"
  end

  def test_render_reuses_syntax_highlight_cache_for_same_line
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(['def x; "hi"; end'])
    editor.set_option("filetype", "ruby", scope: :buffer, buffer: buf, window: win)

    term = TerminalStub.new([6, 40])
    screen = RuVim::Screen.new(terminal: term)

    calls = 0
    mod = RuVim::Highlighter.singleton_class
    verbose, $VERBOSE = $VERBOSE, nil
    mod.alias_method(:__orig_color_columns_for_screen_test, :color_columns)
    mod.define_method(:color_columns) do |*args, **kwargs|
      calls += 1
      __orig_color_columns_for_screen_test(*args, **kwargs)
    end

    begin
      screen.render(editor)
      screen.render(editor)
    ensure
      mod.alias_method(:color_columns, :__orig_color_columns_for_screen_test)
      mod.remove_method(:__orig_color_columns_for_screen_test) rescue nil
      $VERBOSE = verbose
    end

    assert_equal 1, calls
  end

  def test_render_text_line_with_cursor_search_and_syntax_highlights_fits_width
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(['def x; "日本語"; end'])
    editor.set_option("filetype", "ruby", scope: :buffer, buffer: buf, window: win)
    editor.set_last_search(pattern: "日本", direction: :forward)
    win.cursor_y = 0
    win.cursor_x = 8 # around string body

    term = TerminalStub.new([6, 18])
    screen = RuVim::Screen.new(terminal: term)
    line = buf.line_at(0)

    out = screen.send(:render_text_line, line, editor, buffer_row: 0, window: win, buffer: buf, width: 10)
    visible = out.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")

    assert_equal 10, RuVim::DisplayWidth.display_width(visible, tabstop: 2)
    refute_includes out, "\n"
  end
end
