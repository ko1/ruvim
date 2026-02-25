module RuVim
  class Context
    attr_reader :editor, :invocation

    def initialize(editor:, invocation: nil)
      @editor = editor
      @invocation = invocation
    end

    def window
      editor.current_window
    end

    def buffer
      editor.current_buffer
    end

  end
end
