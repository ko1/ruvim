# frozen_string_literal: true

require_relative "test_helper"
require "ruvim/sixel"

class SixelTest < Minitest::Test
  def fixture_png
    File.binread(File.expand_path("fixtures/test.png", __dir__))
  end

  # --- PNG Decoder ---

  def test_decode_png_returns_width_height_pixels
    result = RuVim::Sixel::PNGDecoder.decode(fixture_png)
    assert_equal 4, result[:width]
    assert_equal 4, result[:height]
    assert_equal 4, result[:pixels].length      # 4 rows
    assert_equal 4, result[:pixels][0].length    # 4 cols
  end

  def test_decode_png_pixel_values
    result = RuVim::Sixel::PNGDecoder.decode(fixture_png)
    px = result[:pixels]
    # Row 0: red, green, blue, white
    assert_equal [255, 0, 0], px[0][0]
    assert_equal [0, 255, 0], px[0][1]
    assert_equal [0, 0, 255], px[0][2]
    assert_equal [255, 255, 255], px[0][3]
    # Row 1: all black
    assert_equal [0, 0, 0], px[1][0]
    # Row 2: all white
    assert_equal [255, 255, 255], px[2][0]
    # Row 3: red, red, green, green
    assert_equal [255, 0, 0], px[3][0]
    assert_equal [0, 255, 0], px[3][2]
  end

  def test_decode_png_invalid_signature
    assert_raises(RuVim::Sixel::PNGDecoder::Error) do
      RuVim::Sixel::PNGDecoder.decode("not a png")
    end
  end

  # --- Quantizer ---

  def test_quantize_color
    # 8R × 8G × 4B = 256 palette
    q = RuVim::Sixel::Quantizer
    idx = q.quantize(255, 0, 0)
    assert_kind_of Integer, idx
    assert idx >= 0 && idx < 256

    # Same color should give same index
    assert_equal idx, q.quantize(255, 0, 0)

    # Black
    black = q.quantize(0, 0, 0)
    assert_equal 0, black

    # White: ri=7, gi=7, bi=3 → 7*32 + 7*4 + 3 = 255
    white = q.quantize(255, 255, 255)
    assert_equal 255, white
  end

  def test_quantize_color_register
    q = RuVim::Sixel::Quantizer
    r, g, b = q.color_register(0)  # black
    assert_equal [0, 0, 0], [r, g, b]

    r, g, b = q.color_register(255)  # white
    assert_equal [100, 100, 100], [r, g, b]
  end

  # --- Sixel Encoder ---

  def test_encode_returns_sixel_string_and_rows
    result = RuVim::Sixel.encode(fixture_png, max_width_cells: 10, max_height_cells: 5)
    refute_nil result
    assert_kind_of String, result[:sixel]
    assert_kind_of Integer, result[:rows]
    assert result[:rows] > 0
  end

  def test_encode_sixel_starts_with_dcs
    result = RuVim::Sixel.encode(fixture_png, max_width_cells: 10, max_height_cells: 5)
    assert result[:sixel].start_with?("\eP0;1q"), "Sixel should start with DCS (ESC P 0;1 q)"
  end

  def test_encode_sixel_ends_with_st
    result = RuVim::Sixel.encode(fixture_png, max_width_cells: 10, max_height_cells: 5)
    assert result[:sixel].end_with?("\e\\"), "Sixel should end with ST (ESC \\)"
  end

  def test_encode_sixel_contains_color_registers
    result = RuVim::Sixel.encode(fixture_png, max_width_cells: 10, max_height_cells: 5)
    # Color registers look like #N;2;R;G;B
    assert_match(/#\d+;2;\d+;\d+;\d+/, result[:sixel])
  end

  def test_encode_nil_for_invalid_data
    result = RuVim::Sixel.encode("not png", max_width_cells: 10, max_height_cells: 5)
    assert_nil result
  end

  def test_encode_respects_max_dimensions
    result = RuVim::Sixel.encode(fixture_png, max_width_cells: 1, max_height_cells: 1, cell_width: 8, cell_height: 16)
    refute_nil result
    # With max 1 cell (8px wide, 16px tall), image should be resized down
    assert result[:rows] <= 1
  end

  # --- Resize ---

  def test_resize_downscale
    pixels = [
      [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]],
      [[0, 0, 0],   [0, 0, 0],   [0, 0, 0],   [0, 0, 0]],
      [[255, 255, 255], [255, 255, 255], [255, 255, 255], [255, 255, 255]],
      [[255, 0, 0], [255, 0, 0], [0, 255, 0], [0, 255, 0]]
    ]
    resized = RuVim::Sixel::Resizer.resize(pixels, 4, 4, 2, 2)
    assert_equal 2, resized.length
    assert_equal 2, resized[0].length
    # Nearest neighbor: pixel[0][0] should be [255,0,0] (top-left of source)
    assert_equal [255, 0, 0], resized[0][0]
  end

  def test_resize_no_change
    pixels = [[[255, 0, 0], [0, 255, 0]], [[0, 0, 255], [0, 0, 0]]]
    resized = RuVim::Sixel::Resizer.resize(pixels, 2, 2, 2, 2)
    assert_equal pixels, resized
  end

  # --- Markdown IMAGE_RE ---

  def test_markdown_image_re
    md = RuVim::Lang::Markdown
    assert md::IMAGE_RE.match?("![alt](path.png)")
    assert md::IMAGE_RE.match?("  ![description](./images/photo.png)  ")
    assert md::IMAGE_RE.match?("[link only](./pic.png)")
    assert md::IMAGE_RE.match?("  [text](path)  ")
    refute md::IMAGE_RE.match?("text ![alt](path.png) more text")
    refute md::IMAGE_RE.match?("text [link](url) more")
  end

  def test_markdown_parse_image
    md = RuVim::Lang::Markdown.instance
    result = md.parse_image("![my image](./test.png)")
    assert_equal ["my image", "./test.png"], result

    result2 = md.parse_image("[HTML view](./docs/pic.png)")
    assert_equal ["HTML view", "./docs/pic.png"], result2

    assert_nil md.parse_image("not an image line")
    assert_nil md.parse_image("text ![alt](path) text")
  end

  # --- MarkdownRenderer image tag ---

  def test_markdown_renderer_image_line_returns_hash
    renderer = RuVim::RichView::MarkdownRenderer
    lines = ["# Heading", "![photo](./pic.png)", "Normal text"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_kind_of Hash, result[1]
    assert_equal :image, result[1][:type]
    assert_equal "photo", result[1][:alt]
    assert_equal "./pic.png", result[1][:path]
  end

  def test_markdown_renderer_normal_lines_still_strings
    renderer = RuVim::RichView::MarkdownRenderer
    lines = ["# Heading", "Normal text"]
    result = renderer.render_visible(lines, delimiter: nil)
    assert_kind_of String, result[0]
    assert_kind_of String, result[1]
  end

  # --- Screen image placeholder ---

  def test_screen_image_placeholder_when_sixel_off
    editor = fresh_editor
    editor.set_option("sixel", "off")
    buf = editor.current_buffer
    buf.replace_all_lines!(["# Test", "![photo](./pic.png)", "text"])
    buf.options["filetype"] = "markdown"
    editor.enter_rich_mode(format: :markdown, delimiter: nil)

    terminal = RuVim::Terminal.new(stdin: StringIO.new, stdout: StringIO.new)
    screen = RuVim::Screen.new(terminal: terminal)

    win = editor.current_window
    win.cursor_y = 0
    win.cursor_x = 0

    # Render and check placeholder appears
    gutter_w = 0
    content_w = 40
    rows = screen.send(:rich_view_render_rows, editor, win, buf, height: 3, gutter_w: gutter_w, content_w: content_w)
    # The image line should show placeholder text
    image_row = rows[1]
    assert_match(/\[Image: photo\]/, image_row)
  end
end
