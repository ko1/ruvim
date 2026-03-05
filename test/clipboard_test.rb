require_relative "test_helper"

class ClipboardTest < Minitest::Test
  def setup
    RuVim::Clipboard.reset_backend!
  end

  def teardown
    RuVim::Clipboard.reset_backend!
  end

  def test_available_returns_true_when_backend_exists
    RuVim::Clipboard.instance_variable_set(:@backend, { write: %w[echo], read: %w[echo] })
    assert RuVim::Clipboard.available?
  end

  def test_available_returns_false_when_no_backend
    RuVim::Clipboard.instance_variable_set(:@backend, false)
    refute RuVim::Clipboard.available?
  end

  def test_read_returns_nil_when_no_read_cmd
    RuVim::Clipboard.instance_variable_set(:@backend, { write: nil, read: nil })
    assert_nil RuVim::Clipboard.read
  end

  def test_read_returns_output_on_success
    RuVim::Clipboard.instance_variable_set(:@backend, { write: %w[true], read: %w[echo hello] })
    result = RuVim::Clipboard.read
    assert_equal "hello\n", result
  end

  def test_read_returns_nil_on_command_failure
    RuVim::Clipboard.instance_variable_set(:@backend, { write: %w[true], read: %w[false] })
    assert_nil RuVim::Clipboard.read
  end

  def test_write_returns_false_when_no_write_cmd
    RuVim::Clipboard.instance_variable_set(:@backend, { write: nil, read: nil })
    refute RuVim::Clipboard.write("test")
  end

  def test_write_sends_text_to_command
    RuVim::Clipboard.instance_variable_set(:@backend, { write: %w[cat], read: %w[true] })
    assert RuVim::Clipboard.write("hello")
  end

  def test_pbcopy_backend_format
    expected = { write: %w[pbcopy], read: %w[pbpaste] }
    assert_equal expected, RuVim::Clipboard.pbcopy_backend
  end

  def test_wayland_backend_format
    expected = { write: %w[wl-copy], read: %w[wl-paste -n] }
    assert_equal expected, RuVim::Clipboard.wayland_backend
  end

  def test_xclip_backend_format
    expected = { write: %w[xclip -selection clipboard -in], read: %w[xclip -selection clipboard -out] }
    assert_equal expected, RuVim::Clipboard.xclip_backend
  end

  def test_xsel_backend_format
    expected = { write: %w[xsel --clipboard --input], read: %w[xsel --clipboard --output] }
    assert_equal expected, RuVim::Clipboard.xsel_backend
  end
end
