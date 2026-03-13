require_relative "test_helper"
require "tmpdir"

class BufferTest < Minitest::Test
  def test_insert_and_undo_redo_group
    b = RuVim::Buffer.new(id: 1)
    b.begin_change_group
    b.insert_char(0, 0, "a")
    b.insert_char(0, 1, "b")
    b.end_change_group

    assert_equal ["ab"], b.lines
    assert b.undo!
    assert_equal [""], b.lines
    assert b.redo!
    assert_equal ["ab"], b.lines
  end

  def test_delete_span_across_lines
    b = RuVim::Buffer.new(id: 1, lines: ["abc", "def", "ghi"])
    deleted = b.span_text(0, 1, 2, 1)
    assert_equal "bc\ndef\ng", deleted

    b.delete_span(0, 1, 2, 1)
    assert_equal ["ahi"], b.lines
  end

  def test_reload_from_file_clears_modified_and_history
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ruvim_buffer_reload_test.txt")
      File.write(path, "one\n")
      b = RuVim::Buffer.from_file(id: 1, path: path)
      b.insert_char(0, 0, "X")
      assert b.modified?
      assert b.can_undo?

      b.reload_from_file!
      assert_equal ["one"], b.lines
      refute b.modified?
      refute b.can_undo?
    end
  end

  def test_from_file_rejects_non_regular_file
    Dir.mktmpdir do |dir|
      fifo_path = File.join(dir, "test_fifo")
      system("mkfifo", fifo_path)
      assert File.exist?(fifo_path), "FIFO should exist"

      err = assert_raises(RuVim::CommandError) do
        RuVim::Buffer.from_file(id: 1, path: fifo_path)
      end
      assert_match(/Not a regular file/, err.message)
    end
  end

  def test_reload_rejects_non_regular_file
    b = RuVim::Buffer.new(id: 1, path: "/dev/null")
    # /dev/null exists but is not a regular file on Linux
    if !File.file?("/dev/null") && File.exist?("/dev/null")
      err = assert_raises(RuVim::CommandError) do
        b.reload_from_file!("/dev/null")
      end
      assert_match(/Not a regular file/, err.message)
    end
  end

  def test_utf8_file_is_loaded_as_utf8_text_not_binary_bytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ruvim_utf8_test.txt")
      File.binwrite(path, "bar 日本語 編集\n".encode("UTF-8"))

      b = RuVim::Buffer.from_file(id: 1, path: path)
      assert_equal Encoding::UTF_8, b.line_at(0).encoding
      assert_equal "bar 日本語 編集", b.line_at(0)
      assert_equal 10, b.line_length(0)
    end
  end

  def test_invalid_bytes_are_decoded_to_valid_utf8_with_replacement
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ruvim_invalid_bytes_test.txt")
      File.binwrite(path, "A\xFFB\n".b)

      b = RuVim::Buffer.from_file(id: 1, path: path)
      line = b.line_at(0)
      assert_equal Encoding::UTF_8, line.encoding
      assert_equal true, line.valid_encoding?
      assert_match(/A.*B/, line)
    end
  end

  def test_write_to_saves_utf8_text
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ruvim_write_utf8_test.txt")
      b = RuVim::Buffer.new(id: 1, lines: ["日本語", "abc"])
      b.write_to(path)

      data = File.binread(path)
      text = data.force_encoding(Encoding::UTF_8)
      assert_equal true, text.valid_encoding?
      assert_equal "日本語\nabc", text
    end
  end

  def test_append_stream_text_updates_lines_without_marking_modified
    b = RuVim::Buffer.new(id: 1, lines: [""])
    b.append_stream_text!("a\n")
    b.append_stream_text!("b")
    b.append_stream_text!("\n\nc\n")

    assert_equal ["a", "b", "", "c", ""], b.lines
    refute b.modified?
  end

  # --- Undo snapshot structural sharing tests ---

  def test_undo_snapshot_shares_unchanged_line_objects
    b = RuVim::Buffer.new(id: 1, lines: ["aaa", "bbb", "ccc"])
    original_bbb = b.lines[1]
    original_ccc = b.lines[2]

    # Modify only line 0
    b.insert_char(0, 0, "X")
    assert_equal "Xaaa", b.lines[0]

    # Undo restores original content
    b.undo!
    assert_equal ["aaa", "bbb", "ccc"], b.lines

    # Unchanged lines should share the same object (structural sharing)
    assert_same original_bbb, b.lines[1], "unchanged line 'bbb' should be the same object"
    assert_same original_ccc, b.lines[2], "unchanged line 'ccc' should be the same object"
  end

  def test_undo_redo_with_structural_sharing_preserves_content
    b = RuVim::Buffer.new(id: 1, lines: ["hello", "world"])

    # Multiple modifications
    b.insert_char(0, 5, "!")
    assert_equal ["hello!", "world"], b.lines

    b.insert_char(1, 5, "?")
    assert_equal ["hello!", "world?"], b.lines

    # Undo both
    b.undo!
    assert_equal ["hello!", "world"], b.lines
    b.undo!
    assert_equal ["hello", "world"], b.lines

    # Redo both
    b.redo!
    assert_equal ["hello!", "world"], b.lines
    b.redo!
    assert_equal ["hello!", "world?"], b.lines
  end

  def test_change_group_undo_with_structural_sharing
    b = RuVim::Buffer.new(id: 1, lines: ["aaa", "bbb", "ccc"])
    original_ccc = b.lines[2]

    b.begin_change_group
    b.insert_char(0, 0, "X")
    b.insert_char(1, 0, "Y")
    b.end_change_group

    assert_equal ["Xaaa", "Ybbb", "ccc"], b.lines

    b.undo!
    assert_equal ["aaa", "bbb", "ccc"], b.lines
    assert_same original_ccc, b.lines[2], "unchanged line 'ccc' should be the same object after group undo"
  end

  def test_undo_after_delete_line_with_structural_sharing
    b = RuVim::Buffer.new(id: 1, lines: ["aaa", "bbb", "ccc"])
    original_aaa = b.lines[0]
    original_ccc = b.lines[2]

    b.delete_line(1)
    assert_equal ["aaa", "ccc"], b.lines

    b.undo!
    assert_equal ["aaa", "bbb", "ccc"], b.lines
    assert_same original_aaa, b.lines[0], "line 'aaa' should be the same object"
    assert_same original_ccc, b.lines[2], "line 'ccc' should be the same object"
  end

  def test_undo_after_insert_newline_with_structural_sharing
    b = RuVim::Buffer.new(id: 1, lines: ["hello", "world"])
    original_world = b.lines[1]

    b.insert_newline(0, 3)
    assert_equal ["hel", "lo", "world"], b.lines

    b.undo!
    assert_equal ["hello", "world"], b.lines
    assert_same original_world, b.lines[1], "unchanged line 'world' should be the same object"
  end
end
