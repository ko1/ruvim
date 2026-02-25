require_relative "test_helper"

class AppRegisterTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @editor.materialize_intro_buffer!
    @buffer = @editor.current_buffer
  end

  def press(*keys)
    keys.each { |k| @app.send(:handle_normal_key, k) }
  end

  def test_yy_updates_register_zero
    @buffer.replace_all_lines!(["alpha", "beta"])

    press("y", "y")

    assert_equal({ text: "alpha\n", type: :linewise }, @editor.get_register("0"))
    assert_equal({ text: "alpha\n", type: :linewise }, @editor.get_register("\""))
  end

  def test_dd_rotates_numbered_registers
    @buffer.replace_all_lines!(["one", "two", "three"])

    press("d", "d")
    assert_equal({ text: "one\n", type: :linewise }, @editor.get_register("1"))

    press("d", "d")
    assert_equal({ text: "two\n", type: :linewise }, @editor.get_register("1"))
    assert_equal({ text: "one\n", type: :linewise }, @editor.get_register("2"))
  end

  def test_black_hole_register_does_not_change_unnamed_or_numbered
    @buffer.replace_all_lines!(["one", "two"])

    press("y", "y")
    seed = @editor.get_register("\"")

    press("\"", "_", "d", "d")

    assert_equal seed, @editor.get_register("\"")
    assert_equal({ text: "one\n", type: :linewise }, @editor.get_register("0"))
    assert_nil @editor.get_register("1")
  end
end
