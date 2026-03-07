# frozen_string_literal: true

require_relative "test_helper"

class BrowserTest < Minitest::Test
  def test_wsl_mount_point_default
    assert_equal "/mnt/", RuVim::Browser.wsl_mount_point(config: nil)
  end

  def test_wsl_mount_point_from_config
    config = <<~CONF
      [automount]
      root = /win/
    CONF
    assert_equal "/win/", RuVim::Browser.wsl_mount_point(config: config)
  end

  def test_wsl_mount_point_with_missing_trailing_slash
    config = <<~CONF
      [automount]
      root = /win
    CONF
    assert_equal "/win/", RuVim::Browser.wsl_mount_point(config: config)
  end

  def test_wsl_mount_point_ignores_commented_line
    config = <<~CONF
      [automount]
      # root = /old/
      root = /new/
    CONF
    assert_equal "/new/", RuVim::Browser.wsl_mount_point(config: config)
  end

  def test_detect_backend_returns_a_hash_or_nil
    result = RuVim::Browser.detect_backend
    if result
      assert_kind_of Symbol, result[:type]
    end
  end

  def test_powershell_path_uses_mount_point
    path = RuVim::Browser.powershell_path("/mnt/")
    assert_equal "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", path
  end

  # --- URL validation ---

  def test_valid_url_https
    assert RuVim::Browser.valid_url?("https://github.com/user/repo")
  end

  def test_valid_url_http
    assert RuVim::Browser.valid_url?("http://example.com")
  end

  def test_invalid_url_file
    refute RuVim::Browser.valid_url?("file:///etc/passwd")
  end

  def test_invalid_url_javascript
    refute RuVim::Browser.valid_url?("javascript:alert(1)")
  end

  def test_invalid_url_empty
    refute RuVim::Browser.valid_url?("")
  end

  def test_invalid_url_nil
    refute RuVim::Browser.valid_url?(nil)
  end

  # --- PowerShell encoded command ---

  def test_powershell_encoded_command_uses_encoded_flag
    cmd = RuVim::Browser.powershell_encoded_command("/ps.exe", "https://github.com/user/repo")
    assert_equal "/ps.exe", cmd[0]
    assert_includes cmd, "-EncodedCommand"
    refute_includes cmd, "-Command"
  end

  def test_powershell_encoded_command_escapes_single_quotes
    cmd = RuVim::Browser.powershell_encoded_command("/ps.exe", "https://example.com/it's")
    encoded = cmd.last
    decoded = encoded.unpack1("m0").force_encoding("UTF-16LE").encode("UTF-8")
    assert_includes decoded, "it''s"
  end
end
