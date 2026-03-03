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

  def test_active_returns_false_for_normal_buffer
    editor = fresh_editor
    refute RuVim::RichView.active?(editor.current_buffer)
  end

  def test_open_creates_rich_view_buffer
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb", "c\td"])
    buf.options["filetype"] = "tsv"

    rv_buf = RuVim::RichView.open!(editor, format: "tsv")
    assert_equal :rich_view, rv_buf.kind
    assert RuVim::RichView.active?(rv_buf)
    assert rv_buf.readonly?
    assert_equal false, editor.effective_option("wrap", window: editor.current_window, buffer: rv_buf)
  end

  def test_open_copies_lines_from_source
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb", "c\td", "e\tf"])
    buf.options["filetype"] = "tsv"

    rv_buf = RuVim::RichView.open!(editor, format: "tsv")
    assert_equal 3, rv_buf.line_count
    assert_equal "a\tb", rv_buf.line_at(0)
  end

  def test_close_returns_to_previous_buffer
    editor = fresh_editor
    original_buf = editor.current_buffer
    original_buf.replace_all_lines!(["x\ty"])
    original_buf.options["filetype"] = "tsv"

    RuVim::RichView.open!(editor, format: "tsv")
    refute_equal original_buf.id, editor.current_buffer.id

    RuVim::RichView.close!(editor)
    assert_equal original_buf.id, editor.current_buffer.id
  end

  def test_toggle_opens_and_closes
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tb"])
    buf.options["filetype"] = "tsv"

    RuVim::RichView.toggle!(editor)
    assert RuVim::RichView.active?(editor.current_buffer)

    RuVim::RichView.toggle!(editor)
    refute RuVim::RichView.active?(editor.current_buffer)
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

  def test_render_visible_lines_integration
    editor = fresh_editor
    buf = editor.current_buffer
    buf.replace_all_lines!(["a\tbb", "ccc\td"])
    buf.options["filetype"] = "tsv"

    rv_buf = RuVim::RichView.open!(editor, format: "tsv")
    lines = [rv_buf.line_at(0), rv_buf.line_at(1)]
    rendered = RuVim::RichView.render_visible_lines(rv_buf, lines)
    assert_equal 2, rendered.length
    assert_includes rendered[0], " | "
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
end
