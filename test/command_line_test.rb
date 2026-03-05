require_relative "test_helper"

class CommandLineTest < Minitest::Test
  def setup
    @cl = RuVim::CommandLine.new
  end

  def test_initial_state
    assert_equal ":", @cl.prefix
    assert_equal "", @cl.text
    assert_equal 0, @cl.cursor
  end

  def test_reset_with_custom_prefix
    @cl.reset(prefix: "/")
    assert_equal "/", @cl.prefix
    assert_equal "", @cl.text
    assert_equal 0, @cl.cursor
  end

  def test_insert_appends_at_cursor
    @cl.insert("abc")
    assert_equal "abc", @cl.text
    assert_equal 3, @cl.cursor
  end

  def test_insert_at_middle
    @cl.insert("ac")
    @cl.instance_variable_set(:@cursor, 1)
    @cl.insert("b")
    assert_equal "abc", @cl.text
    assert_equal 2, @cl.cursor
  end

  def test_backspace_at_zero_does_nothing
    @cl.backspace
    assert_equal "", @cl.text
    assert_equal 0, @cl.cursor
  end

  def test_backspace_deletes_character
    @cl.insert("abc")
    @cl.backspace
    assert_equal "ab", @cl.text
    assert_equal 2, @cl.cursor
  end

  def test_move_left
    @cl.insert("abc")
    @cl.move_left
    assert_equal 2, @cl.cursor
  end

  def test_move_left_at_zero_stays
    @cl.move_left
    assert_equal 0, @cl.cursor
  end

  def test_move_right
    @cl.insert("abc")
    @cl.instance_variable_set(:@cursor, 1)
    @cl.move_right
    assert_equal 2, @cl.cursor
  end

  def test_move_right_at_end_stays
    @cl.insert("abc")
    @cl.move_right
    assert_equal 3, @cl.cursor
  end

  def test_content_includes_prefix
    @cl.insert("hello")
    assert_equal ":hello", @cl.content
  end

  def test_content_with_custom_prefix
    @cl.reset(prefix: "/")
    @cl.insert("search")
    assert_equal "/search", @cl.content
  end

  def test_clear_resets_text_and_cursor
    @cl.insert("hello")
    @cl.clear
    assert_equal "", @cl.text
    assert_equal 0, @cl.cursor
    assert_equal ":", @cl.prefix
  end

  def test_replace_text
    @cl.insert("old")
    @cl.replace_text("new text")
    assert_equal "new text", @cl.text
    assert_equal 8, @cl.cursor
  end

  def test_replace_span_end_cursor
    @cl.insert("hello world")
    @cl.replace_span(6, 11, "ruby")
    assert_equal "hello ruby", @cl.text
    assert_equal 10, @cl.cursor
  end

  def test_replace_span_start_cursor
    @cl.insert("hello world")
    @cl.replace_span(6, 11, "ruby", cursor_at: :start)
    assert_equal "hello ruby", @cl.text
    assert_equal 6, @cl.cursor
  end

  def test_replace_span_integer_cursor
    @cl.insert("hello world")
    @cl.replace_span(6, 11, "ruby", cursor_at: 8)
    assert_equal "hello ruby", @cl.text
    assert_equal 8, @cl.cursor
  end
end
