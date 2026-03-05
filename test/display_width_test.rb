require_relative "test_helper"

class DisplayWidthTest < Minitest::Test
  def test_ambiguous_width_cache_tracks_env_changes
    prev = ENV["RUVIM_AMBIGUOUS_WIDTH"]
    ENV["RUVIM_AMBIGUOUS_WIDTH"] = nil
    assert_equal 1, RuVim::DisplayWidth.cell_width("Ω")

    ENV["RUVIM_AMBIGUOUS_WIDTH"] = "2"
    assert_equal 2, RuVim::DisplayWidth.cell_width("Ω")
  ensure
    if prev.nil?
      ENV.delete("RUVIM_AMBIGUOUS_WIDTH")
    else
      ENV["RUVIM_AMBIGUOUS_WIDTH"] = prev
    end
  end

  def test_zero_codepoint_returns_zero
    assert_equal 0, RuVim::DisplayWidth.uncached_codepoint_width(0)
  end

  def test_expand_tabs_basic
    assert_equal "  hello", RuVim::DisplayWidth.expand_tabs("\thello", tabstop: 2)
  end

  def test_expand_tabs_mid_column
    assert_equal "a hello", RuVim::DisplayWidth.expand_tabs("a\thello", tabstop: 2)
  end

  def test_expand_tabs_with_tabstop_4
    assert_equal "    hello", RuVim::DisplayWidth.expand_tabs("\thello", tabstop: 4)
  end

  def test_expand_tabs_preserves_non_tab_chars
    assert_equal "hello", RuVim::DisplayWidth.expand_tabs("hello", tabstop: 2)
  end

  def test_expand_tabs_with_start_col
    result = RuVim::DisplayWidth.expand_tabs("\tx", tabstop: 4, start_col: 1)
    assert_equal "   x", result
  end

  def test_wide_codepoint_cjk
    assert_equal 2, RuVim::DisplayWidth.cell_width("漢")
  end

  def test_wide_codepoint_fullwidth_form
    assert_equal 2, RuVim::DisplayWidth.cell_width("Ａ")
  end

  def test_combining_mark_returns_zero
    assert_equal 0, RuVim::DisplayWidth.cell_width("\u0300")
  end

  def test_zero_width_joiner_returns_zero
    assert_equal 0, RuVim::DisplayWidth.cell_width("\u200D")
  end
end
