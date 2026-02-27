require_relative "test_helper"

class HighlighterTest < Minitest::Test
  def test_ruby_highlighter_marks_keyword_and_string
    cols = RuVim::Highlighter.color_columns("ruby", 'def x; "hi"; end')
    refute_empty cols
    assert_equal "\e[36m", cols[0] # "def"
    assert_equal "\e[32m", cols[7] # opening quote
  end

  def test_json_highlighter_marks_key_and_number
    cols = RuVim::Highlighter.color_columns("json", '{"a": 10}')
    assert_equal "\e[36m", cols[1] # key chars
    assert_equal "\e[33m", cols[6] # number start
  end

  def test_ruby_highlighter_marks_instance_variables_and_constants
    cols = RuVim::Highlighter.color_columns("ruby", "@x = Foo")
    assert_equal "\e[93m", cols[0] # @x
    assert_equal "\e[96m", cols[5] # F
  end
end
