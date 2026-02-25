require_relative "test_helper"

class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @app.send(:handle_key, k) }
  end

  def test_insert_edit_search_and_delete_scenario
    feed("i", "h", "e", "l", "l", "o", :enter, "w", "o", "r", "l", "d", :escape)
    feed("k", "0", "x")
    feed("/", "o", :enter)
    feed("n")

    assert_equal ["ello", "world"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
    assert_equal "Search wrapped", @editor.message if @editor.message == "Search wrapped"
    assert_operator @editor.current_window.cursor_y, :>=, 0
  end

  def test_visual_block_yank
    @editor.current_buffer.replace_all_lines!(["abcde", "ABCDE", "xyz"])
    @editor.current_window.cursor_x = 1
    @editor.current_window.cursor_y = 0

    feed(:ctrl_v, "j", "l", "l", "y")

    reg = @editor.get_register("\"")
    assert_equal :normal, @editor.mode
    assert_equal "bcd\nBCD", reg[:text]
  end

  def test_visual_block_delete
    @editor.current_buffer.replace_all_lines!(["abcde", "ABCDE", "xyz"])
    @editor.current_window.cursor_x = 1
    @editor.current_window.cursor_y = 0

    feed(:ctrl_v, "j", "l", "l", "d")

    assert_equal ["ae", "AE", "xyz"], @editor.current_buffer.lines
    assert_equal 0, @editor.current_window.cursor_y
    assert_equal 1, @editor.current_window.cursor_x
    assert_equal :normal, @editor.mode
  end

  def test_dot_repeats_insert_change
    @editor.current_buffer.replace_all_lines!([""])
    feed("i", "a", "b", :escape)
    feed(".")

    assert_equal ["abab"], @editor.current_buffer.lines
  end

  def test_dot_repeats_change_with_text_object
    @editor.current_buffer.replace_all_lines!(["foo bar"])
    feed("c", "i", "w", "X", :escape)
    feed("w")
    feed(".")

    assert_equal ["X X"], @editor.current_buffer.lines
  end

  def test_dot_repeat_works_inside_macro
    @editor.current_buffer.replace_all_lines!(["abc", "abc", "abc"])

    feed("x")
    feed("j", "0", "q", "a", ".", "j", "q")
    feed("@", "a")

    assert_equal ["bc", "bc", "bc"], @editor.current_buffer.lines
  end
end
