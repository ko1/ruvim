# frozen_string_literal: true

require_relative "test_helper"

class RunCommandTest < Minitest::Test
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
    # Use a quick command
    feed(*":run echo hello".chars, :enter)
    # Should have switched to Shell Output buffer
    # The buffer may be streaming, so just check it was created
    output_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    assert output_buf, "Expected [Shell Output] buffer to be created"
    assert output_buf.readonly?
  end

  def test_run_reuses_shell_output_buffer
    feed(*":run echo first".chars, :enter)
    first_buf = @editor.buffers.values.find { |b| b.name == "[Shell Output]" }
    first_id = first_buf.id

    # Switch back to original buffer and run again
    feed(*":bprev".chars, :enter)
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

    # Simulate that we're on the output buffer and stream is active
    # In test mode (no stream handler wired), stream_state is already :closed
    # So we test the wiring: Ctrl-C on run_output buffer calls run_stream_stop_handler
    stop_called = false
    @editor.run_stream_stop_handler = -> { stop_called = true; true }
    output_buf.stream_state = :live
    output_buf.instance_variable_set(:@kind, :run_output)

    @editor.stdin_stream_stop_or_cancel!
    assert stop_called, "Expected run_stream_stop_handler to be called"
  end

  # --- status line shows run command ---

  def test_run_shows_command_in_message
    feed(*":run echo hello".chars, :enter)
    # The echo message should contain the command
    assert_match(/echo hello/, @editor.message.to_s)
  end
end
