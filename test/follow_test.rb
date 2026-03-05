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

  def test_follow_sets_readonly_and_restores
    create_follow_app
    buf = @editor.current_buffer
    refute buf.readonly?

    @dispatcher.dispatch_ex(@editor, "follow")
    assert buf.readonly?

    @dispatcher.dispatch_ex(@editor, "follow")
    refute buf.readonly?
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
      buf.line_count > 2
    end

    all_text = buf.lines.join("\n")
    assert_includes all_text, "line3"
    assert_includes all_text, "line4"
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
