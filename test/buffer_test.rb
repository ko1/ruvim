require_relative "test_helper"

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
    path = "/tmp/ruvim_buffer_reload_test.txt"
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

  def test_utf8_file_is_loaded_as_utf8_text_not_binary_bytes
    path = "/tmp/ruvim_utf8_test.txt"
    File.binwrite(path, "bar 日本語 編集\n".encode("UTF-8"))

    b = RuVim::Buffer.from_file(id: 1, path: path)
    assert_equal Encoding::UTF_8, b.line_at(0).encoding
    assert_equal "bar 日本語 編集", b.line_at(0)
    assert_equal 10, b.line_length(0)
  end
end
