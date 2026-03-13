# frozen_string_literal: true

require_relative "test_helper"

class ImageViewTest < Minitest::Test
  def setup
    @editor = fresh_editor
  end

  # --- Filetype detection ---

  def test_detect_png
    assert_equal "image", @editor.detect_filetype("photo.png")
  end

  def test_detect_jpg
    assert_equal "image", @editor.detect_filetype("photo.jpg")
  end

  def test_detect_jpeg
    assert_equal "image", @editor.detect_filetype("photo.jpeg")
  end

  def test_detect_gif
    assert_equal "image", @editor.detect_filetype("anim.gif")
  end

  def test_detect_bmp
    assert_equal "image", @editor.detect_filetype("icon.bmp")
  end

  def test_detect_webp
    assert_equal "image", @editor.detect_filetype("photo.webp")
  end

  def test_detect_png_case_insensitive
    assert_equal "image", @editor.detect_filetype("PHOTO.PNG")
  end

  # --- ImageRenderer open_view! ---

  def test_image_renderer_creates_virtual_buffer
    # Create a minimal PNG file
    tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
    path = File.join(tmpdir, "test_image.png")
    # Minimal valid PNG (1x1 white pixel)
    File.binwrite(path, minimal_png)

    buf = @editor.add_buffer_from_file(path)
    @editor.switch_to_buffer(buf.id)

    RuVim::RichView::ImageRenderer.open_view!(@editor)

    # Should have switched to a virtual buffer
    current = @editor.current_buffer
    assert_equal :image_view, current.kind
    assert_match(/test_image\.png/, current.name)

    # Virtual buffer should contain a markdown image line
    line = current.line_at(0)
    assert_match(/!\[.*\]\(.*test_image\.png\)/, line)

    # Should be in rich mode with markdown format
    assert @editor.rich_state
    assert_equal :markdown, @editor.rich_state[:format]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_image_renderer_uses_absolute_path
    tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
    path = File.join(tmpdir, "abs_test.png")
    File.binwrite(path, minimal_png)

    buf = @editor.add_buffer_from_file(path)
    @editor.switch_to_buffer(buf.id)

    RuVim::RichView::ImageRenderer.open_view!(@editor)

    current = @editor.current_buffer
    line = current.line_at(0)
    # Path in markdown should be absolute
    assert_includes line, File.expand_path(path)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  # --- auto_open ---

  def test_auto_open
    assert RuVim::RichView::ImageRenderer.auto_open?
  end

  # --- RichView registration ---

  def test_richview_registered_for_image
    renderer = RuVim::RichView.renderer_for(:image)
    assert_equal RuVim::RichView::ImageRenderer, renderer
  end

  private

  # Minimal valid 1x1 white PNG
  def minimal_png
    [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, # 1x1
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, # 8-bit RGB
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, # IDAT chunk
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x36, 0x28, 0x19,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, # IEND chunk
      0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")
  end
end
