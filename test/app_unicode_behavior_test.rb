require_relative "test_helper"

class AppUnicodeBehaviorTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @editor.materialize_intro_buffer!
    @buffer = @editor.current_buffer
    @win = @editor.current_window
  end

  def press_normal(*keys)
    keys.each { |k| @app.send(:handle_normal_key, k) }
  end

  def press(*keys)
    keys.each { |k| @app.send(:handle_key, k) }
  end

  def test_word_motions_on_japanese_text_do_not_break_character_boundaries
    @buffer.replace_all_lines!(["foo 日本語 編集"])
    @win.cursor_y = 0
    @win.cursor_x = 0

    press_normal("w")
    assert_equal "日", @buffer.line_at(0)[@win.cursor_x]

    press_normal("e")
    assert_equal "語", @buffer.line_at(0)[@win.cursor_x]

    press_normal("w")
    assert_equal "編", @buffer.line_at(0)[@win.cursor_x]

    press_normal("b")
    assert_equal "日", @buffer.line_at(0)[@win.cursor_x]
  end

  def test_paste_charwise_japanese_text_keeps_valid_cursor_position
    @buffer.replace_all_lines!(["abc"])
    @editor.set_register("\"", text: "日本", type: :charwise)
    @win.cursor_y = 0
    @win.cursor_x = 0

    press_normal("p")
    assert_equal "a日本bc", @buffer.line_at(0)
    assert_equal true, @buffer.line_at(0).valid_encoding?
    assert_equal "本", @buffer.line_at(0)[@win.cursor_x]

    press_normal("P")
    assert_equal "a日日本本bc", @buffer.line_at(0)
    assert_equal true, @buffer.line_at(0).valid_encoding?
    assert_equal "本", @buffer.line_at(0)[@win.cursor_x]
  end

  def test_visual_yank_on_japanese_text_is_inclusive_and_valid_utf8
    @buffer.replace_all_lines!(["A日本語B"])
    @win.cursor_x = 1 # 日

    press("v", "l", "y")

    reg = @editor.get_register("\"")
    assert_equal({ text: "日本", type: :charwise }, reg)
    assert_equal true, reg[:text].valid_encoding?
    assert_equal :normal, @editor.mode
  end
end
