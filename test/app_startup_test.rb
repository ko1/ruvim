require_relative "test_helper"
require "tempfile"
require "stringio"

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

  def test_startup_readonly_marks_opened_buffer_readonly
    Tempfile.create(["ruvim-startup", ".txt"]) do |f|
      f.write("hello\n")
      f.flush

      app = RuVim::App.new(path: f.path, clean: true, readonly: true)
      editor = app.instance_variable_get(:@editor)

      assert_equal true, editor.current_buffer.readonly?
    end
  end

  def test_startup_nomodifiable_marks_opened_buffer_unmodifiable_and_readonly
    Tempfile.create(["ruvim-startup", ".txt"]) do |f|
      f.write("hello\n")
      f.flush

      app = RuVim::App.new(path: f.path, clean: true, nomodifiable: true)
      editor = app.instance_variable_get(:@editor)

      assert_equal false, editor.current_buffer.modifiable?
      assert_equal true, editor.current_buffer.readonly?
    end
  end

  def test_startup_restricted_mode_sets_editor_flag
    app = RuVim::App.new(clean: true, restricted: true)
    editor = app.instance_variable_get(:@editor)

    assert_equal true, editor.restricted_mode?
  end

  def test_startup_horizontal_split_opens_multiple_files
    Tempfile.create(["ruvim-a", ".txt"]) do |a|
      Tempfile.create(["ruvim-b", ".txt"]) do |b|
        a.write("a\n"); a.flush
        b.write("b\n"); b.flush

        app = RuVim::App.new(paths: [a.path, b.path], clean: true, startup_open_layout: :horizontal)
        editor = app.instance_variable_get(:@editor)

        assert_equal :horizontal, editor.window_layout
        assert_equal 2, editor.window_order.length
        names = editor.window_order.map { |id| editor.buffers[editor.windows[id].buffer_id].path }
        assert_includes names, a.path
        assert_includes names, b.path
      end
    end
  end

  def test_startup_tab_layout_opens_multiple_tabs
    Tempfile.create(["ruvim-a", ".txt"]) do |a|
      Tempfile.create(["ruvim-b", ".txt"]) do |b|
        a.write("a\n"); a.flush
        b.write("b\n"); b.flush

        app = RuVim::App.new(paths: [a.path, b.path], clean: true, startup_open_layout: :tab)
        editor = app.instance_variable_get(:@editor)

        assert_equal 2, editor.tabpage_count
      end
    end
  end

  def test_restricted_mode_disables_ex_ruby
    app = RuVim::App.new(clean: true, restricted: true)
    editor = app.instance_variable_get(:@editor)
    dispatcher = app.instance_variable_get(:@dispatcher)

    dispatcher.dispatch_ex(editor, "ruby 1+1")

    assert_match(/Restricted mode/, editor.message)
  end

  def test_verbose_logs_startup_and_startup_ex_actions
    log = StringIO.new
    app = RuVim::App.new(
      clean: true,
      verbose_level: 2,
      verbose_io: log,
      startup_actions: [{ type: :ex, value: "set number" }]
    )
    editor = app.instance_variable_get(:@editor)
    assert_equal true, editor.effective_option("number")

    text = log.string
    assert_match(/startup: load_user_config/, text)
    assert_match(/startup: run_startup_actions/, text)
    assert_match(/startup ex: set number/, text)
  end

  def test_startuptime_writes_startup_phase_log
    Tempfile.create(["ruvim-startuptime", ".log"]) do |f|
      path = f.path
      f.close

      RuVim::App.new(clean: true, startup_time_path: path)

      text = File.read(path)
      assert_match(/init\.start/, text)
      assert_match(/buffers\.opened/, text)
      assert_match(/startup_actions\.done/, text)
    end
  end
end
