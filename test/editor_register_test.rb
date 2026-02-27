require_relative "test_helper"
require "tmpdir"

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

  def test_black_hole_register_discards_explicit_write
    editor = fresh_editor
    editor.set_register("\"", text: "keep", type: :charwise)

    editor.set_register("_", text: "drop", type: :charwise)

    assert_equal({ text: "keep", type: :charwise }, editor.get_register("\""))
    assert_nil editor.get_register("_")
  end

  def test_operator_register_updates_yank_zero_and_delete_numbered
    editor = fresh_editor

    editor.store_operator_register("\"", text: "yank", type: :charwise, kind: :yank)
    assert_equal({ text: "yank", type: :charwise }, editor.get_register("\""))
    assert_equal({ text: "yank", type: :charwise }, editor.get_register("0"))

    editor.store_operator_register("\"", text: "del1", type: :charwise, kind: :delete)
    editor.store_operator_register("\"", text: "del2", type: :linewise, kind: :delete)
    assert_equal({ text: "del2", type: :linewise }, editor.get_register("1"))
    assert_equal({ text: "del1", type: :charwise }, editor.get_register("2"))
    assert_equal({ text: "yank", type: :charwise }, editor.get_register("0"))
  end

  def test_black_hole_skips_auto_operator_registers
    editor = fresh_editor
    editor.store_operator_register("\"", text: "seed", type: :charwise, kind: :yank)

    editor.store_operator_register("_", text: "drop", type: :charwise, kind: :delete)

    assert_equal({ text: "seed", type: :charwise }, editor.get_register("\""))
    assert_equal({ text: "seed", type: :charwise }, editor.get_register("0"))
    assert_nil editor.get_register("1")
  end

  def test_detect_filetype_on_opened_buffer
    editor = RuVim::Editor.new
    buffer = editor.add_empty_buffer(path: "/tmp/example.rb")
    assert_equal "ruby", buffer.options["filetype"]
  end

  def test_detect_filetype_from_shebang_when_extension_is_missing
    editor = RuVim::Editor.new
    Dir.mktmpdir("ruvim-shebang-ft") do |dir|
      path = File.join(dir, "script")
      File.binwrite(path, "#!/usr/bin/env ruby\nputs :ok\n")

      buffer = editor.add_buffer_from_file(path)
      assert_equal "ruby", buffer.options["filetype"]
    end
  end

  def test_detect_filetype_from_env_shebang_with_dash_s
    editor = RuVim::Editor.new
    Dir.mktmpdir("ruvim-shebang-envs") do |dir|
      path = File.join(dir, "tool")
      File.binwrite(path, "#!/usr/bin/env -S python3 -u\nprint('ok')\n")

      buffer = editor.add_buffer_from_file(path)
      assert_equal "python", buffer.options["filetype"]
    end
  end
end
