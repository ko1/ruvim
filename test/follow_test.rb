# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class FollowTest < Minitest::Test
  def create_follow_app
    @tmpfile = Tempfile.new(["follow_test", ".txt"])
    @tmpfile.write("line1\nline2\n")
    @tmpfile.flush
    @path = @tmpfile.path

    @app = RuVim::App.new(path: @path, clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
  end

  def cleanup_follow_app
    return unless @app

    watchers = @app.instance_variable_get(:@follow_watchers)
    watchers.each_value { |w| w.stop rescue nil }
    watchers.clear
    @tmpfile&.close!
  end

  def test_follow_starts_on_file_buffer
    create_follow_app
    @dispatcher.dispatch_ex(@editor, "follow")
    watchers = @app.instance_variable_get(:@follow_watchers)
    buf = @editor.current_buffer

    assert !@editor.message_error?, "Unexpected error: #{@editor.message}"
    assert_equal :live, buf.stream_state
    assert watchers.key?(buf.id)
    assert_includes @editor.message.to_s, "[follow]"
  ensure
    cleanup_follow_app
  end

  def test_follow_stops_on_ctrl_c
    create_follow_app
    @dispatcher.dispatch_ex(@editor, "follow")
    buf = @editor.current_buffer
    assert_equal :live, buf.stream_state

    @app.send(:handle_key, :ctrl_c)
    assert_nil buf.stream_state
    assert_includes @editor.message.to_s, "stopped"
  ensure
    cleanup_follow_app
  end

  def test_follow_toggle_stops
    create_follow_app
    @dispatcher.dispatch_ex(@editor, "follow")
    buf = @editor.current_buffer
    assert_equal :live, buf.stream_state

    @dispatcher.dispatch_ex(@editor, "follow")
    watchers = @app.instance_variable_get(:@follow_watchers)
    assert_nil buf.stream_state
    refute watchers.key?(buf.id)
    assert_includes @editor.message.to_s, "stopped"
  ensure
    cleanup_follow_app
  end

  def test_follow_makes_buffer_not_modifiable
    create_follow_app
    buf = @editor.current_buffer
    assert buf.modifiable?

    @dispatcher.dispatch_ex(@editor, "follow")
    refute buf.modifiable?, "Buffer should not be modifiable during follow"

    @dispatcher.dispatch_ex(@editor, "follow")
    assert buf.modifiable?, "Buffer should be modifiable after follow stops"
  ensure
    cleanup_follow_app
  end

  def test_follow_error_on_modified_buffer
    create_follow_app
    buf = @editor.current_buffer
    buf.modified = true

    @dispatcher.dispatch_ex(@editor, "follow")
    assert_includes @editor.message.to_s, "unsaved changes"
    assert_nil buf.stream_state
  ensure
    cleanup_follow_app
  end

  def test_follow_error_on_no_path_buffer
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @editor.materialize_intro_buffer!
    buf = @editor.current_buffer
    buf.instance_variable_set(:@path, nil)

    @dispatcher.dispatch_ex(@editor, "follow")
    assert_includes @editor.message.to_s, "No file"
  end

  def test_follow_appends_data_from_file
    create_follow_app
    win = @editor.current_window
    buf = @editor.current_buffer
    win.cursor_y = buf.line_count - 1

    @dispatcher.dispatch_ex(@editor, "follow")

    File.open(@path, "a") { |f| f.write("line3\nline4\n") }

    assert_eventually(timeout: 3) do
      @app.send(:drain_stream_events!)
      buf.line_count > 3
    end

    # line2 should NOT be joined with line3
    assert_includes buf.lines, "line2"
    assert_includes buf.lines, "line3"
    assert_includes buf.lines, "line4"
    assert_equal buf.line_count - 1, win.cursor_y
  ensure
    cleanup_follow_app
  end

  def test_follow_no_scroll_when_cursor_not_at_end
    create_follow_app
    buf = @editor.current_buffer
    win = @editor.current_window
    win.cursor_y = 0

    @dispatcher.dispatch_ex(@editor, "follow")

    File.open(@path, "a") { |f| f.write("line3\n") }

    assert_eventually(timeout: 3) do
      @app.send(:drain_stream_events!)
      buf.line_count > 2
    end

    assert_equal 0, win.cursor_y
  ensure
    cleanup_follow_app
  end

  def test_startup_follow_applies_to_all_buffers
    tmp1 = Tempfile.new(["follow_multi1", ".txt"])
    tmp1.write("aaa\n"); tmp1.flush
    tmp2 = Tempfile.new(["follow_multi2", ".txt"])
    tmp2.write("bbb\n"); tmp2.flush

    app = RuVim::App.new(paths: [tmp1.path, tmp2.path], follow: true, clean: true)
    editor = app.instance_variable_get(:@editor)
    watchers = app.instance_variable_get(:@follow_watchers)

    bufs = editor.buffers.values.select(&:file_buffer?)
    assert_equal 2, bufs.size
    bufs.each do |buf|
      assert_equal :live, buf.stream_state, "#{buf.display_name} should be in follow mode"
      assert watchers.key?(buf.id), "#{buf.display_name} should have a watcher"
    end
  ensure
    watchers&.each_value { |w| w.stop rescue nil }
    tmp1&.close!
    tmp2&.close!
  end

  private

  def assert_eventually(timeout: 2, interval: 0.05)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        flunk "Timed out waiting for condition"
      end
      sleep interval
    end
  end
end
