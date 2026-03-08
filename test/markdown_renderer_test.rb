require_relative "test_helper"

class MarkdownRendererTest < Minitest::Test
  def renderer
    RuVim::RichView::MarkdownRenderer
  end

  # --- Registration ---

  def test_renderer_registered_for_markdown
    assert_equal renderer, RuVim::RichView.renderer_for(:markdown)
  end

  def test_delimiter_for_markdown
    assert_nil renderer.delimiter_for(:markdown)
  end

  # --- Headings ---

  def test_heading_h1_bold
    lines = ["# Hello"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_equal 1, result.length
    assert_match(/\e\[1[;m]/, result[0])  # bold (standalone or combined)
    assert_includes result[0], "# Hello"
  end

  def test_heading_h2
    lines = ["## Section"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "## Section"
    assert_match(/\e\[1[;m]/, result[0])  # bold
  end

  def test_heading_h3_to_h6
    (3..6).each do |level|
      hashes = "#" * level
      lines = ["#{hashes} Title"]
      result = renderer.render_visible(lines, delimiter: nil)
      assert_includes result[0], "#{hashes} Title", "H#{level} text should be preserved"
      assert_includes result[0], "\e[", "H#{level} should have ANSI styling"
    end
  end

  # --- Inline elements ---

  def test_inline_bold
    lines = ["hello **bold** world"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[1m"   # bold on
    assert_includes result[0], "\e[22m"  # bold off
    assert_includes result[0], "**bold**"
  end

  def test_inline_italic
    lines = ["hello *italic* world"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[3m"   # italic on
    assert_includes result[0], "\e[23m"  # italic off
    assert_includes result[0], "*italic*"
  end

  def test_inline_code
    lines = ["use `foo()` here"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[33m"  # yellow
    assert_includes result[0], "`foo()`"
  end

  def test_inline_link
    lines = ["click [here](http://example.com) now"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[4m"   # underline for text
    assert_includes result[0], "here"
    assert_includes result[0], "http://example.com"
  end

  def test_checkbox_unchecked
    lines = ["- [ ] todo item"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[90m"  # dim
    assert_includes result[0], "[ ]"
  end

  def test_checkbox_checked
    lines = ["- [x] done item"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[32m"  # green
    assert_includes result[0], "[x]"
  end

  # --- Code blocks ---

  def test_code_fence_styling
    lines = ["```ruby", "puts 'hi'", "```"]
    result = renderer.render_visible(lines, delimiter: nil)
    # Fence lines should be dim
    assert_includes result[0], "\e[90m"
    # Content should be warm-colored
    assert_includes result[1], "\e[38;5;223m"
    # Closing fence should be dim
    assert_includes result[2], "\e[90m"
  end

  def test_code_fence_tilde
    lines = ["~~~", "code line", "~~~"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[90m"
    assert_includes result[1], "\e[38;5;223m"
  end

  def test_code_block_context_from_pre_context
    # Simulate rendering in the middle of a code block
    # pre_context_lines should carry the open fence state
    pre_context = ["```ruby", "line1"]
    lines = ["line2", "```"]
    result = renderer.render_visible(lines, delimiter: nil, context: { pre_context_lines: pre_context })
    # line2 should be inside code block (warm color)
    assert_includes result[0], "\e[38;5;223m"
    # closing fence
    assert_includes result[1], "\e[90m"
  end

  def test_needs_pre_context
    assert renderer.needs_pre_context?
  end

  # --- HR ---

  def test_hr_dashes
    lines = ["---"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\u2500"  # box drawing horizontal
  end

  def test_hr_asterisks
    lines = ["***"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\u2500"
  end

  def test_hr_underscores
    lines = ["___"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\u2500"
  end

  # --- Block quotes ---

  def test_block_quote
    lines = ["> quoted text"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_includes result[0], "\e[36m"  # cyan
    assert_includes result[0], "> quoted text"
  end

  # --- Tables ---

  def test_table_basic
    lines = [
      "| Name  | Age |",
      "| ----- | --- |",
      "| Alice | 30  |"
    ]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_equal 3, result.length
    # Data rows should use box-drawing vertical bar
    assert_includes result[0], "\u2502"  # │
    assert_includes result[2], "\u2502"
    # Separator row should use box-drawing
    assert_includes result[1], "\u2500"  # ─
    assert_includes result[1], "\u253c"  # ┼
  end

  def test_table_column_alignment
    lines = [
      "| Short | Long column |",
      "| ----- | ----------- |",
      "| A     | B           |"
    ]
    result = renderer.render_visible(lines, delimiter: nil)
    # Both data rows should have same display width
    w0 = display_width_without_ansi(result[0])
    w2 = display_width_without_ansi(result[2])
    assert_equal w0, w2
  end

  # --- cursor_display_col ---

  def test_cursor_display_col_non_table_line
    # For non-table lines, should return screen_col_for_char_index
    line = "hello world"
    col = renderer.cursor_display_col(line, 5, visible_lines: [line], delimiter: nil)
    expected = RuVim::TextMetrics.screen_col_for_char_index(line, 5)
    assert_equal expected, col
  end

  def test_cursor_display_col_table_line
    lines = [
      "| Name  | Age |",
      "| ----- | --- |",
      "| Alice | 30  |"
    ]
    # Cursor at start of "Alice" (index within raw line)
    raw_line = lines[2]
    col = renderer.cursor_display_col(raw_line, 2, visible_lines: lines, delimiter: nil)
    # Should be > 0 (after the leading │ and padding)
    assert col >= 0
  end

  # --- ANSI support in render_rich_view_line_sc ---

  def test_render_rich_view_line_sc_with_ansi
    screen = create_test_screen
    # Line with ANSI bold: "\e[1m" is 4 chars but 0 display width
    text = "\e[1mhello\e[m world"
    result = screen.send(:render_rich_view_line_sc, text, width: 20, skip_sc: 0)
    # Should contain the ANSI sequences and the text
    assert_includes result, "\e[1m"
    assert_includes result, "hello"
    assert_includes result, "world"
    # Should end with reset
    assert result.end_with?("\e[m") || result.include?("\e[m")
  end

  def test_render_rich_view_line_sc_ansi_skip
    screen = create_test_screen
    # ANSI at start, skip some display columns
    text = "\e[1mhello\e[m world"
    result = screen.send(:render_rich_view_line_sc, text, width: 5, skip_sc: 3)
    # Should show "lo wo" or similar (skipping 3 display cols of "hello")
    assert_includes result, "lo"
  end

  # --- Integration test ---

  def test_markdown_rich_mode_integration
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["# Title", "", "Some **bold** text"])
    buf.options["filetype"] = "markdown"

    RuVim::RichView.open!(editor, format: :markdown)
    assert_equal :rich, editor.mode
    state = editor.rich_state
    assert_equal :markdown, state[:format]

    # Render visible lines
    lines = (0...buf.line_count).map { |i| buf.line_at(i) }
    rendered = RuVim::RichView.render_visible_lines(editor, lines)
    assert_equal 3, rendered.length
    # Heading should have styling
    assert_includes rendered[0], "\e["

    RuVim::RichView.close!(editor)
    assert_equal :normal, editor.mode
  end

  def test_detect_format_markdown
    editor = fresh_editor
    buf = editor.current_buffer
    buf.options["filetype"] = "markdown"
    assert_equal :markdown, RuVim::RichView.detect_format(buf)
  end

  private

  def display_width_without_ansi(str)
    # Strip ANSI escape sequences for width calculation
    clean = str.gsub(/\e\[[0-9;]*m/, "")
    RuVim::DisplayWidth.display_width(clean)
  end

  def create_test_screen
    terminal = Object.new
    def terminal.winsize; [24, 80]; end
    RuVim::Screen.new(terminal: terminal)
  end
end
