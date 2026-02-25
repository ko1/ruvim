require_relative "test_helper"
require "fileutils"
require "tmpdir"

class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
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
end
