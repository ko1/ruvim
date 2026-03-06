# frozen_string_literal: true

require_relative "test_helper"

class AppExCommandTest < Minitest::Test
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

  # --- :set ---

  def test_set_number_on_off
    feed(":", "s", "e", "t", " ", "n", "u", "m", "b", "e", "r", :enter)
    assert @editor.get_option("number")

    feed(":", "s", "e", "t", " ", "n", "o", "n", "u", "m", "b", "e", "r", :enter)
    refute @editor.get_option("number")
  end

  def test_set_tabstop_value
    feed(":", "s", "e", "t", " ", "t", "a", "b", "s", "t", "o", "p", "=", "8", :enter)
    assert_equal 8, @editor.get_option("tabstop")
  end

  def test_set_option_query
    feed(":", "s", "e", "t", " ", "n", "u", "m", "b", "e", "r", "?", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :bindings ---

  def test_bindings_command
    feed(":", "b", "i", "n", "d", "i", "n", "g", "s", :enter)
    assert_equal :normal, @editor.mode
  end

  def test_bindings_with_mode_filter
    feed(":", "b", "i", "n", "d", "i", "n", "g", "s", " ", "n", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :tabnew / :tabnext / :tabprev ---

  def test_tabnext_tabprev_via_ex
    feed(":", "t", "a", "b", "n", "e", "w", :enter)
    feed(":", "t", "a", "b", "p", "r", "e", "v", :enter)
    feed(":", "t", "a", "b", "n", "e", "x", "t", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :bnext / :bprev ---

  def test_bnext_bprev_via_ex
    feed(":", "b", "n", "e", "x", "t", :enter)
    feed(":", "b", "p", "r", "e", "v", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :copen / :cclose / :cprev / :lclose / :lprev ---

  def test_copen_and_cclose
    feed(":", "c", "o", "p", "e", "n", :enter)
    feed(":", "c", "c", "l", "o", "s", "e", :enter)
    assert_equal :normal, @editor.mode
  end

  def test_cprev_with_empty_list
    feed(":", "c", "p", "r", "e", "v", :enter)
    assert_equal :normal, @editor.mode
  end

  def test_lclose_without_open
    feed(":", "l", "c", "l", "o", "s", "e", :enter)
    assert_equal :normal, @editor.mode
  end

  def test_lprev_with_empty_list
    feed(":", "l", "p", "r", "e", "v", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :args ---

  def test_arglist_operations
    feed(":", "a", "r", "g", "s", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :wq ---

  def test_wq_with_no_filename_shows_error
    feed(":", "w", "q", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :edit ---

  def test_edit_no_file_reloads_or_errors
    feed(":", "e", "d", "i", "t", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- :split / :vsplit + window focus ---

  def test_window_focus_after_split
    feed(":", "s", "p", "l", "i", "t", :enter)
    original_win_id = @editor.current_window.id

    feed(:ctrl_w, "w")
    refute_equal original_win_id, @editor.current_window.id

    feed(:ctrl_w, "j")
    feed(:ctrl_w, "k")
    assert_equal :normal, @editor.mode
  end

  def test_window_focus_left_right
    feed(":", "v", "s", "p", "l", "i", "t", :enter)
    feed(:ctrl_w, "h")
    feed(:ctrl_w, "l")
    assert_equal :normal, @editor.mode
  end

  # --- :b# (alternate buffer) ---

  def test_buffer_alternate_hash
    feed(":", "s", "p", "l", "i", "t", :enter)
    feed(":", "b", "#", :enter)
    assert_equal :normal, @editor.mode
  end

  # --- rich view toggle ---

  def test_rich_toggle
    buf.replace_all_lines!(["hello world"])
    feed("g", "r")
    assert_equal :normal, @editor.mode
  end
end
