require_relative "test_helper"
require "tempfile"

class AppStartupTest < Minitest::Test
  def test_startup_ex_command_runs_after_boot
    app = RuVim::App.new(clean: true, startup_actions: [{ type: :ex, value: "set number" }])
    editor = app.instance_variable_get(:@editor)

    assert_equal true, editor.effective_option("number")
  end

  def test_startup_line_moves_cursor
    Tempfile.create(["ruvim-startup", ".txt"]) do |f|
      f.write("a\nb\nc\nd\n")
      f.flush

      app = RuVim::App.new(path: f.path, clean: true, startup_actions: [{ type: :line, value: 3 }])
      editor = app.instance_variable_get(:@editor)

      assert_equal 2, editor.current_window.cursor_y
      assert_equal "c", editor.current_buffer.line_at(editor.current_window.cursor_y)
    end
  end

  def test_startup_line_end_moves_to_last_line
    Tempfile.create(["ruvim-startup", ".txt"]) do |f|
      f.write("a\nb\nc\n")
      f.flush

      app = RuVim::App.new(path: f.path, clean: true, startup_actions: [{ type: :line_end }])
      editor = app.instance_variable_get(:@editor)

      assert_equal 2, editor.current_window.cursor_y
      assert_equal "c", editor.current_buffer.line_at(editor.current_window.cursor_y)
    end
  end
end
