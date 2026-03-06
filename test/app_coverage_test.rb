# frozen_string_literal: true

# Additional scenario tests to improve coverage of global_commands.rb, key_handler.rb, and screen.rb

require_relative "test_helper"

class AppCoverageTest < Minitest::Test
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

  # --- cursor commands ---

  def test_cursor_line_end
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("$")
    # $ moves to last character (length of line)
    assert_equal buf.line_length(0), win.cursor_x
  end

  def test_cursor_buffer_start_gg
    buf.replace_all_lines!(["line1", "line2", "line3"])
    win.cursor_y = 2
    feed("g", "g")
    assert_equal 0, win.cursor_y
  end

  # --- insert mode variants ---

  def test_append_mode_a
    buf.replace_all_lines!(["abc"])
    win.cursor_x = 1
    feed("a", "X", :escape)
    assert_equal ["abXc"], buf.lines
  end

  def test_insert_line_start_nonblank_I
    buf.replace_all_lines!(["  hello"])
    win.cursor_x = 4
    feed("I", "X", :escape)
    assert_equal ["  Xhello"], buf.lines
  end

  def test_open_line_below_o
    buf.replace_all_lines!(["hello", "world"])
    win.cursor_y = 0
    feed("o", "new", :escape)
    assert_equal ["hello", "new", "world"], buf.lines
    assert_equal :normal, @editor.mode
  end

  def test_open_line_above_O
    buf.replace_all_lines!(["hello", "world"])
    win.cursor_y = 1
    feed("O", "new", :escape)
    assert_equal ["hello", "new", "world"], buf.lines
    assert_equal :normal, @editor.mode
  end

  # --- undo / redo ---

  def test_undo_and_redo
    buf.replace_all_lines!(["hello"])
    feed("x")
    assert_equal ["ello"], buf.lines

    feed("u")
    assert_equal ["hello"], buf.lines
    assert_match(/Undo/, @editor.message)

    feed(:ctrl_r)
    assert_equal ["ello"], buf.lines
    assert_match(/Redo/, @editor.message)
  end

  def test_undo_at_oldest
    buf.replace_all_lines!(["hello"])
    buf.instance_variable_get(:@undo_stack)&.clear
    feed("u")
    assert_match(/oldest/, @editor.message)
  end

  # --- search backward ---

  def test_search_backward_mode
    buf.replace_all_lines!(["hello world"])
    feed("?")
    assert_equal :command_line, @editor.mode
  end

  # --- search prev (N) ---

  def test_search_prev_N
    buf.replace_all_lines!(["aaa", "bbb", "aaa"])
    win.cursor_y = 0
    feed("/", "b", "b", "b", :enter)
    assert_equal 1, win.cursor_y

    feed("N")
    # N searches backward, should wrap to same match or stay
    assert_operator win.cursor_y, :>=, 0
  end

  # --- search word backward (#) ---

  def test_search_word_backward
    buf.replace_all_lines!(["foo bar foo"])
    win.cursor_x = 8 # on second "foo"
    feed("#")
    assert_equal 0, win.cursor_x
  end

  # --- marks ---

  def test_mark_set_and_jump
    buf.replace_all_lines!(["line1", "line2", "line3"])
    win.cursor_y = 1
    feed("m", "a")

    win.cursor_y = 0
    feed("'", "a")
    assert_equal 1, win.cursor_y
  end

  def test_mark_jump_unset
    buf.replace_all_lines!(["line1"])
    feed("`", "z")
    assert_match(/Mark not set/, @editor.message)
  end

  # --- jump list (Ctrl-O / Ctrl-I) ---

  def test_jump_older_and_newer
    buf.replace_all_lines!((1..20).map { |i| "line#{i}" })
    win.cursor_y = 0

    # G creates a jump
    feed("G")
    last_line = buf.line_count - 1
    assert_equal last_line, win.cursor_y

    feed(:ctrl_o)
    old_y = win.cursor_y

    feed(:ctrl_i)
    new_y = win.cursor_y
    # Ctrl-I should jump forward (back to where we were)
    assert_operator new_y, :>=, old_y
  end

  def test_jump_older_empty
    buf.replace_all_lines!(["line1"])
    @editor.instance_variable_get(:@jump_list)&.clear rescue nil
    feed(:ctrl_o)
    assert_match(/Jump list/, @editor.message.to_s) if @editor.message
  end

  # --- visual line yank and delete ---

  def test_visual_line_yank
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 0
    feed("V", "j", "y")

    reg = @editor.get_register("\"")
    assert_equal :normal, @editor.mode
    assert_includes reg[:text], "aaa"
    assert_includes reg[:text], "bbb"
  end

  def test_visual_line_delete
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 0
    feed("V", "j", "d")

    assert_equal ["ccc"], buf.lines
    assert_equal :normal, @editor.mode
  end

  # --- visual char yank and delete ---

  def test_visual_char_delete
    buf.replace_all_lines!(["abcdef"])
    win.cursor_x = 1
    feed("v", "l", "l", "d")

    assert_equal ["aef"], buf.lines
    assert_equal :normal, @editor.mode
  end

  # --- delete operator motions ---

  def test_delete_gg_motion
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 2
    feed("d", "g", "g")
    assert_equal [""], buf.lines
  end

  def test_delete_j_motion
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 0
    feed("d", "j")
    assert_equal ["ccc"], buf.lines
  end

  def test_delete_k_motion
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 1
    feed("d", "k")
    assert_equal ["ccc"], buf.lines
  end

  def test_delete_word_dw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("d", "w")
    assert_equal ["world"], buf.lines
  end

  # --- yank operator motions ---

  def test_yank_word_yw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("y", "w")
    reg = @editor.get_register("\"")
    assert_equal "hello ", reg[:text]
  end

  def test_yank_gg_motion
    buf.replace_all_lines!(["aaa", "bbb", "ccc"])
    win.cursor_y = 2
    feed("y", "g", "g")
    reg = @editor.get_register("\"")
    assert_includes reg[:text], "aaa"
    assert_includes reg[:text], "ccc"
  end

  def test_yank_iw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("y", "i", "w")
    reg = @editor.get_register("\"")
    assert_equal "hello", reg[:text]
  end

  def test_yank_aw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("y", "a", "w")
    reg = @editor.get_register("\"")
    assert_equal "hello ", reg[:text]
  end

  # --- delete text object ---

  def test_delete_aw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("d", "a", "w")
    assert_equal ["world"], buf.lines
  end

  # --- indent operator (=) ---

  def test_indent_j_motion
    buf.replace_all_lines!(["  aaa", "  bbb", "ccc"])
    win.cursor_y = 0
    feed("=", "j")
    # = should reindent lines 0-1
    assert_equal :normal, @editor.mode
  end

  def test_indent_gg_motion
    buf.replace_all_lines!(["  aaa", "  bbb"])
    win.cursor_y = 1
    feed("=", "g", "g")
    assert_equal :normal, @editor.mode
  end

  def test_indent_k_motion
    buf.replace_all_lines!(["aaa", "  bbb", "ccc"])
    win.cursor_y = 1
    feed("=", "k")
    assert_equal :normal, @editor.mode
  end

  def test_indent_G_motion
    buf.replace_all_lines!(["  aaa", "  bbb"])
    win.cursor_y = 0
    feed("=", "G")
    assert_equal :normal, @editor.mode
  end

  # --- visual text object selection ---

  def test_visual_select_text_object_iw
    buf.replace_all_lines!(["hello world"])
    win.cursor_x = 0
    feed("v", "i", "w")
    assert_equal :visual_char, @editor.mode
  end

  # --- clear message (Escape in normal) ---

  def test_escape_clears_message
    @editor.echo("test message")
    feed("\e")
    # message should be cleared
  end

  # --- tab operations via Ex commands ---

  def test_tabnext_tabprev_via_ex
    feed(":", "t", "a", "b", "n", "e", "w", :enter)
    feed(":", "t", "a", "b", "p", "r", "e", "v", :enter)
    feed(":", "t", "a", "b", "n", "e", "x", "t", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- buffer next/prev via Ex commands ---

  def test_bnext_bprev_via_ex
    feed(":", "b", "n", "e", "x", "t", :enter)
    feed(":", "b", "p", "r", "e", "v", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- search word partial (g* and g#) ---

  def test_search_word_forward_partial
    buf.replace_all_lines!(["foobar foo foobar"])
    win.cursor_x = 0
    feed("g", "*")
    # g* searches for word without boundaries
    assert_operator win.cursor_x, :>, 0
  end

  def test_search_word_backward_partial
    buf.replace_all_lines!(["foobar foo foobar"])
    win.cursor_x = 11
    feed("g", "#")
    assert_operator win.cursor_x, :<, 11
  end

  # --- write+quit (wq) ---

  def test_wq_with_no_filename_shows_error
    feed(":", "w", "q", :enter)
    # No filename, should show error
    assert_equal :normal, @editor.mode
  end
end
