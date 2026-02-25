require_relative "test_helper"

class TextMetricsTest < Minitest::Test
  def test_grapheme_navigation_uses_cluster_boundaries
    s = "e\u0301x" # e + combining acute + x

    assert_equal 0, RuVim::TextMetrics.previous_grapheme_char_index(s, 2)
    assert_equal 2, RuVim::TextMetrics.next_grapheme_char_index(s, 0)
    assert_equal 3, RuVim::TextMetrics.next_grapheme_char_index(s, 2)
  end

  def test_screen_col_for_char_index_handles_wide_chars
    s = "ab日本"
    assert_equal 0, RuVim::TextMetrics.screen_col_for_char_index(s, 0)
    assert_equal 2, RuVim::TextMetrics.screen_col_for_char_index(s, 2)
    assert_equal 4, RuVim::TextMetrics.screen_col_for_char_index(s, 3)
    assert_equal 6, RuVim::TextMetrics.screen_col_for_char_index(s, 4)
  end

  def test_clip_cells_for_width_expands_tabs_and_preserves_source_col
    cells, used = RuVim::TextMetrics.clip_cells_for_width("a\tb", 4, source_col_start: 0, tabstop: 4)
    assert_equal 4, used
    assert_equal ["a", " ", " ", " "], cells.map(&:glyph)
    assert_equal [0, 1, 1, 1], cells.map(&:source_col)
  end

  def test_char_index_for_screen_col_is_grapheme_aligned
    s = "ab日本c"
    assert_equal 0, RuVim::TextMetrics.char_index_for_screen_col(s, 0)
    assert_equal 2, RuVim::TextMetrics.char_index_for_screen_col(s, 2)
    assert_equal 2, RuVim::TextMetrics.char_index_for_screen_col(s, 3) # inside wide char => start of 日本 cluster char
    assert_equal 3, RuVim::TextMetrics.char_index_for_screen_col(s, 4)
    assert_equal 4, RuVim::TextMetrics.char_index_for_screen_col(s, 6)
    assert_equal 3, RuVim::TextMetrics.char_index_for_screen_col(s, 3, align: :ceil)
  end

  def test_pad_plain_to_screen_width_handles_japanese
    out = RuVim::TextMetrics.pad_plain_to_screen_width("日本", 6, tabstop: 2)
    assert_equal 6, RuVim::DisplayWidth.display_width(out, tabstop: 2)
    assert_equal "日本  ", out
  end
end
