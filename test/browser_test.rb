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
      assert_kind_of Array, result[:command]
      assert_kind_of Symbol, result[:type]
    end
  end

  def test_powershell_path_uses_mount_point
    path = RuVim::Browser.powershell_path("/mnt/")
    assert_equal "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", path
  end
end
