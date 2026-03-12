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

  def test_jump_older_at_beginning_stays_at_first
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window
    buffer.replace_all_lines!(["a", "b", "c"])

    window.cursor_y = 0
    editor.push_jump_location
    window.cursor_y = 2
    editor.push_jump_location

    # Jump older twice — should clamp at index 0
    editor.jump_older
    editor.jump_older
    assert_equal 0, window.cursor_y

    # Another jump_older should stay at 0
    editor.jump_older
    assert_equal 0, window.cursor_y
  end

  def test_jump_newer_at_end_returns_nil
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window
    buffer.replace_all_lines!(["a", "b"])

    window.cursor_y = 0
    editor.push_jump_location
    window.cursor_y = 1
    editor.push_jump_location

    # Already at newest — jump_newer returns nil
    assert_nil editor.jump_newer
  end

  def test_jump_older_on_empty_jumplist
    editor = fresh_editor
    assert_nil editor.jump_older
  end

  def test_jump_newer_on_empty_jumplist
    editor = fresh_editor
    assert_nil editor.jump_newer
  end

  def test_push_jump_location_deduplicates_same_location
    editor = fresh_editor
    buffer = editor.current_buffer
    window = editor.current_window
    buffer.replace_all_lines!(["a", "b"])

    window.cursor_y = 0
    window.cursor_x = 0
    editor.push_jump_location
    editor.push_jump_location
    editor.push_jump_location

    # Should not duplicate identical locations
    # jump_older from current should go to index 0, which is row 0
    window.cursor_y = 1
    editor.push_jump_location
    editor.jump_older
    assert_equal 0, window.cursor_y
  end

  def test_normalize_location_with_invalid_input
    editor = fresh_editor
    # normalize_location is private; test indirectly via jump_to_location
    assert_nil editor.jump_to_location(nil)
    assert_nil editor.jump_to_location({})
  end

  def test_set_mark_rejects_invalid_names
    editor = fresh_editor
    refute editor.set_mark("1")
    refute editor.set_mark("!")
    refute editor.set_mark("")
    assert_nil editor.mark_location("1")
  end

  def test_first_nonblank_col_all_spaces
    editor = fresh_editor
    buffer = editor.current_buffer
    buffer.replace_all_lines!(["   "])
    window = editor.current_window
    window.cursor_y = 0
    window.cursor_x = 2
    editor.set_mark("a")

    window.cursor_x = 0
    editor.jump_to_mark("a", linewise: true)
    # All spaces → first_nonblank_col returns 0
    assert_equal 0, window.cursor_x
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
