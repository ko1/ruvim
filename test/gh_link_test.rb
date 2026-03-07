# frozen_string_literal: true

require_relative "test_helper"

class GhLinkTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @editor.materialize_intro_buffer!
  end

  # --- URL parsing ---

  def test_parse_ssh_remote
    url = RuVim::Git::Link.github_url_from_remote("git@github.com:user/repo.git")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_ssh_remote_without_dot_git
    url = RuVim::Git::Link.github_url_from_remote("git@github.com:user/repo")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_https_remote
    url = RuVim::Git::Link.github_url_from_remote("https://github.com/user/repo.git")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_https_remote_without_dot_git
    url = RuVim::Git::Link.github_url_from_remote("https://github.com/user/repo")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_non_github_remote_returns_nil
    url = RuVim::Git::Link.github_url_from_remote("git@gitlab.com:user/repo.git")
    assert_nil url
  end

  def test_parse_empty_remote_returns_nil
    url = RuVim::Git::Link.github_url_from_remote("")
    assert_nil url
  end

  # --- Link building ---

  def test_build_link_single_line
    link = RuVim::Git::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 10)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L10", link
  end

  def test_build_link_line_range
    link = RuVim::Git::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 10, 20)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L10-L20", link
  end

  def test_build_link_same_start_end
    link = RuVim::Git::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 5, 5)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L5", link
  end

  # --- OSC 52 ---

  def test_osc52_escape_sequence
    seq = RuVim::Git::Link.osc52_copy_sequence("hello")
    expected = "\e]52;c;#{["hello"].pack("m0")}\a"
    assert_equal expected, seq
  end

  # --- Ex command integration ---

  def test_gh_no_subcommand_shows_help
    @dispatcher.dispatch_ex(@editor, "gh")
    assert_match(/link/, @editor.message)
  end

  def test_gh_unknown_subcommand_shows_error
    @dispatcher.dispatch_ex(@editor, "gh unknown")
    assert @editor.message_error?
    assert_match(/Unknown/, @editor.message)
  end
end
