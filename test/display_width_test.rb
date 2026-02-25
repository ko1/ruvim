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
end
