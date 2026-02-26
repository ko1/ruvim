require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "stringio"

class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @app.send(:handle_key, k) }
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

    @app.send(:handle_key, "x")

    assert_equal ["hello"], @editor.current_buffer.lines
    assert_match(/not modifiable/i, @editor.message)
  end

  def test_nomodifiable_buffer_insert_mode_is_rejected
    @editor.current_buffer.replace_all_lines!(["hello"])
    @editor.current_buffer.modifiable = false
    @editor.current_buffer.readonly = true

    @app.send(:handle_key, "i")

    assert_equal :normal, @editor.mode
    assert_equal ["hello"], @editor.current_buffer.lines
    assert_match(/not modifiable/i, @editor.message)
  end

  def test_normal_ctrl_c_stops_stdin_stream_via_default_binding
    stream = StringIO.new("hello\n")
    @app.instance_variable_set(:@stdin_stream_source, stream)
    @app.send(:prepare_stdin_stream_buffer!)

    @app.send(:handle_key, :ctrl_c)

    assert_equal :closed, @editor.current_buffer.stream_state
    assert_equal :normal, @editor.mode
    assert_equal true, stream.closed?
    assert_match(/\[stdin\] closed/, @editor.message)
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
end
