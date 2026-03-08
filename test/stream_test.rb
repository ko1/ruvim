# frozen_string_literal: true

require_relative "test_helper"

class StreamTest < Minitest::Test
  # --- Stream::Stdin ---

  def test_stdin_status_live
    s = RuVim::Stream::Stdin.new(io: $stdin)
    s.state = :live
    assert_equal "stdin", s.status
  end

  def test_stdin_status_closed
    s = RuVim::Stream::Stdin.new(io: $stdin)
    s.state = :closed
    assert_equal "stdin/EOF", s.status
  end

  def test_stdin_status_error
    s = RuVim::Stream::Stdin.new(io: $stdin)
    s.state = :error
    assert_equal "stdin/error", s.status
  end

  def test_stdin_status_nil_when_not_started
    s = RuVim::Stream::Stdin.new(io: $stdin)
    assert_nil s.status
  end

  def test_stdin_command_is_nil
    s = RuVim::Stream::Stdin.new(io: $stdin)
    assert_nil s.command
  end

  # --- Stream::Run ---

  def test_run_status_live
    s = RuVim::Stream::Run.new(command: "echo hello")
    s.state = :live
    assert_equal "run", s.status
  end

  def test_run_status_closed_with_exit
    s = RuVim::Stream::Run.new(command: "echo hello")
    s.state = :closed
    s.exit_status = Struct.new(:exitstatus).new(0)
    assert_equal "run/exit 0", s.status
  end

  def test_run_status_closed_no_exit
    s = RuVim::Stream::Run.new(command: "echo hello")
    s.state = :closed
    assert_equal "run/EOF", s.status
  end

  def test_run_status_error
    s = RuVim::Stream::Run.new(command: "echo hello")
    s.state = :error
    assert_equal "run/error", s.status
  end

  def test_run_command
    s = RuVim::Stream::Run.new(command: "echo hello")
    assert_equal "echo hello", s.command
  end

  # --- Stream::Follow ---

  def test_follow_status_live
    s = RuVim::Stream::Follow.new
    s.state = :live
    assert_equal "follow", s.status
  end

  def test_follow_status_live_inotify
    s = RuVim::Stream::Follow.new
    s.state = :live
    s.backend = :inotify
    assert_equal "follow/i", s.status
  end

  def test_follow_status_error
    s = RuVim::Stream::Follow.new
    s.state = :error
    assert_equal "follow/error", s.status
  end

  def test_follow_status_nil_when_stopped
    s = RuVim::Stream::Follow.new
    assert_nil s.status
  end

  def test_follow_command_is_nil
    s = RuVim::Stream::Follow.new
    assert_nil s.command
  end

  # --- Stream::FileLoad ---

  def test_file_load_status_live
    s = RuVim::Stream::FileLoad.new
    s.state = :live
    assert_equal "load", s.status
  end

  def test_file_load_status_error
    s = RuVim::Stream::FileLoad.new
    s.state = :error
    assert_equal "load/error", s.status
  end

  def test_file_load_status_nil_when_closed
    s = RuVim::Stream::FileLoad.new
    s.state = :closed
    assert_nil s.status
  end

  # --- Stream::Git ---

  def test_git_status_always_nil
    s = RuVim::Stream::Git.new
    assert_nil s.status
    s.state = :live
    assert_nil s.status
  end

  # --- common ---

  def test_live_predicate
    s = RuVim::Stream::Run.new(command: "test")
    refute s.live?
    s.state = :live
    assert s.live?
    s.state = :closed
    refute s.live?
  end

  def test_stop_transitions_run_to_closed
    s = RuVim::Stream::Run.new(command: "echo hello")
    s.state = :live
    s.stop!
    assert_equal :closed, s.state
  end

  def test_stop_transitions_follow_to_nil
    s = RuVim::Stream::Follow.new
    s.state = :live
    s.stop!
    assert_nil s.state
  end

  def test_stop_transitions_stdin_to_closed
    r, _w = IO.pipe
    s = RuVim::Stream::Stdin.new(io: r)
    s.state = :live
    s.stop!
    assert_equal :closed, s.state
  ensure
    r&.close rescue nil
    _w&.close rescue nil
  end

  def test_buffer_stream_status_delegates
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!
    buf = editor.current_buffer
    buf.stream = RuVim::Stream::Run.new(command: "echo test")
    buf.stream.state = :live
    assert_equal "run", buf.stream_status
    assert_equal "echo test", buf.stream_command
  end

  def test_buffer_stream_status_nil_without_stream
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!
    buf = editor.current_buffer
    assert_nil buf.stream_status
    assert_nil buf.stream_command
  end
end
