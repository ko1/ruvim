require_relative "test_helper"

class EditorMarkTest < Minitest::Test
  def test_local_and_global_marks
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window

    buffer.replace_all_lines!(["  abc", "def"])
    window.cursor_y = 1
    window.cursor_x = 2

    assert editor.set_mark("a")
    assert editor.set_mark("A")

    assert_equal 1, editor.mark_location("a")[:row]
    assert_equal 2, editor.mark_location("A")[:col]
  end

  def test_jump_to_mark_linewise_uses_first_nonblank
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window
    buffer.replace_all_lines!(["  abc"])
    window.cursor_y = 0
    window.cursor_x = 4
    editor.set_mark("a")

    window.cursor_x = 0
    editor.jump_to_mark("a", linewise: true)

    assert_equal 2, window.cursor_x
  end

  def test_jumplist_older_and_newer
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window
    buffer.replace_all_lines!(["a", "b", "c"])
    window.cursor_y = 0
    window.cursor_x = 0
    editor.push_jump_location

    window.cursor_y = 2
    window.cursor_x = 0
    editor.push_jump_location

    editor.jump_older
    assert_equal 0, window.cursor_y

    editor.jump_newer
    assert_equal 2, window.cursor_y
  end

  def test_macro_recording_and_append
    editor = fresh_editor

    assert editor.start_macro_recording("a")
    editor.record_macro_key("i")
    editor.record_macro_key("x")
    editor.stop_macro_recording
    assert_equal %w[i x], editor.macro_keys("a")

    assert editor.start_macro_recording("A")
    editor.record_macro_key("y")
    editor.stop_macro_recording
    assert_equal %w[i x y], editor.macro_keys("a")
  end
end
