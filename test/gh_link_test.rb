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
    url = RuVim::Gh::Link.github_url_from_remote("git@github.com:user/repo.git")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_ssh_remote_without_dot_git
    url = RuVim::Gh::Link.github_url_from_remote("git@github.com:user/repo")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_https_remote
    url = RuVim::Gh::Link.github_url_from_remote("https://github.com/user/repo.git")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_https_remote_without_dot_git
    url = RuVim::Gh::Link.github_url_from_remote("https://github.com/user/repo")
    assert_equal "https://github.com/user/repo", url
  end

  def test_parse_non_github_remote_returns_nil
    url = RuVim::Gh::Link.github_url_from_remote("git@gitlab.com:user/repo.git")
    assert_nil url
  end

  def test_parse_empty_remote_returns_nil
    url = RuVim::Gh::Link.github_url_from_remote("")
    assert_nil url
  end

  # --- Link building ---

  def test_build_link_single_line
    link = RuVim::Gh::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 10)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L10", link
  end

  def test_build_link_line_range
    link = RuVim::Gh::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 10, 20)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L10-L20", link
  end

  def test_build_link_same_start_end
    link = RuVim::Gh::Link.build_url("https://github.com/user/repo", "main", "lib/foo.rb", 5, 5)
    assert_equal "https://github.com/user/repo/blob/main/lib/foo.rb#L5", link
  end

  # --- OSC 52 ---

  def test_osc52_escape_sequence
    seq = RuVim::Gh::Link.osc52_copy_sequence("hello")
    expected = "\e]52;c;#{["hello"].pack("m0")}\a"
    assert_equal expected, seq
  end

  # --- Remote detection ---

  def test_find_github_remote_with_specific_name
    # This test runs in the actual ruvim repo
    name, url = RuVim::Gh::Link.find_github_remote(Dir.pwd, "origin")
    if url
      assert_equal "origin", name
      assert_match(%r{\Ahttps://github\.com/}, url)
    else
      skip "origin is not a GitHub remote in this repo"
    end
  end

  def test_find_github_remote_auto_detect
    name, url = RuVim::Gh::Link.find_github_remote(Dir.pwd)
    if url
      assert_kind_of String, name
      assert_match(%r{\Ahttps://github\.com/}, url)
    else
      skip "No GitHub remote in this repo"
    end
  end

  def test_find_github_remote_nonexistent_returns_nil
    name, url = RuVim::Gh::Link.find_github_remote(Dir.pwd, "nonexistent_remote_xyz")
    assert_nil name
    assert_nil url
  end

  # --- Resolve warning ---

  def test_resolve_returns_warning_when_file_differs
    # file_differs_from_remote? returns true for non-existent remote ref
    assert RuVim::Gh::Link.file_differs_from_remote?(Dir.pwd, "nonexistent_remote_xyz", "main", __FILE__)
  end

  # --- Ex command integration ---

  # --- PR URL ---

  def test_pr_search_url
    url = RuVim::Gh::Link.pr_search_url("https://github.com/user/repo", "feature-branch")
    assert_equal "https://github.com/user/repo/pulls?q=head:feature-branch", url
  end

  # --- Ex command integration ---

  def test_gh_browse_listed_in_subcommands
    @dispatcher.dispatch_ex(@editor, "gh")
    assert_match(/browse/, @editor.message)
  end

  def test_gh_pr_listed_in_subcommands
    @dispatcher.dispatch_ex(@editor, "gh")
    assert_match(/pr/, @editor.message)
  end

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
