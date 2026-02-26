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

  def test_signcolumn_yes_reserves_one_column_in_gutter
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    editor.set_option("number", true, scope: :window, window: win, buffer: buf)
    editor.set_option("signcolumn", "yes", scope: :window, window: win, buffer: buf)
    term = TerminalStub.new([8, 20])
    screen = RuVim::Screen.new(terminal: term)

    w = screen.send(:number_column_width, editor, win, buf)
    prefix = screen.send(:line_number_prefix, editor, win, buf, 0, w)

    assert_equal 6, w # sign(1) + default numberwidth(4) + trailing space
    assert_equal "    1 ", prefix
  end

  def test_signcolumn_yes_with_width_reserves_multiple_columns
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    editor.set_option("number", true, scope: :window, window: win, buffer: buf)
    editor.set_option("signcolumn", "yes:2", scope: :window, window: win, buffer: buf)
    term = TerminalStub.new([8, 20])
    screen = RuVim::Screen.new(terminal: term)

    w = screen.send(:number_column_width, editor, win, buf)
    prefix = screen.send(:line_number_prefix, editor, win, buf, 0, w)

    assert_equal 7, w # sign(2) + default numberwidth(4) + trailing space
    assert_equal "     1 ", prefix
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

  def test_render_reuses_wrap_segment_cache_for_same_line
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["x" * 400])
    editor.set_option("wrap", true, scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([8, 20])
    screen = RuVim::Screen.new(terminal: term)

    calls = [0, 0]
    render_index = 0
    mod = RuVim::TextMetrics.singleton_class
    verbose, $VERBOSE = $VERBOSE, nil
    mod.alias_method(:__orig_clip_cells_for_width_for_screen_test, :clip_cells_for_width)
    mod.define_method(:clip_cells_for_width) do |*args, **kwargs|
      calls[render_index] += 1
      __orig_clip_cells_for_width_for_screen_test(*args, **kwargs)
    end

    begin
      render_index = 0
      screen.render(editor)
      render_index = 1
      screen.render(editor)
    ensure
      mod.alias_method(:clip_cells_for_width, :__orig_clip_cells_for_width_for_screen_test)
      mod.remove_method(:__orig_clip_cells_for_width_for_screen_test) rescue nil
      $VERBOSE = verbose
    end

    assert_operator calls[1], :<, calls[0]
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

  def test_termguicolors_uses_truecolor_sequences_for_search_highlight
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["foo"])
    editor.set_last_search(pattern: "foo", direction: :forward)
    editor.set_option("termguicolors", true, scope: :global)

    term = TerminalStub.new([6, 20])
    screen = RuVim::Screen.new(terminal: term)
    out = screen.send(:render_text_line, buf.line_at(0), editor, buffer_row: 0, window: win, buffer: buf, width: 6)

    assert_includes out, "\e[48;2;255;215;0m"
  end

  def test_render_text_line_respects_list_and_listchars_for_tab_trail_and_nbsp
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["\tA \u00A0  "])
    editor.set_option("list", true, scope: :window, window: win, buffer: buf)
    editor.set_option("listchars", "tab:>.,trail:~,nbsp:*", scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([6, 20])
    screen = RuVim::Screen.new(terminal: term)
    out = screen.send(:render_text_line, buf.line_at(0), editor, buffer_row: 0, window: win, buffer: buf, width: 12)
    visible = out.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")

    assert_includes visible, ">."
    assert_includes visible, "*"
    assert_includes visible, "~"
  end

  def test_render_text_line_sanitizes_terminal_escape_controls
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["A\e]52;c;owned\aB"])
    win.cursor_y = 1 # avoid cursor highlight on the tested row

    term = TerminalStub.new([6, 40])
    screen = RuVim::Screen.new(terminal: term)
    out = screen.send(:render_text_line, buf.line_at(0), editor, buffer_row: 0, window: win, buffer: buf, width: 20)

    refute_includes out, "\e]52"
    visible = out.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
    assert_includes visible, "A"
    assert_includes visible, "B"
    assert_includes visible, "?"
  end

  def test_wrap_and_showbreak_render_continuation_rows
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["abcdef ghijkl"])
    editor.set_option("wrap", true, scope: :window, window: win, buffer: buf)
    editor.set_option("showbreak", ">>", scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([6, 8])
    screen = RuVim::Screen.new(terminal: term)
    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    row1 = frame[:lines][1].to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
    row2 = frame[:lines][2].to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
    assert_includes row1, "abcdef"
    assert_includes row2, ">>"
  end

  def test_cursor_screen_position_supports_virtualedit_past_eol
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["abc"])
    editor.set_option("virtualedit", "onemore", scope: :global)
    win.cursor_y = 0
    win.cursor_x = 4

    term = TerminalStub.new([6, 20])
    screen = RuVim::Screen.new(terminal: term)
    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    pos = screen.send(:cursor_screen_position, editor, text_rows, rects)

    # col 1-based; "abc" places cursor at 4, one-past-eol should be 5
    assert_equal [1, 5], pos
  end

  def test_cursor_screen_position_is_clamped_to_text_area_under_wrap
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["x" * 40, "tail"])
    editor.set_option("wrap", true, scope: :window, window: win, buffer: buf)
    win.row_offset = 0
    win.cursor_y = 1
    win.cursor_x = 0

    term = TerminalStub.new([6, 8]) # text_rows = 4 (footer 2 rows)
    screen = RuVim::Screen.new(terminal: term)
    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    row, _col = screen.send(:cursor_screen_position, editor, text_rows, rects)

    assert_operator row, :<=, text_rows
  end

  def test_linebreak_and_breakindent_prefer_space_wrap
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["  foo bar baz"])
    editor.set_option("wrap", true, scope: :window, window: win, buffer: buf)
    editor.set_option("linebreak", true, scope: :window, window: win, buffer: buf)
    editor.set_option("breakindent", true, scope: :window, window: win, buffer: buf)
    editor.set_option("showbreak", ">", scope: :window, window: win, buffer: buf)

    term = TerminalStub.new([6, 10])
    screen = RuVim::Screen.new(terminal: term)
    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    frame = screen.send(:build_frame, editor, rows:, cols:, text_rows:, text_cols:, rects:)

    row2 = frame[:lines][2].to_s.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
    assert_includes row2, ">"
    assert_match(/\s>|\>\s/, row2)
  end

  def test_wrap_keeps_cursor_visible_after_very_long_previous_line
    editor = RuVim::Editor.new
    buf = editor.add_empty_buffer
    win = editor.add_window(buffer_id: buf.id)
    buf.replace_all_lines!(["x" * 200, "tail"])
    editor.set_option("wrap", true, scope: :window, window: win, buffer: buf)
    win.cursor_y = 1
    win.cursor_x = 0

    term = TerminalStub.new([6, 8]) # text_rows=4, content width ~8 (no gutter)
    screen = RuVim::Screen.new(terminal: term)
    screen.render(editor)

    assert_equal 1, win.row_offset

    rows, cols = term.winsize
    text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
    rects = screen.send(:window_rects, editor, text_rows:, text_cols:)
    row, _col = screen.send(:cursor_screen_position, editor, text_rows, rects)
    assert_equal 1, row
  end
end
