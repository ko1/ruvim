require_relative "test_helper"
require "tmpdir"

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

  def test_dispatch_ex_bindings_lists_buffer_filetype_and_app_layers
    keymaps = @app.instance_variable_get(:@keymaps)
    @editor.current_buffer.options["filetype"] = "ruby"
    keymaps.bind_buffer(@editor.current_buffer.id, "Q", "ui.clear_message")
    keymaps.bind_filetype("ruby", "K", "cursor.up", mode: :normal)

    @dispatcher.dispatch_ex(@editor, "bindings")

    assert_equal "[Bindings]", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "Layer: buffer"
    assert_includes body, "Layer: filetype"
    assert_includes body, "Layer: app"
    assert_operator body.index("Layer: buffer"), :<, body.index("Layer: filetype")
    assert_operator body.index("Layer: filetype"), :<, body.index("Layer: app")
    assert_includes body, "Q"
    assert_includes body, "K"
    assert_includes body, "gg"
    assert_includes body, "f"
    assert_includes body, "normal.find_char_forward_start"
    assert_includes body, "Move to start of buffer"
    assert_includes body, "Start char find forward"
    assert_includes body, "Clear message"
  end

  def test_dispatch_ex_bindings_sort_command_sorts_within_group_by_command_id
    keymaps = @app.instance_variable_get(:@keymaps)
    keymaps.bind_buffer(@editor.current_buffer.id, "K", "ui.clear_message")
    keymaps.bind_buffer(@editor.current_buffer.id, "Q", "cursor.up")

    @dispatcher.dispatch_ex(@editor, "bindings sort=command")

    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "Sort: command"

    buffer_section = body.split("Layer: buffer", 2).last
    refute_nil buffer_section
    buffer_section = buffer_section.split("Layer: app", 2).first.to_s

    up_idx = buffer_section.index("cursor.up")
    clear_idx = buffer_section.index("ui.clear_message")
    refute_nil up_idx
    refute_nil clear_idx
    assert_operator up_idx, :<, clear_idx
  end

  def test_dispatch_ex_command_and_ruby
    @dispatcher.dispatch_ex(@editor, "command Hi help")
    assert_equal "Defined :Hi", @editor.message

    @dispatcher.dispatch_ex(@editor, "Hi")
    assert_equal "[Help] help", @editor.message

    @dispatcher.dispatch_ex(@editor, "ruby 1+2")
    assert_equal "ruby: 3", @editor.message
  end

  def test_dispatch_ex_commands_shows_description_and_bound_keys
    keymaps = @app.instance_variable_get(:@keymaps)
    keymaps.bind(:normal, "K", "editor.buffer_next")

    @dispatcher.dispatch_ex(@editor, "commands")

    assert_equal "[Commands]", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "bnext"
    assert_includes body, "Next buffer"
    assert_includes body, "keys: K"
  end

  def test_dispatch_ex_ruby_captures_stdout_and_stderr_into_virtual_buffer
    @dispatcher.dispatch_ex(@editor, "ruby STDOUT.puts(%q[out]); STDERR.puts(%q[err]); 42")

    assert_equal "[Ruby Output]", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "[stdout]"
    assert_includes body, "out"
    assert_includes body, "[stderr]"
    assert_includes body, "err"
    assert_includes body, "[result]"
    assert_includes body, "42"
  end

  def test_dispatch_ex_shell_captures_stdout_and_stderr_into_virtual_buffer
    @dispatcher.dispatch_ex(@editor, "!echo out; echo err 1>&2")

    assert_equal "[Shell Output]", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "[command]"
    assert_includes body, "echo out; echo err 1>&2"
    assert_includes body, "[stdout]"
    assert_includes body, "out"
    assert_includes body, "[stderr]"
    assert_includes body, "err"
    assert_includes body, "[status]"
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

  def test_dispatch_ex_error_marks_message_as_error
    @dispatcher.dispatch_ex(@editor, "no_such_command")

    assert_match(/Error:/, @editor.message)
    assert_equal true, @editor.message_error?
  end

  def test_vimgrep_populates_quickfix_and_cnext_moves
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "bar foo", "baz"])
    @dispatcher.dispatch_ex(@editor, "vimgrep /foo/")

    assert_equal 2, @editor.quickfix_items.length
    assert_equal 0, @editor.current_window.cursor_y

    @dispatcher.dispatch_ex(@editor, "cnext")
    assert_equal 1, @editor.current_window.cursor_y

    @dispatcher.dispatch_ex(@editor, "copen")
    qf_windows = @editor.find_window_ids_by_buffer_kind(:quickfix)
    refute_empty qf_windows
  end

  def test_lvimgrep_populates_location_list_and_lnext_moves
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["aa", "bb aa", "cc aa"])
    wid = @editor.current_window_id

    @dispatcher.dispatch_ex(@editor, "lvimgrep /aa/")
    assert_equal 3, @editor.location_items(wid).length

    @dispatcher.dispatch_ex(@editor, "lnext")
    assert_equal 1, @editor.current_window.cursor_y
  end

  def test_hidden_option_allows_buffer_switch_without_bang
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["x"])
    @editor.current_buffer.modified = true
    other = @editor.add_empty_buffer(path: "other.txt")
    @editor.set_option("hidden", true, scope: :global)

    @dispatcher.dispatch_ex(@editor, "buffer #{other.id}")

    assert_equal other.id, @editor.current_buffer.id
    refute @editor.message_error?
  end

  def test_autowrite_saves_current_buffer_before_buffer_switch
    Dir.mktmpdir("ruvim-autowrite") do |dir|
      path = File.join(dir, "a.txt")
      File.write(path, "old\n")
      @editor.materialize_intro_buffer!
      @editor.current_buffer.path = path
      @editor.current_buffer.replace_all_lines!(["new"])
      @editor.current_buffer.modified = true
      other = @editor.add_empty_buffer(path: "other.txt")
      @editor.set_option("autowrite", true, scope: :global)

      @dispatcher.dispatch_ex(@editor, "buffer #{other.id}")

      assert_equal other.id, @editor.current_buffer.id
      assert_equal "new", File.read(path).strip
    end
  end

  def test_bdelete_deletes_current_buffer_and_switches_to_another
    @editor.materialize_intro_buffer!
    first = @editor.current_buffer
    other = @editor.add_empty_buffer(path: "other.txt")
    @dispatcher.dispatch_ex(@editor, "buffer #{other.id}")
    assert_equal other.id, @editor.current_buffer.id

    @dispatcher.dispatch_ex(@editor, "bd")

    assert_equal first.id, @editor.current_buffer.id
    refute @editor.buffers.key?(other.id)
    assert_equal "buffer #{other.id} deleted", @editor.message
  end

  def test_bdelete_rejects_modified_buffer_without_bang
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["x"])
    @editor.current_buffer.modified = true

    @dispatcher.dispatch_ex(@editor, "bd")

    assert_equal true, @editor.message_error?
    assert_match(/No write since last change/, @editor.message)
    assert @editor.buffers.key?(@editor.current_buffer.id)
  end

  def test_bdelete_bang_deletes_modified_buffer
    @editor.materialize_intro_buffer!
    first = @editor.current_buffer
    other = @editor.add_empty_buffer(path: "other.txt")
    @dispatcher.dispatch_ex(@editor, "buffer #{other.id}")
    @editor.current_buffer.replace_all_lines!(["dirty"])
    @editor.current_buffer.modified = true

    @dispatcher.dispatch_ex(@editor, "bd!")

    assert_equal first.id, @editor.current_buffer.id
    refute @editor.buffers.key?(other.id)
    refute @editor.message_error?
  end

  def test_splitbelow_and_splitright_change_insertion_side
    @editor.set_option("splitbelow", false, scope: :global)
    first = @editor.current_window_id
    @dispatcher.dispatch_ex(@editor, "split")
    assert_equal @editor.window_order[0], @editor.current_window_id
    assert_equal first, @editor.window_order[1]

    @editor.set_option("splitright", false, scope: :global)
    @editor.current_window_id = first
    @dispatcher.dispatch_ex(@editor, "vsplit")
    idx = @editor.window_order.index(@editor.current_window_id)
    assert_equal 1, idx
  end
end
