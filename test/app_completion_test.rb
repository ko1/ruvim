require_relative "test_helper"
require "tmpdir"

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

  def test_path_completion_respects_wildignore
    Dir.mktmpdir("ruvim-complete") do |dir|
      File.write(File.join(dir, "a.rb"), "")
      File.write(File.join(dir, "a.o"), "")
      @editor.set_option("wildignore", "*.o", scope: :global)

      matches = @app.send(:path_completion_candidates, File.join(dir, "a"))

      assert_includes matches, File.join(dir, "a.rb")
      refute_includes matches, File.join(dir, "a.o")
    end
  end

  def test_command_line_completion_respects_wildmode_list_full_and_wildmenu
    @editor.materialize_intro_buffer!
    @editor.set_option("wildmode", "list,full", scope: :global)
    @editor.set_option("wildmenu", true, scope: :global)

    Dir.mktmpdir("ruvim-wild") do |dir|
      a = File.join(dir, "aa.txt")
      b = File.join(dir, "ab.txt")
      File.write(a, "")
      File.write(b, "")

      @editor.enter_command_line_mode(":")
      cmd = @editor.command_line
      cmd.replace_text("e #{File.join(dir, "a")}")

      @app.send(:command_line_complete)
      first = cmd.text.dup
      first_msg = @editor.message.dup
      @app.send(:command_line_complete)
      second = cmd.text.dup
      second_msg = @editor.message.dup

      assert_equal "e #{File.join(dir, "a")}", first
      refute_equal first, second
      assert_includes first_msg, "aa.txt"
      assert_includes second_msg, "["
      assert([a, b].any? { |p| second.end_with?(p) })
    end
  end

  def test_insert_completion_respects_completeopt_noselect_and_pumheight
    @editor.materialize_intro_buffer!
    @editor.set_option("completeopt", "menu,menuone,noselect", scope: :global)
    @editor.set_option("pumheight", 1, scope: :global)
    b = @editor.current_buffer
    b.replace_all_lines!(["fo", "foobar", "fookey"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 2
    @editor.enter_insert_mode

    @app.send(:handle_insert_key, :ctrl_n)
    assert_equal "fo", b.line_at(0)
    assert_includes @editor.message, "..."

    @app.send(:handle_insert_key, :ctrl_n)
    assert_equal "foobar", b.line_at(0)
  end
end
