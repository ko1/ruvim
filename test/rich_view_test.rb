require_relative "test_helper"

class RichViewTest < Minitest::Test
  # --- Framework tests ---

  def test_register_and_renderer_for
    assert RuVim::RichView.renderer_for("tsv")
    assert RuVim::RichView.renderer_for("csv")
    assert_nil RuVim::RichView.renderer_for("unknown")
  end

  def test_registered_filetypes
    fts = RuVim::RichView.registered_filetypes
    assert_includes fts, "tsv"
    assert_includes fts, "csv"
  end

  def test_detect_format_from_filetype
    editor = fresh_editor
    buf = editor.current_buffer
    buf.options["filetype"] = "csv"
    assert_equal "csv", RuVim::RichView.detect_format(buf)
  end

  def test_detect_format_auto_tsv
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb\tc", "d\te\tf"])
    assert_equal "tsv", RuVim::RichView.detect_format(buf)
  end

  def test_detect_format_auto_csv
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a,b,c", "d,e,f"])
    assert_equal "csv", RuVim::RichView.detect_format(buf)
  end

  def test_detect_format_returns_nil_for_plain_text
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["hello world", "foo bar"])
    assert_nil RuVim::RichView.detect_format(buf)
  end

  def test_open_raises_when_format_unknown
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["hello world"])
    assert_raises(RuVim::CommandError) { RuVim::RichView.open!(editor) }
  end

  # --- Mode transition tests ---

  def test_active_returns_false_for_normal_mode
    editor = fresh_editor
    refute RuVim::RichView.active?(editor)
  end

  def test_open_enters_rich_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb", "c\td"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    assert_equal :rich, editor.mode
    assert RuVim::RichView.active?(editor)
  end

  def test_open_stays_on_same_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb", "c\td"])
    buf.options["filetype"] = "tsv"
    original_id = buf.id

    RuVim::RichView.open!(editor, format: "tsv")
    assert_equal original_id, editor.current_buffer.id
  end

  def test_close_returns_to_normal_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["x\ty"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    assert_equal :rich, editor.mode

    RuVim::RichView.close!(editor)
    assert_equal :normal, editor.mode
    refute RuVim::RichView.active?(editor)
  end

  def test_close_keeps_same_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["x\ty"])
    buf.options["filetype"] = "tsv"
    original_id = buf.id

    RuVim::RichView.open!(editor, format: "tsv")
    RuVim::RichView.close!(editor)
    assert_equal original_id, editor.current_buffer.id
  end

  def test_toggle_opens_and_closes
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.toggle!(editor)
    assert RuVim::RichView.active?(editor)

    RuVim::RichView.toggle!(editor)
    refute RuVim::RichView.active?(editor)
  end

  def test_rich_state_stores_format_and_delimiter
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    state = editor.rich_state
    assert_equal "tsv", state[:format]
    assert_equal "\t", state[:delimiter]
  end

  def test_rich_state_csv
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a,b"])
    buf.options["filetype"] = "csv"

    RuVim::RichView.open!(editor, format: "csv")
    state = editor.rich_state
    assert_equal "csv", state[:format]
    assert_equal ",", state[:delimiter]
  end

  def test_rich_state_nil_after_close
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    RuVim::RichView.close!(editor)
    assert_nil editor.rich_state
  end

  def test_active_during_command_line_from_rich_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    editor.enter_command_line_mode(":")
    assert_equal :command_line, editor.mode
    assert RuVim::RichView.active?(editor)
  end

  def test_cancel_command_line_returns_to_rich_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    assert_equal :rich, editor.mode

    editor.enter_command_line_mode(":")
    assert_equal :command_line, editor.mode
    assert editor.rich_state

    editor.cancel_command_line
    assert_equal :rich, editor.mode
    assert editor.rich_state
  end

  def test_leave_command_line_returns_to_rich_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    editor.enter_command_line_mode(":")
    editor.leave_command_line
    assert_equal :rich, editor.mode
    assert editor.rich_state
  end

  def test_leave_command_line_returns_to_normal_without_rich_state
    editor = fresh_editor
    editor.enter_command_line_mode(":")
    editor.leave_command_line
    assert_equal :normal, editor.mode
    assert_nil editor.rich_state
  end

  def test_enter_normal_mode_clears_rich_state
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    editor.enter_normal_mode
    assert_nil editor.rich_state
    assert_equal :normal, editor.mode
  end

  def test_render_visible_lines_integration
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tbb", "ccc\td"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    lines = [buf.line_at(0), buf.line_at(1)]
    rendered = RuVim::RichView.render_visible_lines(editor, lines)
    assert_equal 2, rendered.length
    assert_includes rendered[0], " | "
  end

  def test_buffer_count_unchanged_after_open
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"
    count_before = editor.buffers.length

    RuVim::RichView.open!(editor, format: "tsv")
    assert_equal count_before, editor.buffers.length
  end

  # --- TableRenderer tests ---

  def test_basic_alignment
    lines = ["a\tbb\tccc", "dddd\te\tf"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    assert_equal 2, result.length
    # Both lines should have same total display width
    w0 = RuVim::DisplayWidth.display_width(result[0])
    w1 = RuVim::DisplayWidth.display_width(result[1])
    assert_equal w0, w1
    # Check separator presence
    assert_includes result[0], " | "
  end

  def test_uneven_column_count
    lines = ["a\tb", "c\td\te"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    assert_equal 2, result.length
    # First row should have 3 columns padded (missing column filled)
    parts0 = result[0].split(" | ")
    parts1 = result[1].split(" | ")
    assert_equal 3, parts0.length
    assert_equal 3, parts1.length
  end

  def test_empty_cells
    lines = ["a\t\tc", "\tb\t"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    assert_equal 2, result.length
    assert_includes result[0], " | "
  end

  def test_single_column_passthrough
    lines = ["abc", "def", "ghi"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    assert_equal lines, result
  end

  def test_cjk_characters_alignment
    lines = ["名前\t年齢", "太郎\t25", "Alice\t30"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    assert_equal 3, result.length
    # All rows should have the same display width
    widths = result.map { |r| RuVim::DisplayWidth.display_width(r) }
    assert_equal 1, widths.uniq.length, "All rows should have same display width: #{widths.inspect}"
  end

  def test_csv_basic
    lines = ["a,b,c", "dd,e,ff"]
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: ",")
    assert_equal 2, result.length
    assert_includes result[0], " | "
  end

  def test_csv_quoted_fields
    lines = ['"hello, world",b,c', 'a,"say ""hi""",d']
    result = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: ",")
    assert_equal 2, result.length
    # First row first field should be unquoted
    first_field = result[0].split(" | ").first.strip
    assert_equal "hello, world", first_field
  end

  def test_csv_quoted_field_with_escaped_quotes
    fields = RuVim::RichView::TableRenderer.parse_csv_fields('"say ""hi""",b')
    assert_equal ['say "hi"', "b"], fields
  end

  def test_empty_lines
    result = RuVim::RichView::TableRenderer.render_visible([], delimiter: "\t")
    assert_equal [], result
  end

  # --- TableRenderer helper method tests ---

  def test_compute_col_widths_basic
    lines = ["a\tbb\tccc", "dddd\te\tf"]
    widths = RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
    assert_equal [4, 2, 3], widths
  end

  def test_compute_col_widths_single_column
    lines = ["abc", "def"]
    assert_nil RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
  end

  def test_compute_col_widths_empty
    assert_nil RuVim::RichView::TableRenderer.compute_col_widths([], delimiter: "\t")
  end

  def test_compute_col_widths_cjk
    lines = ["名前\t年齢", "Alice\t30"]
    widths = RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
    # 名前 = 4 display cols, Alice = 5 → max = 5
    # 年齢 = 4 display cols, 30 = 2 → max = 4
    assert_equal [5, 4], widths
  end

  def test_format_line_basic
    col_widths = [4, 2, 3]
    result = RuVim::RichView::TableRenderer.format_line("a\tbb\tccc", delimiter: "\t", col_widths: col_widths)
    assert_equal "a    | bb | ccc", result
  end

  def test_format_line_consistency_with_render_visible
    lines = ["a\tbb\tccc", "dddd\te\tf"]
    rendered = RuVim::RichView::TableRenderer.render_visible(lines, delimiter: "\t")
    col_widths = RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
    lines.each_with_index do |line, i|
      formatted = RuVim::RichView::TableRenderer.format_line(line, delimiter: "\t", col_widths: col_widths)
      assert_equal rendered[i], formatted, "format_line should match render_visible for line #{i}"
    end
  end

  def test_raw_to_formatted_char_index_first_field
    # Raw: "Hello\tWorld\tFoo"
    col_widths = [10, 10, 5]
    r = RuVim::RichView::TableRenderer
    # 'H' at raw 0 → formatted 0
    assert_equal 0, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 0, delimiter: "\t", col_widths: col_widths)
    # 'o' at raw 4 → formatted 4
    assert_equal 4, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 4, delimiter: "\t", col_widths: col_widths)
    # End of first field at raw 5 → formatted 5 (just past 'o', still in padded area)
    assert_equal 5, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 5, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_char_index_second_field
    col_widths = [10, 10, 5]
    r = RuVim::RichView::TableRenderer
    # 'W' at raw 6 → formatted 10 (col_widths[0]) + 3 (separator) = 13
    assert_equal 13, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 6, delimiter: "\t", col_widths: col_widths)
    # 'd' at raw 10 → formatted 13 + 4 = 17
    assert_equal 17, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 10, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_char_index_third_field
    col_widths = [10, 10, 5]
    r = RuVim::RichView::TableRenderer
    # 'F' at raw 12 → formatted 10 + 3 + 10 + 3 = 26
    assert_equal 26, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 12, delimiter: "\t", col_widths: col_widths)
    # Last 'o' at raw 14 → formatted 26 + 2 = 28
    assert_equal 28, r.raw_to_formatted_char_index("Hello\tWorld\tFoo", 14, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_alignment_across_rows
    # When different rows map col_offset to different fields, the formatted
    # positions should still be aligned (same column structure).
    lines = ["Short\tField\tEnd", "LongerField\tF\tEnd"]
    col_widths = RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
    r = RuVim::RichView::TableRenderer

    # Format both lines and verify separator positions match
    f0 = r.format_line(lines[0], delimiter: "\t", col_widths: col_widths)
    f1 = r.format_line(lines[1], delimiter: "\t", col_widths: col_widths)
    assert_equal RuVim::DisplayWidth.display_width(f0), RuVim::DisplayWidth.display_width(f1)

    # Map cursor at "End" field start for both lines — should give same formatted position
    # Line 0: "Short\tField\tEnd" → raw 12 is 'E' in End
    # Line 1: "LongerField\tF\tEnd" → raw 14 is 'E' in End
    fi0 = r.raw_to_formatted_char_index(lines[0], 12, delimiter: "\t", col_widths: col_widths)
    fi1 = r.raw_to_formatted_char_index(lines[1], 14, delimiter: "\t", col_widths: col_widths)
    assert_equal fi0, fi1, "Same column start should map to same formatted position"
  end

  def test_raw_to_formatted_char_index_cjk
    # CJK fields: "太郎" is 2 chars but 4 display cols
    col_widths = [5, 4]
    r = RuVim::RichView::TableRenderer
    # "太郎\t30" → formatted: "太郎 " (2+1 pad) + " | " (3) + "30  " (2+2 pad)
    # Character counts: field "太郎"(2) + pad(1) + separator(3) = 6
    # So "3" at raw 3 → formatted 6
    assert_equal 6, r.raw_to_formatted_char_index("太郎\t30", 3, delimiter: "\t", col_widths: col_widths)
    # "0" at raw 4 → formatted 7
    assert_equal 7, r.raw_to_formatted_char_index("太郎\t30", 4, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_display_col_basic
    col_widths = [10, 10, 5]
    r = RuVim::RichView::TableRenderer
    # 'H' at raw 0 → display col 0
    assert_equal 0, r.raw_to_formatted_display_col("Hello\tWorld\tFoo", 0, delimiter: "\t", col_widths: col_widths)
    # 'o' at raw 4 → display col 4
    assert_equal 4, r.raw_to_formatted_display_col("Hello\tWorld\tFoo", 4, delimiter: "\t", col_widths: col_widths)
    # 'W' at raw 6 → display col 10 + 3 = 13
    assert_equal 13, r.raw_to_formatted_display_col("Hello\tWorld\tFoo", 6, delimiter: "\t", col_widths: col_widths)
    # 'F' at raw 12 → display col 10 + 3 + 10 + 3 = 26
    assert_equal 26, r.raw_to_formatted_display_col("Hello\tWorld\tFoo", 12, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_display_col_cjk
    # "太郎" = 2 chars, 4 display cols; "Alice" = 5 chars, 5 display cols → max = 5
    # "30" = 2 chars, 2 display cols; "年齢" = 2 chars, 4 display cols → max = 4
    col_widths = [5, 4]
    r = RuVim::RichView::TableRenderer
    # "太郎\t30"
    # "太" at raw 0 → display col 0
    assert_equal 0, r.raw_to_formatted_display_col("太郎\t30", 0, delimiter: "\t", col_widths: col_widths)
    # "郎" at raw 1 → display col = dw("太") = 2
    assert_equal 2, r.raw_to_formatted_display_col("太郎\t30", 1, delimiter: "\t", col_widths: col_widths)
    # end of first field at raw 2 → display col = dw("太郎") = 4
    assert_equal 4, r.raw_to_formatted_display_col("太郎\t30", 2, delimiter: "\t", col_widths: col_widths)
    # "3" at raw 3 → display col = 5 (col_widths[0]) + 3 (separator) = 8
    assert_equal 8, r.raw_to_formatted_display_col("太郎\t30", 3, delimiter: "\t", col_widths: col_widths)
    # "0" at raw 4 → display col = 8 + dw("3") = 9
    assert_equal 9, r.raw_to_formatted_display_col("太郎\t30", 4, delimiter: "\t", col_widths: col_widths)
  end

  def test_raw_to_formatted_display_col_alignment_across_cjk_rows
    lines = ["太郎\t年齢", "Alice\t30"]
    col_widths = RuVim::RichView::TableRenderer.compute_col_widths(lines, delimiter: "\t")
    r = RuVim::RichView::TableRenderer
    # Second field starts at same display col for both lines
    # Line 0: "太郎\t年齢" → raw 3 is "年" → display col = col_widths[0]+3
    # Line 1: "Alice\t30" → raw 6 is "3" → display col = col_widths[0]+3
    dc0 = r.raw_to_formatted_display_col(lines[0], 3, delimiter: "\t", col_widths: col_widths)
    dc1 = r.raw_to_formatted_display_col(lines[1], 6, delimiter: "\t", col_widths: col_widths)
    assert_equal dc0, dc1, "Second field start should align across CJK and ASCII rows"
  end

  # --- JSON Rich View tests ---

  def test_json_registered
    assert RuVim::RichView.renderer_for("json")
  end

  def test_json_open_creates_virtual_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1,"b":[2,3]}'])
    buf.options["filetype"] = "json"
    count_before = editor.buffers.length

    RuVim::RichView.open!(editor, format: "json")
    assert_equal count_before + 1, editor.buffers.length
    new_buf = editor.current_buffer
    refute_equal buf.id, new_buf.id
    assert_equal :json_formatted, new_buf.kind
    assert new_buf.readonly?
  end

  def test_json_open_binds_close_keys
    editor = fresh_editor
    editor.keymap_manager = RuVim::KeymapManager.new
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}'])
    buf.options["filetype"] = "json"

    RuVim::RichView.open!(editor, format: "json")
    result = editor.keymap_manager.resolve_with_context(:normal, ["\e"], editor: editor)
    assert_equal "rich.close_buffer", result.invocation.id
  end

  def test_json_open_pretty_prints
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1,"b":[2,3]}'])
    buf.options["filetype"] = "json"

    RuVim::RichView.open!(editor, format: "json")
    new_buf = editor.current_buffer
    lines = new_buf.lines
    assert lines.length > 1, "Minified JSON should be expanded to multiple lines"
    assert_equal "{", lines.first.strip
    assert_equal "}", lines.last.strip
  end

  def test_json_open_multiline_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{', '"key": "value"', '}'])
    buf.options["filetype"] = "json"

    RuVim::RichView.open!(editor, format: "json")
    new_buf = editor.current_buffer
    lines = new_buf.lines
    assert lines.length >= 3
  end

  def test_json_open_invalid_json_shows_error
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"invalid json'])
    buf.options["filetype"] = "json"

    RuVim::RichView.open!(editor, format: "json")
    # Should stay on original buffer
    assert_equal buf.id, editor.current_buffer.id
    assert_match(/JSON/, editor.message.to_s)
  end

  def test_json_open_does_not_enter_rich_mode
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}'])
    buf.options["filetype"] = "json"

    RuVim::RichView.open!(editor, format: "json")
    # Virtual buffer approach — no rich mode
    assert_equal :normal, editor.mode
    assert_nil editor.rich_state
  end

  def test_json_cursor_maps_to_formatted_line
    editor = fresh_editor
    buf = editor.current_buffer
    # {"a":1,"b":{"c":2}}
    buf.replace_all_lines!(['{"a":1,"b":{"c":2}}'])
    buf.options["filetype"] = "json"

    # Place cursor at "c" key — find its offset
    line = buf.line_at(0)
    idx = line.index('"c"')
    editor.current_window.cursor_x = idx

    RuVim::RichView.open!(editor, format: "json")
    new_buf = editor.current_buffer
    # Cursor should be on the line containing "c"
    cursor_line = new_buf.line_at(editor.current_window.cursor_y)
    assert_match(/"c"/, cursor_line, "Cursor should be on the line with \"c\" key")
  end

  def test_json_cursor_maps_multiline_source
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{', '  "x": [1, 2, 3]', '}'])
    buf.options["filetype"] = "json"

    # Place cursor on line 1 at the "x" key (col 2 = opening quote)
    editor.current_window.cursor_y = 1
    editor.current_window.cursor_x = 2

    RuVim::RichView.open!(editor, format: "json")
    new_buf = editor.current_buffer
    cursor_line = new_buf.line_at(editor.current_window.cursor_y)
    assert_match(/"x"/, cursor_line, "Cursor should be on the line with \"x\" key")
  end

  def test_json_cursor_at_start_stays_at_start
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}'])
    buf.options["filetype"] = "json"
    editor.current_window.cursor_x = 0

    RuVim::RichView.open!(editor, format: "json")
    assert_equal 0, editor.current_window.cursor_y
  end

  def test_json_significant_offset
    r = RuVim::RichView::JsonRenderer
    # {"a" — 4 significant chars: { " a "
    assert_equal 4, r.significant_char_count('{"a"', 4)
    # { "a" — space outside string skipped, still 4 significant
    assert_equal 4, r.significant_char_count('{ "a"', 5)
  end

  def test_json_line_for_significant_offset
    formatted = "{\n  \"a\": 1\n}"
    r = RuVim::RichView::JsonRenderer
    # count 0 → line 0 (before any char)
    assert_equal 0, r.line_for_significant_count(formatted, 0)
    # count 1 → line 0 ({ is the 1st significant char, on line 0)
    assert_equal 0, r.line_for_significant_count(formatted, 1)
    # count 2 → line 1 (" opening quote of "a" is on line 1)
    assert_equal 1, r.line_for_significant_count(formatted, 2)
  end

  def test_json_filetype_detected
    editor = fresh_editor
    buf = editor.current_buffer
    buf.options["filetype"] = "json"
    assert_equal "json", RuVim::RichView.detect_format(buf)
  end

  # --- Filetype detection tests ---

  def test_detect_filetype_tsv
    editor = RuVim::Editor.new
    assert_equal "tsv", editor.detect_filetype("data.tsv")
  end

  def test_detect_filetype_csv
    editor = RuVim::Editor.new
    assert_equal "csv", editor.detect_filetype("data.csv")
  end

  def test_detect_filetype_tsv_uppercase
    editor = RuVim::Editor.new
    assert_equal "tsv", editor.detect_filetype("DATA.TSV")
  end

  def test_detect_filetype_jsonl
    editor = RuVim::Editor.new
    assert_equal "jsonl", editor.detect_filetype("data.jsonl")
  end

  # --- JSONL Rich View tests ---

  def test_jsonl_registered
    assert RuVim::RichView.renderer_for("jsonl")
  end

  def test_jsonl_open_creates_virtual_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}', '{"b":2}'])
    buf.options["filetype"] = "jsonl"
    count_before = editor.buffers.length

    RuVim::RichView.open!(editor, format: "jsonl")
    assert_equal count_before + 1, editor.buffers.length
    new_buf = editor.current_buffer
    refute_equal buf.id, new_buf.id
    assert_equal :jsonl_formatted, new_buf.kind
    assert new_buf.readonly?
  end

  def test_jsonl_open_binds_close_keys
    editor = fresh_editor
    editor.keymap_manager = RuVim::KeymapManager.new
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}', '{"b":2}'])
    buf.options["filetype"] = "jsonl"

    RuVim::RichView.open!(editor, format: "jsonl")
    result = editor.keymap_manager.resolve_with_context(:normal, ["\e"], editor: editor)
    assert_equal "rich.close_buffer", result.invocation.id
  end

  def test_jsonl_open_pretty_prints_each_line
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1,"b":[2,3]}', '{"c":4}'])
    buf.options["filetype"] = "jsonl"

    RuVim::RichView.open!(editor, format: "jsonl")
    new_buf = editor.current_buffer
    lines = new_buf.lines
    # Each JSON object should be expanded; separated by "---"
    assert lines.length > 2, "JSONL should be expanded to multiple lines"
    assert lines.any? { |l| l.include?("---") }, "Entries should be separated"
  end

  def test_jsonl_open_maps_cursor_to_correct_entry
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}', '{"b":2}', '{"c":3}'])
    buf.options["filetype"] = "jsonl"
    editor.current_window.cursor_y = 1  # on second entry

    RuVim::RichView.open!(editor, format: "jsonl")
    new_buf = editor.current_buffer
    cy = editor.current_window.cursor_y
    # Cursor should be within the second entry's formatted block
    nearby = (cy..[cy + 2, new_buf.lines.length - 1].min).map { |r| new_buf.line_at(r) }.join("\n")
    assert_match(/"b"/, nearby, "Cursor should be near the entry with \"b\"")
  end

  def test_jsonl_open_skips_blank_lines
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}', '', '{"b":2}'])
    buf.options["filetype"] = "jsonl"

    RuVim::RichView.open!(editor, format: "jsonl")
    new_buf = editor.current_buffer
    lines = new_buf.lines
    # Should contain both entries
    assert lines.any? { |l| l.include?('"a"') }
    assert lines.any? { |l| l.include?('"b"') }
  end

  def test_jsonl_open_shows_parse_error_inline
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(['{"a":1}', 'bad json', '{"b":2}'])
    buf.options["filetype"] = "jsonl"

    RuVim::RichView.open!(editor, format: "jsonl")
    new_buf = editor.current_buffer
    lines = new_buf.lines
    # Invalid line should show an error marker
    assert lines.any? { |l| l.include?("PARSE ERROR") }, "Invalid JSON line should show error"
  end

  def test_jsonl_filetype_detected
    editor = fresh_editor
    buf = editor.current_buffer
    buf.options["filetype"] = "jsonl"
    assert_equal "jsonl", RuVim::RichView.detect_format(buf)
  end
end
