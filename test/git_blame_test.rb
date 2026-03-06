# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

class GitBlameTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @app.send(:handle_key, k) }
  end

  # --- Parsing ---

  def test_parse_porcelain_basic
    porcelain = <<~PORCELAIN
      abc1234abc1234abc1234abc1234abc1234abc123 1 1 1
      author Alice
      author-mail <alice@example.com>
      author-time 1700000000
      author-tz +0900
      committer Alice
      committer-mail <alice@example.com>
      committer-time 1700000000
      committer-tz +0900
      summary Initial commit
      filename foo.rb
      \thello world
    PORCELAIN

    entries = RuVim::Git::Blame.parse_porcelain(porcelain)
    assert_equal 1, entries.length
    e = entries.first
    assert_equal "abc1234a", e[:short_hash]
    assert_equal "Alice", e[:author]
    assert_equal "Initial commit", e[:summary]
    assert_equal "hello world", e[:text]
    assert_equal 1, e[:orig_line]
  end

  def test_parse_porcelain_multi_line
    porcelain = <<~PORCELAIN
      aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111 1 1 2
      author Alice
      author-mail <alice@example.com>
      author-time 1700000000
      author-tz +0900
      committer Alice
      committer-mail <alice@example.com>
      committer-time 1700000000
      committer-tz +0900
      summary First
      filename foo.rb
      \tline one
      aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111 2 2
      \tline two
    PORCELAIN

    entries = RuVim::Git::Blame.parse_porcelain(porcelain)
    assert_equal 2, entries.length
    assert_equal "line one", entries[0][:text]
    assert_equal "line two", entries[1][:text]
    assert_equal "aaaa1111", entries[0][:short_hash]
    assert_equal "aaaa1111", entries[1][:short_hash]
  end

  def test_format_blame_lines
    entries = [
      { short_hash: "abc12345", author: "Alice", date: "2023-11-14", text: "hello", orig_line: 1, hash: "abc12345" * 5 },
      { short_hash: "def67890", author: "Bob",   date: "2023-11-15", text: "world", orig_line: 2, hash: "def67890" * 5 },
    ]
    lines = RuVim::Git::Blame.format_lines(entries)
    assert_equal 2, lines.length
    assert_includes lines[0], "abc12345"
    assert_includes lines[0], "Alice"
    assert_includes lines[0], "hello"
    assert_includes lines[1], "Bob"
  end

  # --- Integration with App (using git repo) ---

  def test_git_blame_opens_blame_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\nline3\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      feed("g", "b")

      blame_buf = @editor.current_buffer
      assert_equal :blame, blame_buf.kind
      assert blame_buf.readonly?
      refute blame_buf.modifiable?
      assert_match(/\[Blame\]/, blame_buf.name)
      assert_equal 3, blame_buf.line_count
    end
  end

  def test_git_blame_buffer_local_bindings
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      feed("g", "b")

      blame_buf = @editor.current_buffer
      assert_equal :blame, blame_buf.kind

      # 'c' should be bound to git.blame.commit for this buffer
      km = @app.instance_variable_get(:@keymaps)
      match = km.resolve_with_context(:normal, ["c"], editor: @editor)
      assert_equal :match, match.status
      assert_equal "git.blame.commit", match.invocation.id
    end
  end

  def test_git_blame_commit_opens_show_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      feed("g", "b")
      assert_equal :blame, @editor.current_buffer.kind

      # Press 'c' to show commit
      feed("c")

      show_buf = @editor.current_buffer
      assert_equal :git_show, show_buf.kind
      refute show_buf.modifiable?
      assert_match(/\[Commit\]/, show_buf.name)
    end
  end

  def test_git_blame_prev_and_back
    Dir.mktmpdir do |dir|
      # Create repo with two commits
      setup_git_repo_multi_commits(dir, "test_file.txt")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      feed("g", "b")
      blame_buf = @editor.current_buffer
      assert_equal :blame, blame_buf.kind

      original_lines = blame_buf.lines.dup

      # Press 'p' to go to previous blame
      feed("p")
      assert_equal :blame, @editor.current_buffer.kind
      refute_equal original_lines, @editor.current_buffer.lines

      # Press 'P' to go back
      feed("P")
      assert_equal :blame, @editor.current_buffer.kind
      assert_equal original_lines, @editor.current_buffer.lines
    end
  end

  def test_ex_blame_command
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "blame")

      blame_buf = @editor.current_buffer
      assert_equal :blame, blame_buf.kind
      assert_equal 2, blame_buf.line_count
    end
  end

  def test_git_blame_on_non_git_file_shows_error
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, "no_git.txt")
      File.write(file_path, "hello\n")

      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      feed("g", "b")

      # Should remain on original buffer (blame failed)
      assert_equal :file, @editor.current_buffer.kind
    end
  end

  private

  def setup_git_repo(dir, filename, content)
    Dir.chdir(dir) do
      system("git init -q .", exception: true)
      system("git config user.email test@test.com", exception: true)
      system("git config user.name Test", exception: true)
      File.write(filename, content)
      system("git add #{filename}", exception: true)
      system("git commit -q -m 'initial' --no-gpg-sign", exception: true)
    end
  end

  def setup_git_repo_multi_commits(dir, filename)
    Dir.chdir(dir) do
      system("git init -q .", exception: true)
      system("git config user.email test@test.com", exception: true)
      system("git config user.name Test", exception: true)
      File.write(filename, "original line\n")
      system("git add #{filename}", exception: true)
      system("git commit -q -m 'first commit' --no-gpg-sign", exception: true)
      File.write(filename, "modified line\n")
      system("git add #{filename}", exception: true)
      system("git commit -q -m 'second commit' --no-gpg-sign", exception: true)
    end
  end
end
