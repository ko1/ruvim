# frozen_string_literal: true

require_relative "test_helper"

class StreamTest < Minitest::Test
  def make_queue
    Queue.new
  end

  def noop
    -> {}
  end

  # --- Stream::Stdin ---

  def test_stdin_starts_live
    r, w = IO.pipe
    s = RuVim::Stream::Stdin.new(io: r, buffer_id: 1, queue: make_queue, &noop)
    assert_equal :live, s.state
    assert_equal "stdin", s.status
  ensure
    s&.stop!
    w&.close rescue nil
  end

  def test_stdin_status_closed
    r, w = IO.pipe
    s = RuVim::Stream::Stdin.new(io: r, buffer_id: 1, queue: make_queue, &noop)
    s.stop!
    assert_equal :closed, s.state
    assert_equal "stdin/EOF", s.status
  ensure
    w&.close rescue nil
  end

  def test_stdin_command_is_nil
    r, w = IO.pipe
    s = RuVim::Stream::Stdin.new(io: r, buffer_id: 1, queue: make_queue, &noop)
    assert_nil s.command
  ensure
    s&.stop!
    w&.close rescue nil
  end

  # --- Stream::Run ---

  def test_run_starts_live
    q = make_queue
    s = RuVim::Stream::Run.new(command: "echo hello", buffer_id: 1, queue: q, &noop)
    assert_equal :live, s.state
    assert_equal "run", s.status
    assert_equal "echo hello", s.command
  ensure
    s&.stop!
  end

  def test_run_status_closed_with_exit
    q = make_queue
    s = RuVim::Stream::Run.new(command: "echo hello", buffer_id: 1, queue: q, &noop)
    s.stop!
    s.exit_status = Struct.new(:exitstatus).new(0)
    assert_equal "run/exit 0", s.status
  end

  def test_run_status_error
    q = make_queue
    s = RuVim::Stream::Run.new(command: "echo hello", buffer_id: 1, queue: q, &noop)
    s.state = :error
    assert_equal "run/error", s.status
  ensure
    s&.stop!
  end

  # --- Stream::Follow ---

  def test_follow_starts_live
    Tempfile.create(["stream_test", ".txt"]) do |f|
      f.write("test\n"); f.flush
      s = RuVim::Stream::Follow.new(path: f.path, buffer_id: 1, queue: make_queue, &noop)
      assert_equal :live, s.state
      assert_match(/\Afollow/, s.status)
      assert_nil s.command
    ensure
      s&.stop!
    end
  end

  def test_follow_stop_clears_state
    Tempfile.create(["stream_test", ".txt"]) do |f|
      f.write("test\n"); f.flush
      s = RuVim::Stream::Follow.new(path: f.path, buffer_id: 1, queue: make_queue, &noop)
      s.stop!
      assert_nil s.state
      assert_nil s.status
    end
  end

  # --- Stream::FileLoad ---

  def test_file_load_starts_live
    Tempfile.create(["stream_test", ".txt"]) do |f|
      f.write("data\n"); f.flush
      io = File.open(f.path, "rb")
      s = RuVim::Stream::FileLoad.new(io: io, file_size: f.size, buffer_id: 1, queue: make_queue, &noop)
      assert_equal :live, s.state
      assert_equal "load", s.status
    ensure
      s&.stop!
    end
  end

  def test_file_load_status_error
    Tempfile.create(["stream_test", ".txt"]) do |f|
      f.write("data\n"); f.flush
      io = File.open(f.path, "rb")
      s = RuVim::Stream::FileLoad.new(io: io, file_size: f.size, buffer_id: 1, queue: make_queue, &noop)
      s.state = :error
      assert_equal "load/error", s.status
    ensure
      s&.stop!
    end
  end

  # --- Stream::Git ---

  def test_git_status_always_nil
    q = make_queue
    s = RuVim::Stream::Git.new(cmd: ["echo", "test"], root: ".", buffer_id: 1, queue: q, &noop)
    assert_nil s.status
  ensure
    s&.stop!
  end

  # --- common ---

  def test_live_predicate
    q = make_queue
    s = RuVim::Stream::Run.new(command: "sleep 10", buffer_id: 1, queue: q, &noop)
    assert s.live?
    s.stop!
    refute s.live?
  end

  def test_buffer_stream_status_delegates
    q = make_queue
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!
    buf = editor.current_buffer
    buf.stream = RuVim::Stream::Run.new(command: "echo test", buffer_id: buf.id, queue: q, &noop)
    assert_equal "run", buf.stream_status
    assert_equal "echo test", buf.stream_command
  ensure
    buf&.stream&.stop!
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
