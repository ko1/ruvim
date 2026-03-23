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

  def test_dispatch_ex_shell_uses_shell_executor_when_available
    executed_command = nil
    fake_status = Struct.new(:exitstatus).new(0)
    @editor.shell_executor = ->(cmd) { executed_command = cmd; fake_status }

    @dispatcher.dispatch_ex(@editor, "!echo hello")

    assert_equal "echo hello", executed_command
    assert_equal "shell exit 0", @editor.message
  end

  def test_dispatch_ex_shell_falls_back_to_capture_without_executor
    @editor.shell_executor = nil
    @dispatcher.dispatch_ex(@editor, "!echo out; echo err 1>&2")

    assert_equal "[Shell Output]", @editor.message
    assert_equal :help, @editor.current_buffer.kind
    body = @editor.current_buffer.lines.join("\n")
    assert_includes body, "[stdout]"
    assert_includes body, "out"
    assert_includes body, "[stderr]"
    assert_includes body, "err"
  end

  def test_dispatch_ex_read_file_inserts_after_cursor_line
    @editor.materialize_intro_buffer!
    Dir.mktmpdir do |dir|
      path = File.join(dir, "data.txt")
      File.write(path, "aaa\nbbb\n")
      @editor.current_buffer.replace_all_lines!(%w[line1 line2 line3])
      @editor.current_window.cursor_y = 1  # on line2

      @dispatcher.dispatch_ex(@editor, "r #{path}")

      assert_equal %w[line1 line2 aaa bbb line3], @editor.current_buffer.lines
    end
  end

  def test_dispatch_ex_read_with_range_inserts_after_specified_line
    @editor.materialize_intro_buffer!
    Dir.mktmpdir do |dir|
      path = File.join(dir, "data.txt")
      File.write(path, "inserted\n")
      @editor.current_buffer.replace_all_lines!(%w[line1 line2 line3])

      @dispatcher.dispatch_ex(@editor, "2r #{path}")

      assert_equal %w[line1 line2 inserted line3], @editor.current_buffer.lines
    end
  end

  def test_dispatch_ex_read_shell_command_inserts_output
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(%w[line1 line2])
    @editor.current_window.cursor_y = 0

    @dispatcher.dispatch_ex(@editor, "r !echo hello")

    assert_equal %w[line1 hello line2], @editor.current_buffer.lines
  end

  def test_dispatch_ex_write_to_shell_command
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(%w[hello world])

    Dir.mktmpdir do |dir|
      outfile = File.join(dir, "out.txt")
      @dispatcher.dispatch_ex(@editor, "w !cat > #{outfile}")

      assert_equal "hello\nworld\n", File.read(outfile)
    end
  end

  def test_dispatch_ex_write_range_to_shell_command
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(%w[aaa bbb ccc])

    Dir.mktmpdir do |dir|
      outfile = File.join(dir, "out.txt")
      @dispatcher.dispatch_ex(@editor, "2,3w !cat > #{outfile}")

      assert_equal "bbb\nccc\n", File.read(outfile)
    end
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

  def test_tabs_lists_all_tabpages
    @editor.tabnew(path: nil)
    @editor.tabnew(path: nil)
    assert_equal 3, @editor.tabpage_count

    @dispatcher.dispatch_ex(@editor, "tabs")

    lines = @editor.hit_enter_lines
    refute_nil lines, "tabs should produce multiline output"
    joined = lines.join("\n")
    assert_includes joined, "Tab page 1"
    assert_includes joined, "Tab page 2"
    assert_includes joined, "Tab page 3"
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

  # --- Range parser tests ---

  def test_parse_range_percent
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    result = @dispatcher.parse_range("%", @editor)
    assert_equal 0, result[:range_start]
    assert_equal 4, result[:range_end]
    assert_equal "", result[:rest]
  end

  def test_parse_range_numeric_pair
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    result = @dispatcher.parse_range("1,5", @editor)
    assert_equal 0, result[:range_start]
    assert_equal 4, result[:range_end]
    assert_equal "", result[:rest]
  end

  def test_parse_range_dot_and_dollar
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    @editor.current_window.cursor_y = 2

    result = @dispatcher.parse_range(".,$", @editor)
    assert_equal 2, result[:range_start]
    assert_equal 4, result[:range_end]
    assert_equal "", result[:rest]
  end

  def test_parse_range_with_offset
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    @editor.current_window.cursor_y = 1

    result = @dispatcher.parse_range(".+2,$-1", @editor)
    assert_equal 3, result[:range_start]
    assert_equal 3, result[:range_end]
    assert_equal "", result[:rest]
  end

  def test_parse_range_single_address
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c"])
    result = @dispatcher.parse_range("2", @editor)
    assert_equal 1, result[:range_start]
    assert_equal 1, result[:range_end]
    assert_equal "", result[:rest]
  end

  def test_parse_range_returns_nil_for_no_range
    @editor.materialize_intro_buffer!
    result = @dispatcher.parse_range("help", @editor)
    assert_nil result
  end

  def test_parse_range_with_rest
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    result = @dispatcher.parse_range("%s/a/b/g", @editor)
    assert_equal 0, result[:range_start]
    assert_equal 4, result[:range_end]
    assert_equal "s/a/b/g", result[:rest]
  end

  def test_parse_range_mark_address
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])
    @editor.current_window.cursor_y = 1
    @editor.set_mark("a")
    @editor.current_window.cursor_y = 3
    @editor.set_mark("b")

    result = @dispatcher.parse_range("'a,'b", @editor)
    assert_equal 1, result[:range_start]
    assert_equal 3, result[:range_end]
    assert_equal "", result[:rest]
  end

  # --- Substitute parser tests ---

  def test_parse_substitute_basic
    result = @dispatcher.parse_substitute("s/foo/bar/")
    assert_equal "foo", result[:pattern]
    assert_equal "bar", result[:replacement]
    assert_equal "", result[:flags_str]
  end

  def test_parse_substitute_with_flags
    result = @dispatcher.parse_substitute("s/foo/bar/gi")
    assert_equal "foo", result[:pattern]
    assert_equal "bar", result[:replacement]
    assert_equal "gi", result[:flags_str]
  end

  def test_parse_substitute_returns_nil_for_non_substitute
    assert_nil @dispatcher.parse_substitute("help")
    assert_nil @dispatcher.parse_substitute("set number")
  end

  # --- Substitute with range integration ---

  def test_substitute_with_range
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo", "foo", "foo", "foo"])

    @dispatcher.dispatch_ex(@editor, "1,3s/foo/bar/")

    assert_equal "bar", @editor.current_buffer.line_at(0)
    assert_equal "bar", @editor.current_buffer.line_at(1)
    assert_equal "bar", @editor.current_buffer.line_at(2)
    assert_equal "foo", @editor.current_buffer.line_at(3)
    assert_equal "foo", @editor.current_buffer.line_at(4)
  end

  def test_substitute_percent_range
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "bar", "foo"])

    @dispatcher.dispatch_ex(@editor, "%s/foo/baz/")

    assert_equal "baz", @editor.current_buffer.line_at(0)
    assert_equal "bar", @editor.current_buffer.line_at(1)
    assert_equal "baz", @editor.current_buffer.line_at(2)
  end

  def test_substitute_ignore_case_flag
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["FOO", "foo", "Foo"])

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/gi")

    assert_equal "bar", @editor.current_buffer.line_at(0)
    assert_equal "bar", @editor.current_buffer.line_at(1)
    assert_equal "bar", @editor.current_buffer.line_at(2)
  end

  def test_substitute_count_only_flag
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "bar", "foo baz foo"])

    @dispatcher.dispatch_ex(@editor, "%s/foo/x/gn")

    # n flag: count only, no changes
    assert_equal "foo", @editor.current_buffer.line_at(0)
    assert_equal "foo baz foo", @editor.current_buffer.line_at(2)
    assert_match(/3 match/, @editor.message)
  end

  def test_substitute_no_range_defaults_to_whole_buffer
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["aaa", "bbb", "aaa"])

    @dispatcher.dispatch_ex(@editor, "s/aaa/zzz/")

    assert_equal "zzz", @editor.current_buffer.line_at(0)
    assert_equal "bbb", @editor.current_buffer.line_at(1)
    assert_equal "zzz", @editor.current_buffer.line_at(2)
  end

  # --- :s///c (confirm substitute) tests ---

  def test_substitute_confirm_yes_replaces
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo bar foo"])
    keys = ["y", "y"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/baz/gc")

    assert_equal "baz bar baz", @editor.current_buffer.line_at(0)
    assert_match(/2 substitution/, @editor.message)
  end

  def test_substitute_confirm_no_skips
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo bar foo"])
    keys = ["n", "n"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/baz/gc")

    assert_equal "foo bar foo", @editor.current_buffer.line_at(0)
    assert_match(/Pattern not found/, @editor.message)
  end

  def test_substitute_confirm_quit_stops
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo", "foo"])
    keys = ["y", "q"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/c")

    assert_equal "bar", @editor.current_buffer.line_at(0)
    assert_equal "foo", @editor.current_buffer.line_at(1)
    assert_equal "foo", @editor.current_buffer.line_at(2)
  end

  def test_substitute_confirm_all_replaces_remaining
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo", "foo"])
    keys = ["n", "a"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/c")

    assert_equal "foo", @editor.current_buffer.line_at(0)
    assert_equal "bar", @editor.current_buffer.line_at(1)
    assert_equal "bar", @editor.current_buffer.line_at(2)
  end

  def test_substitute_confirm_last_replaces_one_and_stops
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo", "foo"])
    keys = ["l"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/c")

    assert_equal "bar", @editor.current_buffer.line_at(0)
    assert_equal "foo", @editor.current_buffer.line_at(1)
    assert_equal "foo", @editor.current_buffer.line_at(2)
  end

  def test_substitute_confirm_escape_stops
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo"])
    keys = [:escape].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/c")

    assert_equal "foo", @editor.current_buffer.line_at(0)
    assert_equal "foo", @editor.current_buffer.line_at(1)
  end

  def test_substitute_confirm_undo_is_single_unit
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["foo", "foo", "foo"])
    keys = ["y", "y", "y"].each
    @editor.confirm_key_reader = -> { keys.next }

    @dispatcher.dispatch_ex(@editor, "%s/foo/bar/c")

    assert_equal ["bar", "bar", "bar"], @editor.current_buffer.lines
    assert @editor.current_buffer.undo!
    assert_equal ["foo", "foo", "foo"], @editor.current_buffer.lines
  end

  # --- :d (delete lines) tests ---

  def test_delete_lines_with_range
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])

    @dispatcher.dispatch_ex(@editor, "2,4d")

    assert_equal 2, @editor.current_buffer.line_count
    assert_equal "a", @editor.current_buffer.line_at(0)
    assert_equal "e", @editor.current_buffer.line_at(1)
    assert_match(/3 line/, @editor.message)
  end

  def test_delete_lines_without_range_deletes_current
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c"])
    @editor.current_window.cursor_y = 1

    @dispatcher.dispatch_ex(@editor, "d")

    assert_equal 2, @editor.current_buffer.line_count
    assert_equal "a", @editor.current_buffer.line_at(0)
    assert_equal "c", @editor.current_buffer.line_at(1)
  end

  # --- :y (yank lines) tests ---

  def test_yank_lines_with_range
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c", "d", "e"])

    @dispatcher.dispatch_ex(@editor, "1,3y")

    assert_match(/3 line/, @editor.message)
    # Buffer unchanged
    assert_equal 5, @editor.current_buffer.line_count
  end

  def test_yank_lines_without_range_yanks_current
    @editor.materialize_intro_buffer!
    @editor.current_buffer.replace_all_lines!(["a", "b", "c"])
    @editor.current_window.cursor_y = 1

    @dispatcher.dispatch_ex(@editor, "y")

    assert_match(/1 line/, @editor.message)
    assert_equal 3, @editor.current_buffer.line_count
  end

  # --- :grep tests ---

  def test_grep_populates_quickfix
    Dir.mktmpdir("ruvim-grep") do |dir|
      File.write(File.join(dir, "a.txt"), "hello world\ngoodbye\n")
      File.write(File.join(dir, "b.txt"), "hello again\n")

      @editor.materialize_intro_buffer!
      @dispatcher.dispatch_ex(@editor, "grep hello #{File.join(dir, '*.txt')}")

      assert_operator @editor.quickfix_items.length, :>=, 2
      refute @editor.message_error?
    end
  end

  def test_grep_no_matches_shows_error
    @editor.materialize_intro_buffer!
    @dispatcher.dispatch_ex(@editor, "grep ZZZZUNMATCHABLE /dev/null")

    assert @editor.message_error?
  end

  def test_lgrep_populates_location_list
    Dir.mktmpdir("ruvim-lgrep") do |dir|
      File.write(File.join(dir, "c.txt"), "alpha\nbeta\nalpha\n")

      @editor.materialize_intro_buffer!
      wid = @editor.current_window_id
      @dispatcher.dispatch_ex(@editor, "lgrep alpha #{File.join(dir, 'c.txt')}")

      assert_operator @editor.location_items(wid).length, :>=, 2
      refute @editor.message_error?
    end
  end

  # ---- parse_gf_target with col ----

  class ParseGfTargetColTest < Minitest::Test
    def setup
      @gc = RuVim::GlobalCommands.instance
    end

    def test_path_line_col
      result = @gc.send(:parse_gf_target, "foo.rb:10:5")
      assert_equal "foo.rb", result[:path]
      assert_equal 10, result[:line]
      assert_equal 5, result[:col]
    end

    def test_path_line_only
      result = @gc.send(:parse_gf_target, "foo.rb:10")
      assert_equal "foo.rb", result[:path]
      assert_equal 10, result[:line]
      assert_nil result[:col]
    end

    def test_plain_path
      result = @gc.send(:parse_gf_target, "foo.rb")
      assert_equal "foo.rb", result[:path]
      assert_nil result[:line]
      assert_nil result[:col]
    end

    def test_path_line_col_zero_col
      result = @gc.send(:parse_gf_target, "foo.rb:1:0")
      assert_equal "foo.rb", result[:path]
      assert_equal 1, result[:line]
      assert_equal 0, result[:col]
    end

    def test_trailing_colon
      result = @gc.send(:parse_gf_target, "foo.rb:10:")
      assert_equal "foo.rb", result[:path]
      assert_equal 10, result[:line]
      assert_nil result[:col]
    end

    def test_trailing_colon_with_spaces
      result = @gc.send(:parse_gf_target, "foo.rb:10: ")
      assert_equal "foo.rb", result[:path]
      assert_equal 10, result[:line]
      assert_nil result[:col]
    end
  end

  # ---- parse_path_with_location ----

  class ParsePathWithLocationTest < Minitest::Test
    def test_existing_file_with_line
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hello.rb")
        File.write(path, "line1\nline2\nline3\n")

        result = RuVim::GlobalCommands.parse_path_with_location("#{path}:2")
        assert_equal path, result[:path]
        assert_equal 2, result[:line]
        assert_nil result[:col]
      end
    end

    def test_existing_file_with_line_and_col
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hello.rb")
        File.write(path, "line1\nline2\nline3\n")

        result = RuVim::GlobalCommands.parse_path_with_location("#{path}:3:7")
        assert_equal path, result[:path]
        assert_equal 3, result[:line]
        assert_equal 7, result[:col]
      end
    end

    def test_nonexistent_file_with_digits_treated_as_literal
      result = RuVim::GlobalCommands.parse_path_with_location("/no/such/file.rb:10")
      assert_equal "/no/such/file.rb:10", result[:path]
      assert_nil result[:line]
      assert_nil result[:col]
    end

    def test_existing_file_without_location
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hello.rb")
        File.write(path, "content\n")

        result = RuVim::GlobalCommands.parse_path_with_location(path)
        assert_equal path, result[:path]
        assert_nil result[:line]
        assert_nil result[:col]
      end
    end

    def test_nil_input
      result = RuVim::GlobalCommands.parse_path_with_location(nil)
      assert_equal "", result[:path]
      assert_nil result[:line]
    end

    def test_trailing_colon
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hello.rb")
        File.write(path, "line1\nline2\nline3\n")

        result = RuVim::GlobalCommands.parse_path_with_location("#{path}:2:")
        assert_equal path, result[:path]
        assert_equal 2, result[:line]
        assert_nil result[:col]
      end
    end

    def test_trailing_colon_with_spaces
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hello.rb")
        File.write(path, "line1\nline2\nline3\n")

        result = RuVim::GlobalCommands.parse_path_with_location("#{path}:2: ")
        assert_equal path, result[:path]
        assert_equal 2, result[:line]
        assert_nil result[:col]
      end
    end
  end

  # ---- open_path with path:line:col ----

  class OpenPathLocationTest < Minitest::Test
    def setup
      @app = RuVim::App.new
      @editor = @app.instance_variable_get(:@editor)
    end

    def test_open_path_jumps_to_line
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.rb")
        File.write(path, (1..20).map { |i| "line #{i}" }.join("\n"))

        @editor.open_path("#{path}:10")
        assert_equal path, @editor.current_buffer.path
        assert_equal 9, @editor.current_window.cursor_y  # 0-indexed
      end
    end

    def test_open_path_jumps_to_line_and_col
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.rb")
        File.write(path, (1..20).map { |i| "line #{i}" }.join("\n"))

        @editor.open_path("#{path}:5:3")
        assert_equal path, @editor.current_buffer.path
        assert_equal 4, @editor.current_window.cursor_y  # 0-indexed
        assert_equal 3, @editor.current_window.cursor_x
      end
    end

    def test_open_path_nonexistent_colon_digits_literal
      @editor.open_path("/tmp/nonexistent_path_test:42")
      # treated as literal path since /tmp/nonexistent_path_test doesn't exist
      assert_equal "/tmp/nonexistent_path_test:42", @editor.current_buffer.path
    end
  end

  # ---- open_path with directory ----

  class OpenPathDirectoryTest < Minitest::Test
    def setup
      @app = RuVim::App.new
      @editor = @app.instance_variable_get(:@editor)
    end

    def test_open_path_directory_shows_error
      Dir.mktmpdir do |dir|
        original_buffer = @editor.current_buffer
        @editor.open_path(dir)
        assert_equal original_buffer, @editor.current_buffer, "buffer should not change"
        assert_equal :error, @editor.instance_variable_get(:@message_kind)
        assert_match(/is a directory/, @editor.instance_variable_get(:@message))
      end
    end

    def test_open_path_sync_directory_returns_nil
      Dir.mktmpdir do |dir|
        result = @editor.send(:open_path_sync, dir)
        assert_nil result
      end
    end
  end

  # ---- parse_global ----

  class ParseGlobalTest < Minitest::Test
    def setup
      @dispatcher = RuVim::Dispatcher.new
    end

    def test_g_slash_pattern_slash_command
      result = @dispatcher.parse_global("g/TODO/d")
      assert_equal "TODO", result[:pattern]
      assert_equal "d", result[:command]
      refute result[:invert]
    end

    def test_v_slash_pattern_slash_command
      result = @dispatcher.parse_global("v/TODO/d")
      assert_equal "TODO", result[:pattern]
      assert_equal "d", result[:command]
      assert result[:invert]
    end

    def test_global_with_substitute_command
      result = @dispatcher.parse_global("g/foo/s/bar/baz/g")
      assert_equal "foo", result[:pattern]
      assert_equal "s/bar/baz/g", result[:command]
    end

    def test_global_without_command_defaults_to_print
      result = @dispatcher.parse_global("g/pattern/")
      assert_equal "pattern", result[:pattern]
      assert_equal "p", result[:command]
    end

    def test_global_with_bang_inverts
      result = @dispatcher.parse_global("g!/pattern/d")
      assert_equal "pattern", result[:pattern]
      assert_equal "d", result[:command]
      assert result[:invert]
    end

    def test_non_global_returns_nil
      assert_nil @dispatcher.parse_global("set number")
      assert_nil @dispatcher.parse_global("d")
    end
  end

  # ---- :global / :vglobal integration ----

  class GlobalCommandTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_global_delete_matching_lines
      set_lines("keep", "DEBUG foo", "keep2", "DEBUG bar", "keep3")
      @dispatcher.dispatch_ex(@editor, "g/DEBUG/d")
      assert_equal %w[keep keep2 keep3], @editor.current_buffer.lines
    end

    def test_vglobal_delete_non_matching_lines
      set_lines("keep", "remove", "keep2", "remove2", "keep3")
      @dispatcher.dispatch_ex(@editor, "v/keep/d")
      assert_equal %w[keep keep2 keep3], @editor.current_buffer.lines
    end

    def test_global_with_range
      set_lines("a", "DEBUG 1", "b", "DEBUG 2", "c")
      @dispatcher.dispatch_ex(@editor, "2,4g/DEBUG/d")
      assert_equal %w[a b c], @editor.current_buffer.lines
    end

    def test_global_substitute
      set_lines("hello world", "foo bar", "hello foo")
      @dispatcher.dispatch_ex(@editor, "g/hello/s/hello/hi/")
      assert_equal ["hi world", "foo bar", "hi foo"], @editor.current_buffer.lines
    end

    def test_global_no_match_shows_message
      set_lines("aaa", "bbb", "ccc")
      @dispatcher.dispatch_ex(@editor, "g/zzz/d")
      assert_match(/not found/i, @editor.message)
    end

    def test_global_undo_is_single_unit
      set_lines("a", "DEBUG 1", "b", "DEBUG 2", "c")
      @dispatcher.dispatch_ex(@editor, "g/DEBUG/d")
      assert_equal %w[a b c], @editor.current_buffer.lines
      @editor.current_buffer.undo!
      assert_equal ["a", "DEBUG 1", "b", "DEBUG 2", "c"], @editor.current_buffer.lines
    end

    def test_vglobal_with_v_command
      set_lines("keep", "remove1", "keep2", "remove2")
      @dispatcher.dispatch_ex(@editor, "v/keep/d")
      assert_equal %w[keep keep2], @editor.current_buffer.lines
    end

    def test_global_delete_all_lines_leaves_empty_buffer
      set_lines("a", "b", "c")
      @dispatcher.dispatch_ex(@editor, "g/./d")
      assert_equal [""], @editor.current_buffer.lines
    end

    def test_global_print_collects_all_lines
      set_lines("aaa", "bbb editor", "ccc", "ddd editor", "eee")
      @dispatcher.dispatch_ex(@editor, "g/editor/p")
      lines = @editor.hit_enter_lines
      assert lines, "should enter hit-enter mode for multi-line output"
      assert_includes lines, "bbb editor"
      assert_includes lines, "ddd editor"
    end

    def test_global_number_collects_all_lines
      set_lines("aaa", "bbb editor", "ccc", "ddd editor")
      @dispatcher.dispatch_ex(@editor, "g/editor/nu")
      lines = @editor.hit_enter_lines
      assert lines, "should enter hit-enter mode for multi-line output"
      assert lines.any? { |l| l.include?("bbb editor") }
      assert lines.any? { |l| l.include?("ddd editor") }
    end
  end

  # ---- Ex commands: :print, :number, :move, :copy, :join, :>/<, :normal ----

  class ExPrintTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_print_current_line
      set_lines("aaa", "bbb", "ccc")
      @editor.current_window.cursor_y = 1
      @dispatcher.dispatch_ex(@editor, "p")
      assert_match(/bbb/, @editor.message)
    end

    def test_print_range
      set_lines("aaa", "bbb", "ccc")
      @dispatcher.dispatch_ex(@editor, "1,2p")
      assert_match(/aaa/, @editor.message)
      assert_match(/bbb/, @editor.message)
    end

    def test_number_current_line
      set_lines("aaa", "bbb", "ccc")
      @editor.current_window.cursor_y = 1
      @dispatcher.dispatch_ex(@editor, "nu")
      assert_match(/2.*bbb/, @editor.message)
    end

    def test_number_range
      set_lines("aaa", "bbb", "ccc")
      @dispatcher.dispatch_ex(@editor, "1,3nu")
      assert_match(/1.*aaa/, @editor.message)
      assert_match(/3.*ccc/, @editor.message)
    end
  end

  class ExMoveTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_move_line_to_end
      set_lines("a", "b", "c", "d")
      @editor.current_window.cursor_y = 0
      @dispatcher.dispatch_ex(@editor, "1m$")
      assert_equal %w[b c d a], @editor.current_buffer.lines
    end

    def test_move_line_to_beginning
      set_lines("a", "b", "c")
      @editor.current_window.cursor_y = 2
      @dispatcher.dispatch_ex(@editor, "3m0")
      assert_equal %w[c a b], @editor.current_buffer.lines
    end

    def test_move_range
      set_lines("a", "b", "c", "d", "e")
      @dispatcher.dispatch_ex(@editor, "2,3m$")
      assert_equal %w[a d e b c], @editor.current_buffer.lines
    end

    def test_move_no_arg_error
      set_lines("a", "b")
      @dispatcher.dispatch_ex(@editor, "m")
      assert @editor.message_error?
    end
  end

  class ExCopyTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_copy_line_to_end
      set_lines("a", "b", "c")
      @editor.current_window.cursor_y = 0
      @dispatcher.dispatch_ex(@editor, "1t$")
      assert_equal %w[a b c a], @editor.current_buffer.lines
    end

    def test_copy_line_to_beginning
      set_lines("a", "b", "c")
      @editor.current_window.cursor_y = 2
      @dispatcher.dispatch_ex(@editor, "3t0")
      assert_equal %w[c a b c], @editor.current_buffer.lines
    end

    def test_copy_range
      set_lines("a", "b", "c", "d")
      @dispatcher.dispatch_ex(@editor, "2,3t$")
      assert_equal %w[a b c d b c], @editor.current_buffer.lines
    end
  end

  class ExJoinTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_join_current_line
      set_lines("hello", "world", "end")
      @editor.current_window.cursor_y = 0
      @dispatcher.dispatch_ex(@editor, "j")
      assert_equal ["hello world", "end"], @editor.current_buffer.lines
    end

    def test_join_range
      set_lines("a", "b", "c", "d")
      @dispatcher.dispatch_ex(@editor, "1,3j")
      assert_equal ["a b c", "d"], @editor.current_buffer.lines
    end
  end

  class ExShiftTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_shift_right
      set_lines("aaa", "bbb", "ccc")
      @editor.current_window.cursor_y = 1
      @dispatcher.dispatch_ex(@editor, "2>")
      assert_equal "  bbb", @editor.current_buffer.line_at(1)
    end

    def test_shift_left
      set_lines("aaa", "  bbb", "ccc")
      @editor.current_window.cursor_y = 1
      @dispatcher.dispatch_ex(@editor, "2<")
      assert_equal "bbb", @editor.current_buffer.line_at(1)
    end

    def test_shift_right_range
      set_lines("aaa", "bbb", "ccc")
      @dispatcher.dispatch_ex(@editor, "1,3>")
      assert_equal "  aaa", @editor.current_buffer.line_at(0)
      assert_equal "  bbb", @editor.current_buffer.line_at(1)
      assert_equal "  ccc", @editor.current_buffer.line_at(2)
    end

    def test_shift_left_range
      set_lines("  aaa", "  bbb", "  ccc")
      @dispatcher.dispatch_ex(@editor, "1,3<")
      assert_equal "aaa", @editor.current_buffer.line_at(0)
      assert_equal "bbb", @editor.current_buffer.line_at(1)
      assert_equal "ccc", @editor.current_buffer.line_at(2)
    end
  end

  class ExNormalTest < Minitest::Test
    def setup
      @app = RuVim::App.new(clean: true)
      @editor = @app.instance_variable_get(:@editor)
      @editor.materialize_intro_buffer!
      @dispatcher = RuVim::Dispatcher.new
      @key_handler = @app.instance_variable_get(:@key_handler)
      # Wire up normal_key_feeder so :normal can feed keys
      @editor.normal_key_feeder = ->(keys) { keys.each { |k| @key_handler.handle(k) } }
    end

    def set_lines(*lines)
      buf = @editor.current_buffer
      buf.replace_all_lines!(lines)
      buf.instance_variable_set(:@modified, false)
    end

    def test_normal_delete_word
      set_lines("hello world", "foo bar")
      @editor.current_window.cursor_y = 0
      @editor.current_window.cursor_x = 0
      @dispatcher.dispatch_ex(@editor, "normal dw")
      assert_equal "world", @editor.current_buffer.line_at(0)
    end

    def test_normal_with_range
      set_lines("hello", "world", "foo")
      @dispatcher.dispatch_ex(@editor, "1,3normal A!")
      assert_equal "hello!", @editor.current_buffer.line_at(0)
      assert_equal "world!", @editor.current_buffer.line_at(1)
      assert_equal "foo!", @editor.current_buffer.line_at(2)
    end

    def test_normal_dd
      set_lines("aaa", "bbb", "ccc")
      @editor.current_window.cursor_y = 1
      @dispatcher.dispatch_ex(@editor, "2normal dd")
      assert_equal %w[aaa ccc], @editor.current_buffer.lines
    end

    def test_global_normal_append
      set_lines("foo", "bar foo", "baz")
      @dispatcher.dispatch_ex(@editor, "g/foo/normal A;")
      assert_equal "foo;", @editor.current_buffer.line_at(0)
      assert_equal "bar foo;", @editor.current_buffer.line_at(1)
      assert_equal "baz", @editor.current_buffer.line_at(2)
    end
  end
end
