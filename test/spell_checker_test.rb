# frozen_string_literal: true

require_relative "test_helper"
require "ruvim/spell_checker"

class SpellCheckerTest < Minitest::Test
  def setup
    @checker = RuVim::SpellChecker.instance
  end

  def test_common_english_words_are_valid
    %w[the hello world commit fix update add remove change].each do |word|
      assert @checker.valid?(word), "Expected '#{word}' to be valid"
    end
  end

  def test_misspelled_words_are_invalid
    %w[teh helo wrold comit].each do |word|
      refute @checker.valid?(word), "Expected '#{word}' to be invalid"
    end
  end

  def test_case_insensitive
    assert @checker.valid?("Hello")
    assert @checker.valid?("HELLO")
    assert @checker.valid?("hello")
  end

  def test_single_letters_are_valid
    ("a".."z").each do |ch|
      assert @checker.valid?(ch), "Expected '#{ch}' to be valid"
    end
  end

  def test_numbers_are_valid
    assert @checker.valid?("123")
    assert @checker.valid?("42")
  end

  def test_empty_and_nil
    assert @checker.valid?("")
    assert @checker.valid?(nil)
  end

  def test_misspelled_words_in_line
    result = @checker.misspelled_words("helo wrold this is a tset")
    words = result.map { |m| m[:word] }
    assert_includes words, "helo"
    assert_includes words, "wrold"
    assert_includes words, "tset"
    refute_includes words, "this"
    refute_includes words, "is"
    refute_includes words, "a"
  end

  def test_misspelled_words_returns_positions
    result = @checker.misspelled_words("helo world")
    assert_equal 1, result.length
    assert_equal "helo", result[0][:word]
    assert_equal 0, result[0][:col]
    assert_equal 4, result[0][:length]
  end

  def test_misspelled_words_skips_comment_lines
    result = @checker.misspelled_words("# helo wrold bad speling")
    assert_empty result
  end

  def test_misspelled_words_skips_short_words
    # Words with 1 char are always valid
    result = @checker.misspelled_words("x y z")
    assert_empty result
  end

  def test_words_with_apostrophe
    assert @checker.valid?("don't")
    assert @checker.valid?("it's")
  end

  def test_spell_highlight_cols
    cols = @checker.spell_highlight_cols("helo world", source_col_offset: 0)
    # "helo" at cols 0..3 should be highlighted
    assert cols[0], "col 0 should be highlighted"
    assert cols[1], "col 1 should be highlighted"
    assert cols[2], "col 2 should be highlighted"
    assert cols[3], "col 3 should be highlighted"
    # "world" should not
    refute cols[5], "col 5 should not be highlighted"
  end

  def test_spell_highlight_cols_with_offset
    cols = @checker.spell_highlight_cols("helo world", source_col_offset: 10)
    assert cols[10], "col 10 should be highlighted (offset applied)"
    refute cols[0], "col 0 should not be highlighted"
  end

  def test_extra_programming_words_are_valid
    %w[refactor repo todo api config github ci merge rebase].each do |word|
      assert @checker.valid?(word), "Expected '#{word}' to be valid"
    end
  end
end

class SpellOptionTest < Minitest::Test
  def test_spell_option_default_is_false
    editor = fresh_editor
    refute editor.effective_option("spell")
  end

  def test_spell_option_can_be_set
    editor = fresh_editor
    editor.set_option("spell", true)
    assert editor.effective_option("spell")
  end

  def test_spelllang_option_default_is_en
    editor = fresh_editor
    assert_equal "en", editor.effective_option("spelllang")
  end

  def test_spell_checker_is_singleton
    checker = RuVim::SpellChecker.instance
    assert_instance_of RuVim::SpellChecker, checker
    assert_same checker, RuVim::SpellChecker.instance
  end

  def test_gitcommit_filetype_enables_spell
    editor = fresh_editor
    buf = editor.add_virtual_buffer(
      kind: :git_commit,
      name: "[Commit Message]",
      lines: ["test"],
      filetype: "gitcommit",
      readonly: false,
      modifiable: true
    )
    assert_equal true, buf.options["spell"]
  end
end

class SpellNavigationTest < Minitest::Test
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

  def test_spell_next_jumps_to_misspelled_word
    buf.replace_all_lines!(["hello wrold this is tset"])
    @editor.set_option("spell", true, scope: :buffer)
    win.cursor_x = 0
    win.cursor_y = 0
    feed("]", "s")
    # Should jump to "wrold" at col 6
    assert_equal 0, win.cursor_y
    assert_equal 6, win.cursor_x
  end

  def test_spell_prev_jumps_to_misspelled_word
    buf.replace_all_lines!(["helo world wrold"])
    @editor.set_option("spell", true, scope: :buffer)
    win.cursor_y = 0
    win.cursor_x = 15
    feed("[", "s")
    # Should jump to "wrold" at col 11
    assert_equal 0, win.cursor_y
    assert_equal 11, win.cursor_x
  end

  def test_spell_next_wraps_around
    buf.replace_all_lines!(["helo world", "good text"])
    @editor.set_option("spell", true, scope: :buffer)
    win.cursor_y = 1
    win.cursor_x = 0
    feed("]", "s")
    # Should wrap to "helo" at line 0, col 0
    assert_equal 0, win.cursor_y
    assert_equal 0, win.cursor_x
  end

  def test_spell_next_across_lines
    buf.replace_all_lines!(["hello world", "this is tset"])
    @editor.set_option("spell", true, scope: :buffer)
    win.cursor_y = 0
    win.cursor_x = 0
    feed("]", "s")
    # Should jump to "tset" on line 1
    assert_equal 1, win.cursor_y
    assert_equal 8, win.cursor_x
  end
end
