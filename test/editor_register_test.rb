require_relative "test_helper"

class EditorRegisterTest < Minitest::Test
  def test_named_register_and_append_register
    editor = fresh_editor

    editor.set_register("a", text: "foo", type: :charwise)
    assert_equal({ text: "foo", type: :charwise }, editor.get_register("a"))
    assert_equal({ text: "foo", type: :charwise }, editor.get_register("\""))

    editor.set_register("A", text: "bar", type: :charwise)
    assert_equal({ text: "foobar", type: :charwise }, editor.get_register("a"))
    assert_equal({ text: "foobar", type: :charwise }, editor.get_register("\""))
  end

  def test_active_register_is_consumed_once
    editor = fresh_editor
    editor.set_active_register("b")

    assert_equal "b", editor.consume_active_register
    assert_equal "\"", editor.consume_active_register
  end

  def test_detect_filetype_on_opened_buffer
    editor = RuVim::Editor.new
    buffer = editor.add_empty_buffer(path: "/tmp/example.rb")
    assert_equal "ruby", buffer.options["filetype"]
  end
end
