require_relative "test_helper"

class SearchOptionTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    def write(_data); end
  end

  def setup
    @editor = RuVim::Editor.new
    @buf = @editor.add_empty_buffer
    @win = @editor.add_window(buffer_id: @buf.id)
    @gc = RuVim::GlobalCommands.instance
  end

  def test_ignorecase_and_smartcase_affect_search_regex
    regex = @gc.send(:compile_search_regex, "abc", editor: @editor, window: @win, buffer: @buf)
    refute regex.match?("ABC")

    @editor.set_option("ignorecase", true, scope: :global)
    regex = @gc.send(:compile_search_regex, "abc", editor: @editor, window: @win, buffer: @buf)
    assert regex.match?("ABC")

    @editor.set_option("smartcase", true, scope: :global)
    regex = @gc.send(:compile_search_regex, "Abc", editor: @editor, window: @win, buffer: @buf)
    refute regex.match?("abc")
  end

  def test_hlsearch_option_controls_search_highlight
    screen = RuVim::Screen.new(terminal: TerminalStub.new([10, 40]))
    @editor.set_last_search(pattern: "foo", direction: :forward)

    cols = screen.send(:search_highlight_source_cols, @editor, "foo bar", source_col_offset: 0)
    assert_equal true, cols[0]

    @editor.set_option("hlsearch", false, scope: :global)
    cols = screen.send(:search_highlight_source_cols, @editor, "foo bar", source_col_offset: 0)
    assert_equal({}, cols)
  end
end
