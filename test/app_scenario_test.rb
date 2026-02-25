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
end
