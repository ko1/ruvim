require_relative "test_helper"

class InputScreenIntegrationTest < Minitest::Test
  TerminalStub = Struct.new(:winsize) do
    attr_reader :writes

    def write(data)
      @writes ||= []
      @writes << data
    end
  end

  class FakeTTY
    def initialize(bytes)
      @bytes = bytes.dup
    end

    def getch
      @bytes.slice!(0)
    end

    def read_nonblock(_n)
      raise IO::WaitReadable if @bytes.empty?

      @bytes.slice!(0)
    end

    def ready?
      !@bytes.empty?
    end
  end

  def test_input_pagedown_to_app_and_screen_render
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!
    editor.current_buffer.replace_all_lines!((1..30).map { |i| "line #{i}" })

    term = TerminalStub.new([8, 40])
    screen = RuVim::Screen.new(terminal: term)
    app.instance_variable_set(:@screen, screen)

    stdin = FakeTTY.new("\e[6~")
    input = RuVim::Input.new(stdin: stdin)

    io_sc = IO.singleton_class
    verbose, $VERBOSE = $VERBOSE, nil
    io_sc.alias_method(:__orig_select_for_input_screen_test, :select)
    io_sc.define_method(:select) do |readers, *_rest|
      ready = Array(readers).select { |io| io.respond_to?(:ready?) && io.ready? }
      ready.empty? ? nil : [ready, [], []]
    end

    begin
      key = input.read_key(timeout: 0.2)
      assert_equal :pagedown, key

      app.send(:handle_normal_key, key)
      screen.render(editor)

      assert_operator editor.current_window.cursor_y, :>, 0
      assert_includes term.writes.last, "line "
    ensure
      io_sc.alias_method(:select, :__orig_select_for_input_screen_test)
      io_sc.remove_method(:__orig_select_for_input_screen_test) rescue nil
      $VERBOSE = verbose
    end
  end
end
