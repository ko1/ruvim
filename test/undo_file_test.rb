require_relative "test_helper"
require "tmpdir"
require "fileutils"

class UndoFileTest < Minitest::Test
  def test_save_and_load_undo_file
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.from_file(id: 1, path: path)
      b.insert_char(0, 5, "!")
      assert b.can_undo?

      b.save_undo_file(undodir)
      assert Dir.exist?(undodir)

      # Create a new buffer from the same file and load undo
      b2 = RuVim::Buffer.from_file(id: 2, path: path)
      refute b2.can_undo?

      b2.load_undo_file(undodir)
      assert b2.can_undo?
      assert b2.undo!
      assert_equal ["hello"], b2.lines
    end
  end

  def test_undo_file_path_uses_hash_of_absolute_path
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      b = RuVim::Buffer.new(id: 1, path: "/tmp/test.txt")
      undo_path = b.undo_file_path(undodir)
      assert undo_path.start_with?(undodir)
      assert_match(/\A[0-9a-f]+\z/, File.basename(undo_path))
    end
  end

  def test_save_undo_file_does_nothing_without_path
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      b = RuVim::Buffer.new(id: 1)
      b.insert_char(0, 0, "a")
      b.save_undo_file(undodir)
      refute Dir.exist?(undodir)
    end
  end

  def test_load_undo_file_does_nothing_without_path
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      b = RuVim::Buffer.new(id: 1)
      b.load_undo_file(undodir)
      refute b.can_undo?
    end
  end

  def test_load_undo_file_ignores_corrupted_file
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.new(id: 1, path: path)
      FileUtils.mkdir_p(undodir)
      undo_path = b.undo_file_path(undodir)
      File.write(undo_path, "garbage data")

      b.load_undo_file(undodir)
      refute b.can_undo?
    end
  end

  def test_load_undo_file_ignores_missing_file
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.new(id: 1, path: path)
      b.load_undo_file(undodir)
      refute b.can_undo?
    end
  end

  def test_save_undo_file_preserves_redo_stack
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.from_file(id: 1, path: path)
      b.insert_char(0, 5, "!")
      b.undo!
      assert b.can_redo?

      b.save_undo_file(undodir)

      b2 = RuVim::Buffer.from_file(id: 2, path: path)
      b2.load_undo_file(undodir)
      assert b2.can_redo?
      assert b2.redo!
      assert_equal ["hello!"], b2.lines
    end
  end

  def test_reload_from_file_removes_undo_file_when_undodir_given
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.from_file(id: 1, path: path)
      b.insert_char(0, 5, "!")
      b.save_undo_file(undodir)

      undo_path = b.undo_file_path(undodir)
      assert File.exist?(undo_path)

      b.reload_from_file!
      refute b.can_undo?
    end
  end

  def test_save_undo_file_with_empty_stacks_removes_file
    Dir.mktmpdir do |dir|
      undodir = File.join(dir, "undo")
      path = File.join(dir, "test.txt")
      File.write(path, "hello\n")

      b = RuVim::Buffer.from_file(id: 1, path: path)
      b.insert_char(0, 5, "!")
      b.save_undo_file(undodir)

      undo_path = b.undo_file_path(undodir)
      assert File.exist?(undo_path)

      b.undo!
      b.save_undo_file(undodir)
      # After undo, there's still a redo stack entry, so file should exist
      assert File.exist?(undo_path)

      # Clear both stacks by reloading
      b.reload_from_file!
      b.save_undo_file(undodir)
      refute File.exist?(undo_path)
    end
  end
end
