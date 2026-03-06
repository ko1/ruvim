# frozen_string_literal: true

require_relative "test_helper"

class KeywordCharsTest < Minitest::Test
  def setup
    # Clear caches between tests
    RuVim::KeywordChars.instance_variable_set(:@char_class_cache, nil)
    RuVim::KeywordChars.instance_variable_set(:@regex_cache, nil)
  end

  # --- char_class ---

  def test_char_class_default_for_empty
    assert_equal "[:alnum:]_", RuVim::KeywordChars.char_class("")
  end

  def test_char_class_default_for_nil
    assert_equal "[:alnum:]_", RuVim::KeywordChars.char_class(nil)
  end

  def test_char_class_single_char
    result = RuVim::KeywordChars.char_class("-")
    assert_includes result, "[:alnum:]_"
    assert_includes result, "\\-"
  end

  def test_char_class_range
    result = RuVim::KeywordChars.char_class("65-90")
    assert_includes result, "[:alnum:]_"
    # Should include A-Z range
    assert_includes result, "A-Z"
  end

  def test_char_class_reversed_range
    # minmax should handle reversed ranges
    result = RuVim::KeywordChars.char_class("90-65")
    assert_includes result, "A-Z"
  end

  def test_char_class_skips_at_sign
    result = RuVim::KeywordChars.char_class("@")
    assert_equal "[:alnum:]_", result
  end

  def test_char_class_skips_out_of_range
    result = RuVim::KeywordChars.char_class("256-300")
    assert_equal "[:alnum:]_", result
  end

  def test_char_class_mixed_spec
    result = RuVim::KeywordChars.char_class("-,65-90")
    assert_includes result, "\\-"
    assert_includes result, "A-Z"
  end

  def test_char_class_caches_result
    result1 = RuVim::KeywordChars.char_class("-")
    result2 = RuVim::KeywordChars.char_class("-")
    assert_same result1, result2
  end

  # --- regex ---

  def test_regex_default_for_empty
    assert_equal RuVim::KeywordChars::DEFAULT_REGEX, RuVim::KeywordChars.regex("")
  end

  def test_regex_default_for_nil
    assert_equal RuVim::KeywordChars::DEFAULT_REGEX, RuVim::KeywordChars.regex(nil)
  end

  def test_regex_matches_with_spec
    re = RuVim::KeywordChars.regex("-")
    assert_match re, "a"
    assert_match re, "-"
    refute_match re, " "
  end

  def test_regex_caches_result
    result1 = RuVim::KeywordChars.regex("-")
    result2 = RuVim::KeywordChars.regex("-")
    assert_same result1, result2
  end
end
