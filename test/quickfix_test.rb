# frozen_string_literal: true

require_relative "test_helper"

class QuickfixTest < Minitest::Test
  def setup
    @editor = fresh_editor
  end

  # --- Quickfix list ---

  def test_set_quickfix_list
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "first" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 5, text: "second" }
    ]
    @editor.set_quickfix_list(items)

    assert_equal 2, @editor.quickfix_items.length
    assert_equal "first", @editor.quickfix_items[0][:text]
    assert_nil @editor.quickfix_index
  end

  def test_set_quickfix_list_empty
    @editor.set_quickfix_list([])
    assert_empty @editor.quickfix_items
    assert_nil @editor.quickfix_index
  end

  def test_move_quickfix_forward
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" }
    ]
    @editor.set_quickfix_list(items)

    item = @editor.move_quickfix(1)
    assert_equal 0, @editor.quickfix_index
    assert_equal "a", item[:text]

    item = @editor.move_quickfix(1)
    assert_equal 1, @editor.quickfix_index
    assert_equal "b", item[:text]
  end

  def test_move_quickfix_backward
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" }
    ]
    @editor.set_quickfix_list(items)

    item = @editor.move_quickfix(-1)
    assert_equal 1, @editor.quickfix_index
    assert_equal "b", item[:text]
  end

  def test_move_quickfix_wraps
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" }
    ]
    @editor.set_quickfix_list(items)

    @editor.move_quickfix(1) # index 0
    @editor.move_quickfix(1) # index 1
    item = @editor.move_quickfix(1) # wraps to 0
    assert_equal 0, @editor.quickfix_index
    assert_equal "a", item[:text]
  end

  def test_move_quickfix_empty_returns_nil
    @editor.set_quickfix_list([])
    assert_nil @editor.move_quickfix(1)
  end

  def test_select_quickfix
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" },
      { buffer_id: @editor.current_buffer.id, row: 2, col: 0, text: "c" }
    ]
    @editor.set_quickfix_list(items)

    item = @editor.select_quickfix(1)
    assert_equal 1, @editor.quickfix_index
    assert_equal "b", item[:text]
  end

  def test_select_quickfix_clamps
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" }
    ]
    @editor.set_quickfix_list(items)

    item = @editor.select_quickfix(99)
    assert_equal 0, @editor.quickfix_index
    assert_equal "a", item[:text]
  end

  def test_current_quickfix_item_nil_when_no_index
    items = [{ buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" }]
    @editor.set_quickfix_list(items)
    assert_nil @editor.current_quickfix_item
  end

  # --- Location list ---

  def test_set_location_list
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "loc1" }
    ]
    @editor.set_location_list(items)

    assert_equal 1, @editor.location_items.length
    assert_equal "loc1", @editor.location_items[0][:text]
  end

  def test_move_location_list
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" }
    ]
    @editor.set_location_list(items)

    item = @editor.move_location_list(1)
    assert_equal "a", item[:text]

    item = @editor.move_location_list(1)
    assert_equal "b", item[:text]
  end

  def test_move_location_list_empty_returns_nil
    @editor.set_location_list([])
    assert_nil @editor.move_location_list(1)
  end

  def test_select_location_list
    items = [
      { buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "a" },
      { buffer_id: @editor.current_buffer.id, row: 1, col: 0, text: "b" }
    ]
    @editor.set_location_list(items)

    item = @editor.select_location_list(1)
    assert_equal "b", item[:text]
  end

  def test_location_list_per_window
    items1 = [{ buffer_id: @editor.current_buffer.id, row: 0, col: 0, text: "win1" }]
    @editor.set_location_list(items1)

    win_id = @editor.current_window.id
    assert_equal "win1", @editor.location_items(win_id)[0][:text]
  end
end
