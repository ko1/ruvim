require_relative "test_helper"

class AppCompletionTest < Minitest::Test
  def setup
    @app = RuVim::App.new
    @editor = @app.instance_variable_get(:@editor)
  end

  def test_app_starts_with_intro_buffer_without_path
    assert_equal :intro, @editor.current_buffer.kind
    assert @editor.current_buffer.readonly?
    refute @editor.current_buffer.modifiable?
  end

  def test_command_line_completion_for_set_option
    @editor.materialize_intro_buffer!
    @editor.enter_command_line_mode(":")
    cmd = @editor.command_line
    cmd.replace_text("set nu")

    @app.send(:command_line_complete)

    assert_equal "set number", cmd.text
  end

  def test_insert_buffer_word_completion_ctrl_n
    @editor.materialize_intro_buffer!
    b = @editor.current_buffer
    b.replace_all_lines!(["fo", "foobar", "fizz"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 2
    @editor.enter_insert_mode

    @app.send(:handle_insert_key, :ctrl_n)

    assert_equal "foobar", b.line_at(0)
    assert_equal 6, @editor.current_window.cursor_x
  end
end
