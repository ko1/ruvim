require_relative "test_helper"

class DispatcherTest < Minitest::Test
  def setup
    @app = RuVim::App.new
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = RuVim::Dispatcher.new
  end

  def test_parse_ex_with_bang_and_args
    parsed = @dispatcher.parse_ex("w! foo.txt")
    assert_equal "w", parsed.name
    assert parsed.bang
    assert_equal ["foo.txt"], parsed.argv
  end

  def test_dispatch_ex_help_sets_message
    @dispatcher.dispatch_ex(@editor, "help")
    assert_equal "[Help] help", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    assert @editor.current_buffer.readonly?
    refute @editor.current_buffer.modifiable?
    assert_includes @editor.current_buffer.lines.join("\n"), "help"
    assert_equal :normal, @editor.mode
  end

  def test_dispatch_ex_help_topic_for_command
    @dispatcher.dispatch_ex(@editor, "help w")
    assert_equal "[Help] w", @editor.message
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, ":w"
    assert_includes body, "Write current buffer"
  end

  def test_dispatch_ex_command_and_ruby
    @dispatcher.dispatch_ex(@editor, "command Hi help")
    assert_equal "Defined :Hi", @editor.message

    @dispatcher.dispatch_ex(@editor, "Hi")
    assert_equal "[Help] help", @editor.message

    @dispatcher.dispatch_ex(@editor, "ruby 1+2")
    assert_equal "ruby: 3", @editor.message
  end

  def test_dispatch_ex_set_commands
    @dispatcher.dispatch_ex(@editor, "set number")
    assert_equal true, @editor.current_window.options["number"]

    @dispatcher.dispatch_ex(@editor, "setlocal tabstop=4")
    assert_equal 4, @editor.current_buffer.options["tabstop"]

    @dispatcher.dispatch_ex(@editor, "setglobal tabstop=8")
    assert_equal 8, @editor.global_options["tabstop"]
    assert_equal 4, @editor.effective_option("tabstop")
  end

  def test_q_closes_current_window_when_multiple_windows_exist
    @editor.split_current_window(layout: :horizontal)
    assert_equal 2, @editor.window_count

    @dispatcher.dispatch_ex(@editor, "q")

    assert_equal 1, @editor.window_count
    assert @editor.running?
    assert_equal "closed window", @editor.message
  end

  def test_q_closes_current_tab_when_multiple_tabs_exist
    @editor.tabnew
    assert_equal 2, @editor.tabpage_count
    assert_equal 1, @editor.window_count

    @dispatcher.dispatch_ex(@editor, "q")

    assert_equal 1, @editor.tabpage_count
    assert @editor.running?
    assert_equal "closed tab", @editor.message
  end

  def test_q_exits_app_when_last_window
    assert_equal 1, @editor.window_count
    assert_equal 1, @editor.tabpage_count

    @dispatcher.dispatch_ex(@editor, "q")

    refute @editor.running?
  end
end
