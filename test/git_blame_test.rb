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

  def drain_git_stream!
    threads = @app.instance_variable_get(:@git_stream_threads)
    threads&.each_value(&:join)
    @app.send(:drain_stream_events!)
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

  # --- Status filename parsing ---

  def test_parse_status_modified_line
    assert_equal "lib/ruvim/app.rb", RuVim::Git::Status.parse_filename("\tmodified:   lib/ruvim/app.rb")
  end

  def test_parse_status_new_file_line
    assert_equal "foo.rb", RuVim::Git::Status.parse_filename("\tnew file:   foo.rb")
  end

  def test_parse_status_untracked_line
    assert_equal "bar.txt", RuVim::Git::Status.parse_filename("\tbar.txt")
  end

  def test_parse_status_header_returns_nil
    assert_nil RuVim::Git::Status.parse_filename("Changes not staged for commit:")
    assert_nil RuVim::Git::Status.parse_filename("  (use \"git add <file>...\")")
    assert_nil RuVim::Git::Status.parse_filename("On branch master")
    assert_nil RuVim::Git::Status.parse_filename("")
  end

  # --- Integration with App (using git repo) ---

  def test_ctrl_g_enters_git_command_mode
    feed(:ctrl_g)
    assert_equal :command_line, @editor.mode
    assert_equal ":git ", @editor.command_line.content
  end

  def test_git_blame_via_ex_git_subcommand
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git blame")

      blame_buf = @editor.current_buffer
      assert_equal :blame, blame_buf.kind
      assert_equal 2, blame_buf.line_count
    end
  end

  def test_git_blame_opens_blame_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\nline3\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git blame")

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

      @dispatcher.dispatch_ex(@editor, "git blame")

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

      @dispatcher.dispatch_ex(@editor, "git blame")
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
      setup_git_repo_multi_commits(dir, "test_file.txt")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git blame")
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

  def test_git_unknown_subcommand_shows_error
    @dispatcher.dispatch_ex(@editor, "git unknown")
    assert_match(/Unknown Git subcommand/, @editor.message)
  end

  def test_git_no_subcommand_shows_list
    @dispatcher.dispatch_ex(@editor, "git")
    assert_match(/blame/, @editor.message)
  end

  # --- GitStatus ---

  def test_git_status
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git status")

      status_buf = @editor.current_buffer
      assert_equal :git_status, status_buf.kind
      assert status_buf.readonly?
      assert_match(/\[Git Status\]/, status_buf.name)
    end
  end

  def test_git_status_enter_opens_file
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")
      # Create an uncommitted change so it shows in status
      File.write(File.join(dir, "test_file.txt"), "modified\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git status")
      assert_equal :git_status, @editor.current_buffer.kind

      # Move to a line containing the modified file
      status_buf = @editor.current_buffer
      target_line = status_buf.lines.index { |l| l.include?("test_file.txt") }
      assert target_line, "Expected test_file.txt in status output"
      @editor.current_window.cursor_y = target_line

      feed(:enter)

      # Should have opened test_file.txt
      assert_equal File.join(dir, "test_file.txt"), @editor.current_buffer.path
    end
  end

  # --- GitDiff ---

  def test_git_diff
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")
      # Make an uncommitted change
      File.write(File.join(dir, "test_file.txt"), "modified\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git diff")

      diff_buf = @editor.current_buffer
      assert_equal :git_diff, diff_buf.kind
      assert diff_buf.readonly?
      assert_match(/\[Git Diff\]/, diff_buf.name)
    end
  end

  def test_git_diff_parse_location_on_hunk_header
    lines = [
      "diff --git a/lib/foo.rb b/lib/foo.rb",
      "--- a/lib/foo.rb",
      "+++ b/lib/foo.rb",
      "@@ -1,3 +1,4 @@",
      " line1",
      "+added",
      " line2",
      " line3",
    ]
    # On hunk header line → file at start of hunk
    file, line = RuVim::Git::Diff.parse_location(lines, 3)
    assert_equal "lib/foo.rb", file
    assert_equal 1, line
  end

  def test_git_diff_parse_location_on_context_line
    lines = [
      "diff --git a/lib/foo.rb b/lib/foo.rb",
      "--- a/lib/foo.rb",
      "+++ b/lib/foo.rb",
      "@@ -1,3 +1,4 @@",
      " line1",
      "+added",
      " line2",
    ]
    # On " line2" (index 6): new-side lines are " line1"(+1), "+added"(+2), " line2"(+3)
    file, line = RuVim::Git::Diff.parse_location(lines, 6)
    assert_equal "lib/foo.rb", file
    assert_equal 3, line
  end

  def test_git_diff_parse_location_on_added_line
    lines = [
      "diff --git a/lib/foo.rb b/lib/foo.rb",
      "--- a/lib/foo.rb",
      "+++ b/lib/foo.rb",
      "@@ -1,3 +1,4 @@",
      " line1",
      "+added",
      " line2",
    ]
    file, line = RuVim::Git::Diff.parse_location(lines, 5)
    assert_equal "lib/foo.rb", file
    assert_equal 2, line
  end

  def test_git_diff_parse_location_on_deleted_line
    lines = [
      "diff --git a/lib/foo.rb b/lib/foo.rb",
      "--- a/lib/foo.rb",
      "+++ b/lib/foo.rb",
      "@@ -1,3 +1,3 @@",
      " line1",
      "-removed",
      " line2",
    ]
    # Deleted line → jump to the next new-side line position
    file, line = RuVim::Git::Diff.parse_location(lines, 5)
    assert_equal "lib/foo.rb", file
    assert_equal 2, line
  end

  def test_git_diff_parse_location_on_diff_header
    lines = [
      "diff --git a/lib/foo.rb b/lib/foo.rb",
      "index abc..def 100644",
      "--- a/lib/foo.rb",
      "+++ b/lib/foo.rb",
      "@@ -1,3 +1,3 @@",
    ]
    # On "diff --git" line → file, line 1
    file, line = RuVim::Git::Diff.parse_location(lines, 0)
    assert_equal "lib/foo.rb", file
    assert_equal 1, line
  end

  def test_git_diff_parse_location_returns_nil_for_empty
    assert_nil RuVim::Git::Diff.parse_location([], 0)
  end

  def test_git_diff_enter_opens_file
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\nline2\nline3\n")
      File.write(File.join(dir, "test_file.txt"), "line1\nmodified\nline3\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git diff")
      assert_equal :git_diff, @editor.current_buffer.kind

      # Find a line with the modified content
      diff_buf = @editor.current_buffer
      target_line = diff_buf.lines.index { |l| l.start_with?("+modified") }
      assert target_line, "Expected +modified in diff output"
      @editor.current_window.cursor_y = target_line

      feed(:enter)

      # Should have opened test_file.txt
      assert_equal File.join(dir, "test_file.txt"), @editor.current_buffer.path
    end
  end

  def test_git_diff_clean_shows_message
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git diff")

      # Should stay on original buffer, no diff buffer opened
      assert_equal :file, @editor.current_buffer.kind
      assert_match(/clean/, @editor.message)
    end
  end

  # --- GitLog ---

  def test_git_log
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git log")
      drain_git_stream!

      log_buf = @editor.current_buffer
      assert_equal :git_log, log_buf.kind
      assert log_buf.readonly?
      assert_match(/\[Git Log\]/, log_buf.name)
      assert log_buf.lines.any? { |l| l.include?("initial") }
    end
  end

  def test_git_log_with_p_flag
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git log -p")
      drain_git_stream!

      log_buf = @editor.current_buffer
      assert_equal :git_log, log_buf.kind
      # -p shows diffs, so output should include diff markers
      assert log_buf.lines.any? { |l| l.start_with?("diff") || l.start_with?("+++") || l.start_with?("---") }
    end
  end

  # --- GitBranch ---

  def test_git_branch
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git branch")

      branch_buf = @editor.current_buffer
      assert_equal :git_branch, branch_buf.kind
      assert branch_buf.readonly?
      assert_match(/\[Git Branch\]/, branch_buf.name)
      assert branch_buf.lines.any? { |l| l.include?("master") || l.include?("main") }
    end
  end

  def test_git_branch_parse_name
    assert_equal "master", RuVim::Git::Branch.parse_branch_name("* master\t2025-03-06\tInitial")
    assert_equal "feature", RuVim::Git::Branch.parse_branch_name("  feature\t2025-03-05\tAdd feature")
    assert_nil RuVim::Git::Branch.parse_branch_name("")
  end

  def test_git_branch_enter_checks_out
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")
      # Create a second branch
      Dir.chdir(dir) do
        system("git branch test-branch", exception: true)
      end

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git branch")
      assert_equal :git_branch, @editor.current_buffer.kind

      branch_buf = @editor.current_buffer
      target_line = branch_buf.lines.index { |l| l.include?("test-branch") }
      assert target_line, "Expected test-branch in branch output"
      @editor.current_window.cursor_y = target_line

      feed(:enter)

      # Branch buffer should be closed, and we should have switched
      refute_equal :git_branch, @editor.current_buffer.kind
      # Verify checkout happened
      Dir.chdir(dir) do
        current = `git rev-parse --abbrev-ref HEAD`.strip
        assert_equal "test-branch", current
      end
    end
  end

  # --- GitCommit ---

  def test_git_commit_prepare
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")
      File.write(File.join(dir, "test_file.txt"), "modified\n")
      Dir.chdir(dir) { system("git add test_file.txt", exception: true) }

      lines, root, err = RuVim::Git::Commit.prepare(File.join(dir, "test_file.txt"))
      assert_nil err
      assert_equal dir, File.realpath(root)
      assert_equal "", lines.first  # Empty line for message
      assert lines.any? { |l| l.start_with?("#") }
    end
  end

  def test_git_commit_extract_message
    lines = ["Fix the bug", "", "Detailed description", "# comment line", "# another"]
    msg = RuVim::Git::Commit.extract_message(lines)
    assert_equal "Fix the bug\n\nDetailed description", msg
  end

  def test_git_commit_extract_message_empty
    lines = ["# comment only", "# another"]
    msg = RuVim::Git::Commit.extract_message(lines)
    assert_equal "", msg
  end

  def test_git_commit_opens_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git commit")

      commit_buf = @editor.current_buffer
      assert_equal :git_commit, commit_buf.kind
      refute commit_buf.readonly?
      assert commit_buf.modifiable?
      assert_equal :insert, @editor.mode
    end
  end

  def test_git_commit_via_write
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")
      File.write(File.join(dir, "test_file.txt"), "modified\n")
      Dir.chdir(dir) { system("git add test_file.txt", exception: true) }

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git commit")
      assert_equal :git_commit, @editor.current_buffer.kind

      # Type a commit message on the first line
      commit_buf = @editor.current_buffer
      commit_buf.lines[0] = "Test commit message"

      # :w should trigger the commit
      @dispatcher.dispatch_ex(@editor, "w")

      # Commit buffer should be closed
      refute_equal :git_commit, @editor.current_buffer.kind

      # Verify commit happened
      Dir.chdir(dir) do
        log = `git log --oneline -1`.strip
        assert_includes log, "Test commit message"
      end
    end
  end

  def test_git_commit_empty_message_aborts
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git commit")
      assert_equal :git_commit, @editor.current_buffer.kind

      # Don't type anything, just try to write
      @dispatcher.dispatch_ex(@editor, "w")

      # Should still be on commit buffer (abort didn't close it)
      assert_equal :git_commit, @editor.current_buffer.kind
      assert_match(/Empty commit message/, @editor.message)
    end
  end

  # --- Close with Esc/C-c ---

  def test_esc_closes_git_blame_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      original_buf_id = buf.id
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git blame")
      assert_equal :blame, @editor.current_buffer.kind

      feed(:escape)
      assert_equal original_buf_id, @editor.current_buffer.id
    end
  end

  def test_esc_closes_git_status_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      original_buf_id = buf.id
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git status")
      assert_equal :git_status, @editor.current_buffer.kind

      feed(:escape)
      assert_equal original_buf_id, @editor.current_buffer.id
    end
  end

  def test_esc_closes_git_log_buffer
    Dir.mktmpdir do |dir|
      setup_git_repo(dir, "test_file.txt", "line1\n")

      file_path = File.join(dir, "test_file.txt")
      buf = @editor.add_buffer_from_file(file_path)
      original_buf_id = buf.id
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git log")
      assert_equal :git_log, @editor.current_buffer.kind

      feed(:escape)
      assert_equal original_buf_id, @editor.current_buffer.id
    end
  end

  # --- Error cases ---

  def test_git_blame_on_non_git_file_shows_error
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, "no_git.txt")
      File.write(file_path, "hello\n")

      buf = @editor.add_buffer_from_file(file_path)
      @editor.switch_to_buffer(buf.id)

      @dispatcher.dispatch_ex(@editor, "git blame")

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
