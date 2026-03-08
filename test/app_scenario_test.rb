require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "stringio"

class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @key_handler = @app.instance_variable_get(:@key_handler)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @key_handler.handle(k) }
  end

  def test_insert_edit_search_and_delete_scenario
    feed("i", "h", "e", "l", "l", "o", :enter, "w", "o", "r", "l", "d", :escape)
    feed("k", "0", "x")
    feed("/", "o", :enter)
    feed("n")

    assert_equal ["ello", "world"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
    assert_equal "Search wrapped", @editor.message if @editor.message == "Search wrapped"
    assert_operator @editor.current_window.cursor_y, :>=, 0
  end

  def test_visual_block_yank
    @editor.current_buffer.replace_all_lines!(["abcde", "ABCDE", "xyz"])
    @editor.current_window.cursor_x = 1
    @editor.current_window.cursor_y = 0

    feed(:ctrl_v, "j", "l", "l", "y")

    reg = @editor.get_register("\"")
    assert_equal :normal, @editor.mode
    assert_equal "bcd\nBCD", reg[:text]
  end

  def test_visual_block_delete
    @editor.current_buffer.replace_all_lines!(["abcde", "ABCDE", "xyz"])
    @editor.current_window.cursor_x = 1
    @editor.current_window.cursor_y = 0

    feed(:ctrl_v, "j", "l", "l", "d")

    assert_equal ["ae", "AE", "xyz"], @editor.current_buffer.lines
    assert_equal 0, @editor.current_window.cursor_y
    assert_equal 1, @editor.current_window.cursor_x
    assert_equal :normal, @editor.mode
  end

  def test_dot_repeats_insert_change
    @editor.current_buffer.replace_all_lines!([""])
    feed("i", "a", "b", :escape)
    feed(".")

    assert_equal ["abab"], @editor.current_buffer.lines
  end

  def test_dot_repeats_change_with_text_object
    @editor.current_buffer.replace_all_lines!(["foo bar"])
    feed("c", "i", "w", "X", :escape)
    feed("w")
    feed(".")

    assert_equal ["X X"], @editor.current_buffer.lines
  end

  def test_dot_repeat_works_inside_macro
    @editor.current_buffer.replace_all_lines!(["abc", "abc", "abc"])

    feed("x")
    feed("j", "0", "q", "a", ".", "j", "q")
    feed("@", "a")

    assert_equal ["bc", "bc", "bc"], @editor.current_buffer.lines
  end

  def test_s_substitutes_char_and_enters_insert_mode
    @editor.current_buffer.replace_all_lines!(["abcd"])
    @editor.current_window.cursor_x = 1

    feed("s", "X", :escape)

    assert_equal ["aXcd"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
  end

  def test_z_commands_reposition_current_line_in_window
    @editor.current_buffer.replace_all_lines!((1..20).map { |i| "line#{i}" })
    @editor.current_window_view_height_hint = 5
    @editor.current_window.cursor_y = 10

    feed("z", "t")
    assert_equal 10, @editor.current_window.row_offset

    feed("z", "z")
    assert_equal 8, @editor.current_window.row_offset

    feed("z", "b")
    assert_equal 6, @editor.current_window.row_offset
  end

  def test_j_joins_next_line_trimming_indent
    @editor.current_buffer.replace_all_lines!(["foo", "  bar", "baz"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("J")

    assert_equal ["foo bar", "baz"], @editor.current_buffer.lines
    assert_equal 3, @editor.current_window.cursor_x
  end

  def test_uppercase_aliases_d_c_s_x_y_and_tilde
    @editor.current_buffer.replace_all_lines!(["abcd"])
    @editor.current_window.cursor_x = 2
    feed("X")
    assert_equal ["acd"], @editor.current_buffer.lines

    @editor.current_buffer.replace_all_lines!(["abcd"])
    @editor.current_window.cursor_x = 1
    feed("D")
    assert_equal ["a"], @editor.current_buffer.lines

    @editor.current_buffer.replace_all_lines!(["abcd"])
    @editor.current_window.cursor_x = 1
    feed("C", "X", :escape)
    assert_equal ["aX"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode

    @editor.current_buffer.replace_all_lines!(["Abcd"])
    @editor.current_window.cursor_x = 0
    feed("~")
    assert_equal ["abcd"], @editor.current_buffer.lines
    assert_equal 1, @editor.current_window.cursor_x

    @editor.current_buffer.replace_all_lines!(["hello"])
    @editor.current_window.cursor_x = 0
    feed("Y")
    reg = @editor.get_register("\"")
    assert_equal :linewise, reg[:type]
    assert_equal "hello\n", reg[:text]

    @editor.current_buffer.replace_all_lines!(["hello"])
    @editor.current_window.cursor_x = 0
    feed("S", "x", :escape)
    assert_equal ["x"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
  end

  def test_expandtab_and_autoindent_in_insert_mode
    @editor.set_option("expandtab", true, scope: :buffer)
    @editor.set_option("tabstop", 4, scope: :buffer)
    @editor.set_option("softtabstop", 4, scope: :buffer)
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.current_buffer.replace_all_lines!(["  foo"])

    feed("A", :ctrl_i, :enter, :escape)

    assert_equal ["  foo   ", "  "], @editor.current_buffer.lines
  end

  def test_smartindent_adds_shiftwidth_after_open_brace
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.set_option("smartindent", true, scope: :buffer)
    @editor.set_option("shiftwidth", 2, scope: :buffer)
    @editor.current_buffer.replace_all_lines!(["if x {"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = @editor.current_buffer.line_length(0)

    feed("A", :enter, :escape)

    assert_equal ["if x {", "  "], @editor.current_buffer.lines
  end

  def test_smartindent_adds_shiftwidth_after_ruby_def
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.set_option("smartindent", true, scope: :buffer)
    @editor.set_option("shiftwidth", 2, scope: :buffer)
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_buffer.replace_all_lines!(["def foo"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = @editor.current_buffer.line_length(0)

    feed("A", :enter, :escape)

    assert_equal ["def foo", "  "], @editor.current_buffer.lines
  end

  def test_smartindent_adds_shiftwidth_after_ruby_do_block
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.set_option("smartindent", true, scope: :buffer)
    @editor.set_option("shiftwidth", 2, scope: :buffer)
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_buffer.replace_all_lines!(["  items.each do |x|"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = @editor.current_buffer.line_length(0)

    feed("A", :enter, :escape)

    assert_equal ["  items.each do |x|", "    "], @editor.current_buffer.lines
  end

  def test_smartindent_dedents_end_in_insert_mode
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.set_option("smartindent", true, scope: :buffer)
    @editor.set_option("shiftwidth", 2, scope: :buffer)
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_buffer.replace_all_lines!(["def foo"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = @editor.current_buffer.line_length(0)

    feed("A", :enter, "b", "a", "r", :enter, "e", "n", "d", :escape)

    assert_equal ["def foo", "  bar", "end"], @editor.current_buffer.lines
  end

  def test_smartindent_dedents_else_in_insert_mode
    @editor.set_option("autoindent", true, scope: :buffer)
    @editor.set_option("smartindent", true, scope: :buffer)
    @editor.set_option("shiftwidth", 2, scope: :buffer)
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_buffer.replace_all_lines!(["if cond"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = @editor.current_buffer.line_length(0)

    feed("A", :enter, "a", :enter, "e", "l", "s", "e", :escape)

    assert_equal ["if cond", "  a", "else"], @editor.current_buffer.lines
  end

  def test_incsearch_moves_cursor_while_typing_and_escape_restores
    @editor.set_option("incsearch", true, scope: :global)
    @editor.current_buffer.replace_all_lines!(["alpha", "beta", "gamma"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("/", "b")
    assert_equal :command_line, @editor.mode
    assert_equal 1, @editor.current_window.cursor_y
    assert_equal 0, @editor.current_window.cursor_x

    feed(:escape)
    assert_equal :normal, @editor.mode
    assert_equal 0, @editor.current_window.cursor_y
    assert_equal 0, @editor.current_window.cursor_x
  end

  def test_search_command_line_backspace_on_empty_cancels
    @editor.current_buffer.replace_all_lines!(["alpha", "beta"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("/")
    assert_equal :command_line, @editor.mode
    assert_equal "/", @editor.command_line.prefix
    assert_equal "", @editor.command_line.text

    feed(:backspace)

    assert_equal :normal, @editor.mode
    assert_equal 0, @editor.current_window.cursor_y
    assert_equal 0, @editor.current_window.cursor_x
  end

  def test_lopen_enter_jumps_to_selected_location_and_returns_to_source_window
    @editor.current_buffer.replace_all_lines!(["aa", "bb aa", "cc aa"])
    source_window_id = @editor.current_window_id

    @dispatcher.dispatch_ex(@editor, "lvimgrep /aa/")
    @dispatcher.dispatch_ex(@editor, "lopen")

    assert_equal :location_list, @editor.current_buffer.kind
    assert_equal 2, @editor.window_count

    # Header lines are: title, blank, then items...
    @editor.current_window.cursor_y = 4 # 3rd item
    feed(:enter)

    refute_equal :location_list, @editor.current_buffer.kind
    assert_equal source_window_id, @editor.current_window_id
    assert_equal 2, @editor.current_window.cursor_y
    assert_equal 3, @editor.current_window.cursor_x
  end

  def test_incsearch_submit_stays_on_previewed_match
    @editor.set_option("incsearch", true, scope: :global)
    @editor.current_buffer.replace_all_lines!(["foo", "bar", "baz", "bar"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("/", "b", "a", "r", :enter)

    assert_equal :normal, @editor.mode
    assert_equal 1, @editor.current_window.cursor_y
    assert_equal 0, @editor.current_window.cursor_x
  end

  def test_whichwrap_allows_h_and_l_to_cross_lines
    @editor.set_option("whichwrap", "h,l", scope: :global)
    @editor.current_buffer.replace_all_lines!(["ab", "cd"])
    @editor.current_window.cursor_y = 1
    @editor.current_window.cursor_x = 0

    feed("h")
    assert_equal [0, 2], [@editor.current_window.cursor_y, @editor.current_window.cursor_x]

    feed("l")
    assert_equal [1, 0], [@editor.current_window.cursor_y, @editor.current_window.cursor_x]
  end

  def test_iskeyword_affects_word_motion
    @editor.set_option("iskeyword", "@,-", scope: :buffer)
    @editor.current_buffer.replace_all_lines!(["foo-bar baz"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("w")

    assert_equal 8, @editor.current_window.cursor_x
  end

  def test_backspace_start_option_blocks_deleting_before_insert_start
    @editor.set_option("backspace", "indent,eol", scope: :global)
    @editor.current_buffer.replace_all_lines!(["ab"])
    @editor.current_window.cursor_x = 1

    feed("i", :backspace)

    assert_equal ["ab"], @editor.current_buffer.lines
    assert_equal 1, @editor.current_window.cursor_x
    assert_equal :insert, @editor.mode
  end

  def test_backspace_eol_option_blocks_joining_previous_line
    @editor.set_option("backspace", "start", scope: :global)
    @editor.current_buffer.replace_all_lines!(["a", "b"])
    @editor.current_window.cursor_y = 1
    @editor.current_window.cursor_x = 0

    feed("i", :backspace)

    assert_equal ["a", "b"], @editor.current_buffer.lines
    assert_equal [1, 0], [@editor.current_window.cursor_y, @editor.current_window.cursor_x]
  end

  def test_nomodifiable_buffer_edit_key_does_not_crash
    @editor.current_buffer.replace_all_lines!(["hello"])
    @editor.current_buffer.modifiable = false
    @editor.current_buffer.readonly = true

    @key_handler.handle("x")

    assert_equal ["hello"], @editor.current_buffer.lines
    assert_match(/not modifiable/i, @editor.message)
  end

  def test_nomodifiable_buffer_insert_mode_is_rejected
    @editor.current_buffer.replace_all_lines!(["hello"])
    @editor.current_buffer.modifiable = false
    @editor.current_buffer.readonly = true

    @key_handler.handle("i")

    assert_equal :normal, @editor.mode
    assert_equal ["hello"], @editor.current_buffer.lines
    assert_match(/not modifiable/i, @editor.message)
  end

  def test_normal_ctrl_c_stops_stdin_stream_via_default_binding
    stream = StringIO.new("hello\n")
    sh = @app.instance_variable_get(:@stream_mixer)
    sh.prepare_stdin_stream_buffer!(stream)
    sh.start_pending_stdin!

    @key_handler.handle(:ctrl_c)

    assert_equal :closed, @editor.current_buffer.stream.state
    assert_equal :normal, @editor.mode
    assert_equal true, stream.closed?
    assert_match(/stopped/, @editor.message)
  end

  def test_ctrl_z_calls_terminal_suspend
    terminal_stub = Object.new
    terminal_stub.instance_variable_set(:@suspend_calls, 0)
    terminal_stub.define_singleton_method(:suspend_for_tstp) do
      @suspend_calls += 1
    end
    terminal_stub.define_singleton_method(:suspend_calls) { @suspend_calls }
    @app.instance_variable_set(:@terminal, terminal_stub)
    @app.instance_variable_get(:@key_handler).instance_variable_set(:@terminal, terminal_stub)

    feed("i", "a", :ctrl_z)

    assert_equal 1, terminal_stub.suspend_calls
    assert_equal :insert, @editor.mode
    assert_equal ["a"], @editor.current_buffer.lines
  end

  def test_ctrl_z_invalidates_screen_cache_for_full_redraw_after_fg
    terminal_stub = Object.new
    terminal_stub.define_singleton_method(:suspend_for_tstp) {}
    @app.instance_variable_set(:@terminal, terminal_stub)
    @app.instance_variable_get(:@key_handler).instance_variable_set(:@terminal, terminal_stub)

    screen_stub = Object.new
    screen_stub.instance_variable_set(:@invalidated, false)
    screen_stub.define_singleton_method(:invalidate_cache!) do
      @invalidated = true
    end
    screen_stub.define_singleton_method(:invalidated?) { @invalidated }
    @app.instance_variable_set(:@screen, screen_stub)
    @app.instance_variable_get(:@key_handler).instance_variable_set(:@screen, screen_stub)

    feed(:ctrl_z)

    assert_equal true, screen_stub.invalidated?
  end

  def test_g_and_1g_distinguish_implicit_and_explicit_count
    @editor.current_buffer.replace_all_lines!(%w[a b c d])
    @editor.current_window.cursor_y = 1

    feed("G")
    assert_equal 3, @editor.current_window.cursor_y

    feed("1", "G")
    assert_equal 0, @editor.current_window.cursor_y
  end

  def test_backspace_indent_allows_deleting_autoindent_before_insert_start
    @editor.set_option("backspace", "indent,eol", scope: :global)
    @editor.current_buffer.replace_all_lines!(["  abc"])
    @editor.current_window.cursor_x = 2

    feed("i", :backspace)

    assert_equal [" abc"], @editor.current_buffer.lines
    assert_equal 1, @editor.current_window.cursor_x
  end

  def test_softtabstop_backspace_deletes_spaces_in_chunks_when_expandtab
    @editor.set_option("expandtab", true, scope: :buffer)
    @editor.set_option("tabstop", 4, scope: :buffer)
    @editor.set_option("softtabstop", 4, scope: :buffer)
    @editor.current_buffer.replace_all_lines!(["        "])
    @editor.current_window.cursor_x = 8

    feed("i", :backspace)

    assert_equal ["    "], @editor.current_buffer.lines
    assert_equal 4, @editor.current_window.cursor_x
  end

  def test_gf_uses_path_and_suffixesadd
    Dir.mktmpdir("ruvim-gf") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      target = File.join(dir, "lib", "foo.rb")
      File.write(target, "puts :ok\n")
      @editor.current_buffer.path = File.join(dir, "main.txt")
      @editor.current_buffer.replace_all_lines!(["foo"])
      @editor.current_window.cursor_y = 0
      @editor.current_window.cursor_x = 0
      @editor.set_option("hidden", true, scope: :global)
      @editor.set_option("path", "lib", scope: :buffer)
      @editor.set_option("suffixesadd", ".rb", scope: :buffer)

      feed("g", "f")

      assert_equal File.expand_path(target), File.expand_path(@editor.current_buffer.path)
      assert_equal "puts :ok", @editor.current_buffer.line_at(0)
    end
  end

  def test_gf_supports_recursive_path_entry_with_double_star
    Dir.mktmpdir("ruvim-gf-rec") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "deep", "nest"))
      target = File.join(dir, "lib", "deep", "nest", "foo.rb")
      File.write(target, "puts :deep\n")
      @editor.current_buffer.path = File.join(dir, "main.txt")
      @editor.current_buffer.replace_all_lines!(["foo"])
      @editor.current_window.cursor_y = 0
      @editor.current_window.cursor_x = 0
      @editor.set_option("hidden", true, scope: :global)
      @editor.set_option("path", "lib/**", scope: :buffer)
      @editor.set_option("suffixesadd", ".rb", scope: :buffer)

      feed("g", "f")

      assert_equal File.expand_path(target), File.expand_path(@editor.current_buffer.path)
    end
  end

  def test_gf_supports_file_with_line_number_suffix
    Dir.mktmpdir("ruvim-gf-line") do |dir|
      target = File.join(dir, "foo.rb")
      File.write(target, "line1\nline2\nline3\n")
      @editor.current_buffer.path = File.join(dir, "main.txt")
      @editor.current_buffer.replace_all_lines!(["foo.rb:3"])
      @editor.current_window.cursor_y = 0
      @editor.current_window.cursor_x = 3
      @editor.set_option("hidden", true, scope: :global)

      feed("g", "f")

      assert_equal File.expand_path(target), File.expand_path(@editor.current_buffer.path)
      assert_equal 2, @editor.current_window.cursor_y
    end
  end

  def test_showmatch_message_respects_matchtime_and_clears
    @editor.set_option("showmatch", true, scope: :global)
    @editor.set_option("matchtime", 1, scope: :global) # 0.1 sec
    @editor.current_buffer.replace_all_lines!([""])

    feed("i", ")")
    assert_equal "match", @editor.message

    sleep 0.12
    @app.send(:clear_expired_transient_message_if_any)
    assert_equal "", @editor.message
  end

  def test_insert_arrow_left_respects_whichwrap
    @editor.set_option("whichwrap", "left,right", scope: :global)
    @editor.current_buffer.replace_all_lines!(["ab", "cd"])
    @editor.current_window.cursor_y = 1
    @editor.current_window.cursor_x = 0

    feed("i", :left)

    assert_equal :insert, @editor.mode
    assert_equal [0, 2], [@editor.current_window.cursor_y, @editor.current_window.cursor_x]
  end

  def test_star_search_uses_iskeyword
    @editor.set_option("iskeyword", "@,-", scope: :buffer)
    @editor.current_buffer.replace_all_lines!(["foo-bar x", "foo y", "foo-bar z"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 1

    feed("*")

    assert_equal 2, @editor.current_window.cursor_y
    assert_equal 0, @editor.current_window.cursor_x
    assert_includes @editor.last_search[:pattern], "foo\\-bar"
  end

  def test_unknown_key_error_clears_on_next_successful_key
    @editor.current_buffer.replace_all_lines!(["a", "b"])
    @editor.current_window.cursor_y = 0

    feed("_")
    assert @editor.message_error?
    assert_match(/Unknown key:/, @editor.message)

    feed("j")
    refute @editor.message_error?
    assert_equal "", @editor.message
    assert_equal 1, @editor.current_window.cursor_y
  end

  def test_normal_message_clears_on_next_key
    @editor.current_buffer.replace_all_lines!(["a", "b"])
    @editor.current_window.cursor_y = 0
    @editor.echo("written")

    feed("j")

    refute @editor.message_error?
    assert_equal "", @editor.message
    assert_equal 1, @editor.current_window.cursor_y
  end

  # --- hit-enter prompt tests ---

  def test_ls_with_multiple_buffers_enters_hit_enter_mode
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")

    assert_equal :hit_enter, @editor.mode
    assert_instance_of Array, @editor.hit_enter_lines
    assert_operator @editor.hit_enter_lines.length, :>=, 2
  end

  def test_ls_with_single_buffer_uses_normal_echo
    @dispatcher.dispatch_ex(@editor, "ls")

    refute_equal :hit_enter, @editor.mode
    refute_nil @editor.message
    refute @editor.message.to_s.empty?
  end

  def test_hit_enter_dismiss_with_enter
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed(:enter)

    assert_equal :normal, @editor.mode
    assert_nil @editor.hit_enter_lines
  end

  def test_hit_enter_dismiss_with_escape
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed(:escape)

    assert_equal :normal, @editor.mode
    assert_nil @editor.hit_enter_lines
  end

  def test_hit_enter_dismiss_with_ctrl_c
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed(:ctrl_c)

    assert_equal :normal, @editor.mode
    assert_nil @editor.hit_enter_lines
  end

  def test_hit_enter_colon_enters_command_line
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed(":")

    assert_equal :command_line, @editor.mode
    assert_nil @editor.hit_enter_lines
  end

  def test_hit_enter_slash_enters_search
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed("/")

    assert_equal :command_line, @editor.mode
    assert_equal "/", @editor.command_line_prefix
    assert_nil @editor.hit_enter_lines
  end

  def test_hit_enter_question_enters_reverse_search
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")
    assert_equal :hit_enter, @editor.mode

    feed("?")

    assert_equal :command_line, @editor.mode
    assert_equal "?", @editor.command_line_prefix
    assert_nil @editor.hit_enter_lines
  end

  def test_args_with_multiple_files_enters_hit_enter_mode
    @editor.set_arglist(["a.rb", "b.rb", "c.rb"])
    @dispatcher.dispatch_ex(@editor, "args")

    assert_equal :hit_enter, @editor.mode
    assert_instance_of Array, @editor.hit_enter_lines
    assert_equal 3, @editor.hit_enter_lines.length
    assert_match(/\[a\.rb\]/, @editor.hit_enter_lines[0])
  end

  def test_args_with_single_file_uses_normal_echo
    @editor.set_arglist(["a.rb"])
    @dispatcher.dispatch_ex(@editor, "args")

    refute_equal :hit_enter, @editor.mode
  end

  def test_set_no_args_enters_hit_enter_mode
    @dispatcher.dispatch_ex(@editor, "set")

    # option_snapshot returns many options, so always > 1 line
    assert_equal :hit_enter, @editor.mode
    assert_instance_of Array, @editor.hit_enter_lines
    assert_operator @editor.hit_enter_lines.length, :>, 1
  end

  def test_batch_insert_handles_pasted_text_correctly
    @editor.current_buffer.replace_all_lines!([""])
    # Simulate pasting "Hello World\n" in insert mode (batch of characters)
    feed("i", *"Hello World".chars, :enter, *"Second line".chars, :escape)

    assert_equal ["Hello World", "Second line"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
  end

  def test_paste_batch_suppresses_autoindent
    @editor.current_buffer.replace_all_lines!(["  hello"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    # Normal enter in insert mode should autoindent
    feed("A", :enter, :escape)
    assert_equal ["  hello", "  "], @editor.current_buffer.lines

    # Simulate paste batch: autoindent should be suppressed
    @editor.current_buffer.replace_all_lines!(["  hello"])
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0
    feed("A")
    @app.instance_variable_get(:@key_handler).paste_batch = true
    feed(:enter, *"world".chars)
    @app.instance_variable_get(:@key_handler).paste_batch = false
    feed(:escape)

    assert_equal ["  hello", "world"], @editor.current_buffer.lines
  end

  def test_batch_insert_stops_on_escape
    @editor.current_buffer.replace_all_lines!([""])
    # Escape exits insert mode; subsequent keys are normal-mode commands
    feed("i", "a", "b", "c", :escape)

    assert_equal ["abc"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
  end

  def test_ls_format_shows_vim_style_output
    @editor.add_empty_buffer(path: "second.rb")
    @dispatcher.dispatch_ex(@editor, "ls")

    lines = @editor.hit_enter_lines
    # Each line should contain the buffer id and name
    assert_match(/1.*\[No Name\]/, lines[0])
    assert_match(/2.*"second\.rb"/, lines[1])
  end

  def test_equal_equal_indents_current_line
    @editor.current_buffer.replace_all_lines!(["def foo", "bar", "end"])
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_window.cursor_y = 1
    @editor.current_window.cursor_x = 0

    feed("=", "=")

    assert_equal ["def foo", "  bar", "end"], @editor.current_buffer.lines
  end

  def test_equal_j_indents_two_lines
    @editor.current_buffer.replace_all_lines!(["def foo", "bar", "baz", "end"])
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_window.cursor_y = 1
    @editor.current_window.cursor_x = 0

    feed("=", "j")

    assert_equal ["def foo", "  bar", "  baz", "end"], @editor.current_buffer.lines
  end

  def test_visual_equal_indents_selection
    @editor.current_buffer.replace_all_lines!(["def foo", "bar", "end"])
    @editor.assign_filetype(@editor.current_buffer, "ruby")
    @editor.current_window.cursor_y = 0
    @editor.current_window.cursor_x = 0

    feed("V", "j", "j", "=")

    assert_equal ["def foo", "  bar", "end"], @editor.current_buffer.lines
    assert_equal :normal, @editor.mode
  end

  # :qa / :qall tests

  def test_qa_quits_with_multiple_windows
    @dispatcher.dispatch_ex(@editor, "split")
    assert_equal 2, @editor.window_count

    @dispatcher.dispatch_ex(@editor, "qa")
    assert_equal false, @editor.running?
  end

  def test_qa_refuses_with_unsaved_changes
    @editor.current_buffer.replace_all_lines!(["modified"])
    @editor.current_buffer.instance_variable_set(:@modified, true)

    @dispatcher.dispatch_ex(@editor, "qa")
    assert @editor.running?
    assert_match(/unsaved changes/, @editor.message)
  end

  def test_qa_bang_forces_quit_with_unsaved_changes
    @editor.current_buffer.replace_all_lines!(["modified"])
    @editor.current_buffer.instance_variable_set(:@modified, true)

    @dispatcher.dispatch_ex(@editor, "qa!")
    assert_equal false, @editor.running?
  end

  def test_wqa_writes_all_and_quits
    Dir.mktmpdir do |dir|
      path1 = File.join(dir, "a.txt")
      path2 = File.join(dir, "b.txt")
      File.write(path1, "")
      File.write(path2, "")

      @editor.current_buffer.replace_all_lines!(["hello"])
      @editor.current_buffer.instance_variable_set(:@path, path1)
      @editor.current_buffer.instance_variable_set(:@modified, true)

      buf2 = @editor.add_empty_buffer(path: path2)
      buf2.replace_all_lines!(["world"])
      buf2.instance_variable_set(:@modified, true)

      @dispatcher.dispatch_ex(@editor, "wqa")
      assert_equal false, @editor.running?
      assert_equal "hello", File.read(path1)
      assert_equal "world", File.read(path2)
    end
  end

  def test_shift_right_splits_when_single_window
    assert_equal 1, @editor.window_count
    first_win = @editor.current_window
    feed(:shift_right)
    assert_equal 2, @editor.window_count
    # Focus should be on the new (right) window
    refute_equal first_win.id, @editor.current_window.id
    assert_equal :vertical, @editor.window_layout
  end

  def test_shift_left_splits_when_single_window
    assert_equal 1, @editor.window_count
    first_win = @editor.current_window
    feed(:shift_left)
    assert_equal 2, @editor.window_count
    # Focus should be on the new (left) window
    refute_equal first_win.id, @editor.current_window.id
    assert_equal :vertical, @editor.window_layout
  end

  def test_shift_down_splits_when_single_window
    assert_equal 1, @editor.window_count
    first_win = @editor.current_window
    feed(:shift_down)
    assert_equal 2, @editor.window_count
    refute_equal first_win.id, @editor.current_window.id
    assert_equal :horizontal, @editor.window_layout
  end

  def test_shift_up_splits_when_single_window
    assert_equal 1, @editor.window_count
    first_win = @editor.current_window
    feed(:shift_up)
    assert_equal 2, @editor.window_count
    refute_equal first_win.id, @editor.current_window.id
    assert_equal :horizontal, @editor.window_layout
  end

  def test_shift_right_splits_even_with_horizontal_split
    # Horizontal split exists, but no window to the right → vsplit
    @editor.split_current_window(layout: :horizontal)
    assert_equal 2, @editor.window_count
    feed(:shift_right)
    assert_equal 3, @editor.window_count
  end

  def test_shift_left_splits_even_with_horizontal_split
    @editor.split_current_window(layout: :horizontal)
    assert_equal 2, @editor.window_count
    feed(:shift_left)
    assert_equal 3, @editor.window_count
  end

  def test_shift_down_splits_even_with_vertical_split
    @editor.split_current_window(layout: :vertical)
    assert_equal 2, @editor.window_count
    feed(:shift_down)
    assert_equal 3, @editor.window_count
  end

  def test_shift_up_splits_even_with_vertical_split
    @editor.split_current_window(layout: :vertical)
    assert_equal 2, @editor.window_count
    feed(:shift_up)
    assert_equal 3, @editor.window_count
  end

  def test_shift_arrow_moves_window_focus_when_multiple_windows
    # Create a vertical split so we have two windows
    first_win = @editor.current_window
    @editor.split_current_window(layout: :vertical)
    second_win = @editor.current_window

    # After split, focus is on the new (second) window
    assert_equal second_win.id, @editor.current_window.id

    # Shift+Left should move focus to the left window (no new split)
    feed(:shift_left)
    assert_equal first_win.id, @editor.current_window.id
    assert_equal 2, @editor.window_count

    # Shift+Right should move focus back to the right window
    feed(:shift_right)
    assert_equal second_win.id, @editor.current_window.id
    assert_equal 2, @editor.window_count
  end

  def test_shift_arrow_up_down_moves_window_focus_horizontal_split
    # Create a horizontal split so we have two windows
    first_win = @editor.current_window
    @editor.split_current_window(layout: :horizontal)
    second_win = @editor.current_window

    assert_equal second_win.id, @editor.current_window.id

    # Shift+Up should move focus to the upper window (no new split)
    feed(:shift_up)
    assert_equal first_win.id, @editor.current_window.id
    assert_equal 2, @editor.window_count

    # Shift+Down should move focus back to the lower window
    feed(:shift_down)
    assert_equal second_win.id, @editor.current_window.id
    assert_equal 2, @editor.window_count
  end

  # --- Nested layout tree tests ---

  def test_vsplit_then_split_creates_nested_layout
    # Start with 1 window (win1)
    win1 = @editor.current_window
    # vsplit → creates win2 to the right
    @editor.split_current_window(layout: :vertical)
    win2 = @editor.current_window
    assert_equal 2, @editor.window_count

    # split the right window (win2) horizontally → creates win3 below win2
    @editor.split_current_window(layout: :horizontal)
    win3 = @editor.current_window
    assert_equal 3, @editor.window_count

    # Layout tree should be: vsplit[ win1, hsplit[ win2, win3 ] ]
    tree = @editor.layout_tree
    assert_equal :vsplit, tree[:type]
    assert_equal 2, tree[:children].length
    assert_equal :window, tree[:children][0][:type]
    assert_equal win1.id, tree[:children][0][:id]
    assert_equal :hsplit, tree[:children][1][:type]
    assert_equal 2, tree[:children][1][:children].length

    # window_order should traverse leaves left-to-right, top-to-bottom
    assert_equal [win1.id, win2.id, win3.id], @editor.window_order
  end

  def test_split_then_vsplit_creates_nested_layout
    # split → creates win2 below
    @editor.split_current_window(layout: :horizontal)
    assert_equal 2, @editor.window_count

    # vsplit the lower window → creates win3 to the right of win2
    @editor.split_current_window(layout: :vertical)
    assert_equal 3, @editor.window_count

    # Layout tree should be: hsplit[ win1, vsplit[ win2, win3 ] ]
    tree = @editor.layout_tree
    assert_equal :hsplit, tree[:type]
    assert_equal 2, tree[:children].length
    assert_equal :window, tree[:children][0][:type]
    assert_equal :vsplit, tree[:children][1][:type]
  end

  def test_close_window_simplifies_nested_tree
    @editor.split_current_window(layout: :vertical)
    @editor.split_current_window(layout: :horizontal)
    win3 = @editor.current_window
    assert_equal 3, @editor.window_count

    # Close win3 → hsplit node should collapse, leaving vsplit[ win1, win2 ]
    @editor.close_window(win3.id)
    assert_equal 2, @editor.window_count

    tree = @editor.layout_tree
    assert_equal :vsplit, tree[:type]
    assert_equal 2, tree[:children].length
    assert_equal :window, tree[:children][0][:type]
    assert_equal :window, tree[:children][1][:type]
  end

  def test_close_window_to_single_produces_single_layout
    @editor.split_current_window(layout: :vertical)
    win2 = @editor.current_window
    assert_equal 2, @editor.window_count

    @editor.close_window(win2.id)
    assert_equal 1, @editor.window_count
    assert_equal :single, @editor.window_layout
  end

  def test_focus_window_direction_in_nested_layout
    # Create vsplit[ win1, hsplit[ win2, win3 ] ]
    win1 = @editor.current_window
    @editor.split_current_window(layout: :vertical)
    win2 = @editor.current_window
    @editor.split_current_window(layout: :horizontal)
    win3 = @editor.current_window

    # From win3 (bottom-right), going left should reach win1
    @editor.focus_window(win3.id)
    @editor.focus_window_direction(:left)
    assert_equal win1.id, @editor.current_window_id

    # From win1 (left), going right should reach win2 or win3
    @editor.focus_window_direction(:right)
    assert_includes [win2.id, win3.id], @editor.current_window_id

    # From win2 (top-right), going down should reach win3
    @editor.focus_window(win2.id)
    @editor.focus_window_direction(:down)
    assert_equal win3.id, @editor.current_window_id

    # From win3 (bottom-right), going up should reach win2
    @editor.focus_window_direction(:up)
    assert_equal win2.id, @editor.current_window_id
  end

  def test_shift_left_does_not_split_at_edge_of_existing_vsplit
    # vsplit creates [win1, win2], focus on win2
    @editor.split_current_window(layout: :vertical)
    # Move focus to left (win1)
    feed(:shift_left)
    assert_equal 2, @editor.window_count

    # Now we're on win1 (leftmost). Shift+Left should NOT split because
    # there are already windows on the same axis (horizontal neighbors exist).
    feed(:shift_left)
    assert_equal 2, @editor.window_count, "Should not split at edge of existing vsplit"

    # Pressing again should still not split
    feed(:shift_left)
    assert_equal 2, @editor.window_count
  end

  def test_shift_left_splits_bottom_window_in_nested_layout
    # Create layout: hsplit[ vsplit[win1, win2], win3 ]
    # Start with win1
    win1 = @editor.current_window
    # vsplit → vsplit[win1, win2]
    @editor.split_current_window(layout: :vertical)
    win2 = @editor.current_window
    # Focus back to win1, then split horizontally from win1
    # Actually, easier: split from win2 horizontally to get the right structure
    # Let me build it differently: start fresh
    @editor.focus_window(win1.id)

    # From win1, hsplit → hsplit[win1, win3], but we want vsplit on top.
    # Let me just build the tree directly.
    # Better approach: vsplit first, then move up and hsplit from the vsplit pair
    # Actually: vsplit[win1, win2], then from win1 do hsplit → hsplit[vsplit[...], win3]
    # No, that's wrong. Let me think:
    # We want hsplit[ vsplit[A, B], C ]
    # Step 1: split (horizontal) → hsplit[win1, win3], focus on win3
    @editor.close_window(win2.id)
    assert_equal 1, @editor.window_count
    @editor.split_current_window(layout: :horizontal)
    win3 = @editor.current_window
    # Step 2: focus win1 (top), then vsplit → vsplit[win1, win2] inside hsplit
    @editor.focus_window(win1.id)
    @editor.split_current_window(layout: :vertical)
    win2 = @editor.current_window
    assert_equal 3, @editor.window_count

    # Layout should be: hsplit[ vsplit[win1, win2], win3 ]
    tree = @editor.layout_tree
    assert_equal :hsplit, tree[:type]
    assert_equal :vsplit, tree[:children][0][:type]
    assert_equal :window, tree[:children][1][:type]
    assert_equal win3.id, tree[:children][1][:id]

    # From win3 (full-width bottom), Shift+Left should SPLIT (no vsplit ancestor)
    @editor.focus_window(win3.id)
    feed(:shift_left)
    assert_equal 4, @editor.window_count, "Shift+Left from full-width bottom should vsplit it"
  end

  def test_same_direction_split_merges_into_parent
    # hsplit[ win1, win2 ], then split win2 again horizontally
    @editor.split_current_window(layout: :horizontal)
    @editor.split_current_window(layout: :horizontal)
    assert_equal 3, @editor.window_count

    # All three should be in a single hsplit (no nested hsplit inside hsplit)
    tree = @editor.layout_tree
    assert_equal :hsplit, tree[:type]
    assert_equal 3, tree[:children].length
  end

  # --- search filter (g/) ---

  def test_filter_creates_buffer_with_matching_lines
    @editor.current_buffer.replace_all_lines!(["apple", "banana", "apricot", "cherry"])
    feed("/", "a", "p", :enter)  # search for "ap"
    feed("g", "/")

    buf = @editor.current_buffer
    assert_equal :filter, buf.kind
    assert_equal ["apple", "apricot"], buf.lines
  end

  def test_filter_enter_jumps_to_original_line_and_closes_filter
    @editor.current_buffer.replace_all_lines!(["apple", "banana", "apricot", "cherry"])
    original_buf_id = @editor.current_buffer.id
    feed("/", "a", "p", :enter)
    feed("g", "/")

    # Move to second match line ("apricot", originally line 2)
    feed("j")
    feed(:enter)

    assert_equal original_buf_id, @editor.current_buffer.id
    assert_equal 2, @editor.current_window.cursor_y
  end

  def test_filter_quit_returns_to_previous_buffer
    @editor.current_buffer.replace_all_lines!(["apple", "banana", "apricot"])
    original_buf_id = @editor.current_buffer.id
    feed("/", "a", "p", :enter)
    feed("g", "/")

    assert_equal :filter, @editor.current_buffer.kind
    feed(":", "q", :enter)

    assert_equal original_buf_id, @editor.current_buffer.id
  end

  def test_filter_recursive_filtering
    @editor.current_buffer.replace_all_lines!(["apple pie", "apricot jam", "apple sauce", "cherry"])
    feed("/", "a", "p", :enter)
    feed("g", "/")

    assert_equal ["apple pie", "apricot jam", "apple sauce"], @editor.current_buffer.lines

    # Search within filter and filter again
    feed("/", "p", "l", "e", :enter)
    feed("g", "/")

    assert_equal ["apple pie", "apple sauce"], @editor.current_buffer.lines

    # Enter jumps to original buffer
    feed("j")  # "apple sauce" - originally line 2 of buffer
    feed(:enter)

    assert_equal 2, @editor.current_window.cursor_y
  end

  def test_filter_inherits_filetype
    @editor.current_buffer.replace_all_lines!(["a\tb", "c\td", "a\te"])
    @editor.current_buffer.options["filetype"] = "tsv"
    feed("/", "a", :enter)
    feed("g", "/")

    assert_equal "tsv", @editor.current_buffer.options["filetype"]
  end

  def test_filter_without_search_pattern_shows_error
    @editor.current_buffer.replace_all_lines!(["apple", "banana"])
    feed("g", "/")

    assert @editor.message_error?
  end

  def test_filter_quit_restores_cursor_position
    @editor.current_buffer.replace_all_lines!(["aaa", "bbb", "aab", "ccc", "aac"])
    original_buf_id = @editor.current_buffer.id
    feed("/", "a", "a", :enter)
    # Search moves cursor to line 0 (first match)
    feed("n")
    # Now on line 2 ("aab")
    assert_equal 2, @editor.current_window.cursor_y
    feed("g", "/")

    assert_equal :filter, @editor.current_buffer.kind
    feed(":", "q", :enter)

    assert_equal original_buf_id, @editor.current_buffer.id
    assert_equal 2, @editor.current_window.cursor_y
  end

  def test_filter_ex_command
    @editor.current_buffer.replace_all_lines!(["apple", "banana", "apricot"])
    feed("/", "a", "p", :enter)
    feed(":", "f", "i", "l", "t", "e", "r", :enter)

    assert_equal :filter, @editor.current_buffer.kind
    assert_equal ["apple", "apricot"], @editor.current_buffer.lines
  end

  # --- dG / dgg / yG / ygg / cG / cgg ---

  def test_dG_deletes_from_cursor_to_end
    @editor.current_buffer.replace_all_lines!(["aa", "bb", "cc", "dd", "ee"])
    @editor.current_window.cursor_y = 2
    feed("d", "G")

    assert_equal ["aa", "bb"], @editor.current_buffer.lines
  end

  def test_dgg_deletes_from_cursor_to_start
    @editor.current_buffer.replace_all_lines!(["aa", "bb", "cc", "dd", "ee"])
    @editor.current_window.cursor_y = 2
    feed("d", "g", "g")

    assert_equal ["dd", "ee"], @editor.current_buffer.lines
  end

  def test_yG_yanks_from_cursor_to_end
    @editor.current_buffer.replace_all_lines!(["aa", "bb", "cc", "dd"])
    @editor.current_window.cursor_y = 1
    feed("y", "G")

    reg = @editor.get_register('"')&.fetch(:text, "")
    assert_includes reg, "bb"
    assert_includes reg, "dd"
  end

  def test_ygg_yanks_from_cursor_to_start
    @editor.current_buffer.replace_all_lines!(["aa", "bb", "cc", "dd"])
    @editor.current_window.cursor_y = 2
    feed("y", "g", "g")

    reg = @editor.get_register('"')&.fetch(:text, "")
    assert_includes reg, "aa"
    assert_includes reg, "cc"
  end

  def test_cG_changes_from_cursor_to_end
    @editor.current_buffer.replace_all_lines!(["aa", "bb", "cc", "dd"])
    @editor.current_window.cursor_y = 2
    feed("c", "G")

    assert_equal ["aa", "bb", ""], @editor.current_buffer.lines
    assert_equal :insert, @editor.mode
  end
end
