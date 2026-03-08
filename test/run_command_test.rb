# frozen_string_literal: true

require_relative "test_helper"

class RunCommandTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    def write(_data) = nil
  end

  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @key_handler = @app.instance_variable_get(:@key_handler)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @key_handler.handle(k) }
  end

  def buf
    @editor.current_buffer
  end

  def win
    @editor.current_window
  end

  # --- runprg option ---

  def test_runprg_option_exists
    assert_nil @editor.get_option("runprg")
  end

  def test_runprg_set_via_ex
    feed(*":set runprg=ruby\\ -w\\ %".chars, :enter)
    assert_equal "ruby -w %", @editor.get_option("runprg")
  end

  # --- % expansion ---

  def test_expand_run_command_replaces_percent_with_filename
    buf.instance_variable_set(:@path, "/tmp/test.rb")
    gc = RuVim::GlobalCommands.instance
    result = gc.send(:expand_run_command, "ruby -w %", buf)
    assert_equal "ruby -w /tmp/test.rb", result
  end

  def test_expand_run_command_without_percent
    gc = RuVim::GlobalCommands.instance
    result = gc.send(:expand_run_command, "echo hello", buf)
    assert_equal "echo hello", result
  end

  def test_expand_run_command_percent_with_no_path_raises
    gc = RuVim::GlobalCommands.instance
    assert_raises(RuVim::CommandError) do
      gc.send(:expand_run_command, "ruby %", buf)
    end
  end

  # --- :run with args ---

  def test_run_with_args_creates_shell_output_buffer
    feed(*":run echo hello".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf, "Expected [Shell Output] buffer to be created"
    assert output_buf.readonly?
  end

  def test_run_opens_in_horizontal_split
    feed(*":run echo hello".chars, :enter)
    # Should have 2 windows after split
    leaves = @editor.send(:tree_leaves, @editor.layout_tree)
    assert_equal 2, leaves.length, "Expected 2 windows (source + output)"
    # Current window should show the output buffer
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert_equal output_buf.id, @editor.current_window.buffer_id
  end

  def test_run_reuses_existing_output_window
    feed(*":run echo first".chars, :enter)
    leaves_after_first = @editor.send(:tree_leaves, @editor.layout_tree)

    # Focus source window and run again
    feed(*":wincmd w".chars, :enter)
    feed(*":run echo second".chars, :enter)

    leaves_after_second = @editor.send(:tree_leaves, @editor.layout_tree)
    assert_equal leaves_after_first.length, leaves_after_second.length, "Should not create additional splits"
  end

  def test_run_reuses_shell_output_buffer
    feed(*":run echo first".chars, :enter)
    first_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    first_id = first_buf.id

    # Switch to source window and run again
    feed(*":wincmd w".chars, :enter)
    feed(*":run echo second".chars, :enter)
    second_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }

    assert_equal first_id, second_buf.id, "Should reuse the same [Shell Output] buffer"
  end

  # --- :run without args uses runprg ---

  def test_run_no_args_uses_runprg
    buf.instance_variable_set(:@path, "/tmp/test.rb")
    buf.options["runprg"] = "echo %"
    feed(*":run".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf, "Expected [Shell Output] buffer to be created"
  end

  def test_run_no_args_no_runprg_no_history_shows_error
    feed(*":run".chars, :enter)
    assert_match(/runprg/, @editor.message.to_s)
  end

  # --- per-buffer run history ---

  def test_run_remembers_last_command_per_buffer
    buf.instance_variable_set(:@path, "/tmp/test.rb")
    feed(*":run echo test1".chars, :enter)

    # Switch back and run again without args
    feed(*":bprev".chars, :enter)
    feed(*":run".chars, :enter)

    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf
  end

  # --- filetype default runprg ---

  def test_ruby_filetype_sets_default_runprg
    buf.instance_variable_set(:@path, "/tmp/test.rb")
    @editor.send(:assign_filetype, buf, "ruby")
    assert_equal "ruby -w %", buf.options["runprg"]
  end

  def test_python_filetype_sets_default_runprg
    buf.instance_variable_set(:@path, "/tmp/test.py")
    @editor.send(:assign_filetype, buf, "python")
    assert_equal "python3 %", buf.options["runprg"]
  end

  # --- Ctrl-C stops run stream ---

  def test_ctrl_c_on_run_output_buffer_stops_stream
    feed(*":run echo hello".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf

    # Set a stop handler on the buffer and verify it's called
    stop_called = false
    output_buf.stream.stop_handler = -> { stop_called = true }

    @editor.stream_stop_or_cancel!
    assert stop_called, "Expected buffer's stream_stop_handler to be called"
  end

  # --- auto-save before :run ---

  def test_run_auto_saves_modified_buffer
    Tempfile.create(["ruvim-run-save", ".rb"]) do |f|
      f.write("original\n")
      f.flush

      app = RuVim::App.new(path: f.path, clean: true)
      editor = app.instance_variable_get(:@editor)
      kh = app.instance_variable_get(:@key_handler)
      buf = editor.current_buffer

      # Simulate editing
      buf.lines[0] = "modified"
      buf.modified = true

      ":run echo ok".chars.each { |k| kh.handle(k) }
      kh.handle(:enter)

      # File should be saved
      assert_equal "modified", File.read(f.path)
      assert_equal false, buf.modified?
    end
  end

  def test_run_does_not_save_unmodified_buffer
    Tempfile.create(["ruvim-run-nosave", ".rb"]) do |f|
      f.write("original\n")
      f.flush
      mtime_before = File.mtime(f.path)

      app = RuVim::App.new(path: f.path, clean: true)
      kh = app.instance_variable_get(:@key_handler)

      sleep 0.01 # ensure mtime would differ if written
      ":run echo ok".chars.each { |k| kh.handle(k) }
      kh.handle(:enter)

      assert_equal mtime_before, File.mtime(f.path)
    end
  end

  # --- streaming output arrives incrementally ---

  def test_run_streams_output_incrementally
    sh = @app.instance_variable_get(:@stream_handler)
    # Run a command that prints lines with small delays
    cmd = "ruby -e 'STDOUT.sync=true; 3.times{puts _1; sleep 0.1}'"
    feed(*":run #{cmd}".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf, "Expected [Shell Output] buffer"

    # Wait for at least one line to arrive (but not necessarily all)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      sh.drain_events!
      break if output_buf.lines.any? { |l| l.include?("0") }
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        flunk "Timed out waiting for streamed output; lines=#{output_buf.lines.inspect}"
      end
      sleep 0.05
    end

    # Should have received at least the first line while command is still running
    assert_includes output_buf.lines, "0"
  ensure
    output_buf&.stream.stop_handler&.call
  end

  # --- status line shows run command ---

  def test_ctrl_c_key_stops_running_stream
    sh = @app.instance_variable_get(:@stream_handler)
    feed(*":run sleep 10".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf, "Expected [Shell Output] buffer"
    assert_equal :live, output_buf.stream.state, "Buffer should be streaming"
    assert output_buf.stream.stop_handler, "Buffer should have stop handler"

    # Simulate Ctrl-C key press
    feed(:ctrl_c)
    sh.drain_events!

    assert_equal :closed, output_buf.stream.state, "Stream should be stopped after Ctrl-C"
  ensure
    output_buf&.stream.stop_handler&.call rescue nil
  end

  # --- stream_status shows correct label ---

  def test_run_output_stream_status_live
    feed(*":run sleep 10".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert_equal "run", output_buf.stream_status
  ensure
    output_buf&.stream.stop_handler&.call rescue nil
  end

  def test_run_output_stream_status_exit
    feed(*":run echo done".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    sh = @app.instance_variable_get(:@stream_handler)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      sh.drain_events!
      break if output_buf.stream.state == :closed
      flunk "Timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
    assert_match(/\Arun\/exit 0\z/, output_buf.stream_status)
  end

  def test_stdin_stream_status_live
    buf = @editor.current_buffer
    buf.stream = RuVim::Stream::Stdin.new(io: $stdin)
    buf.stream.state = :live
    assert_equal "stdin", buf.stream_status
  end

  def test_stdin_stream_status_closed
    buf = @editor.current_buffer
    buf.stream = RuVim::Stream::Stdin.new(io: $stdin)
    buf.stream.state = :closed
    assert_equal "stdin/EOF", buf.stream_status
  end

  def test_run_stores_command_on_output_buffer
    feed(*":run echo hello".chars, :enter)
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert_equal "echo hello", output_buf.stream_command
  end

  def test_status_line_includes_run_command
    feed(*":run echo hello".chars, :enter)
    term = TerminalStub.new([6, 80])
    screen = RuVim::Screen.new(terminal: term)
    line = screen.send(:status_line, @editor, 80)
    assert_includes line, "echo hello"
    assert_includes line, "[run]"
  end
end
