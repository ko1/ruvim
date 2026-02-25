module RuVim
  class CommandLine
    attr_reader :prefix, :text, :cursor

    def initialize
      reset(prefix: ":")
    end

    def reset(prefix: ":")
      @prefix = prefix
      @text = +""
      @cursor = 0
    end

    def clear
      @text.clear
      @cursor = 0
    end

    def replace_text(str)
      @text = str.to_s.dup
      @cursor = @text.length
    end

    def replace_span(start_idx, end_idx, replacement, cursor_at: :end)
      s = [[start_idx.to_i, 0].max, @text.length].min
      e = [[end_idx.to_i, s].max, @text.length].min
      rep = replacement.to_s
      @text = @text[0...s].to_s + rep + @text[e..].to_s
      @cursor =
        case cursor_at
        when :start then s
        when Integer then [[cursor_at, 0].max, @text.length].min
        else
          s + rep.length
        end
    end

    def insert(str)
      @text.insert(@cursor, str)
      @cursor += str.length
    end

    def backspace
      return if @cursor.zero?

      @text.slice!(@cursor - 1)
      @cursor -= 1
    end

    def move_left
      @cursor -= 1 if @cursor.positive?
    end

    def move_right
      @cursor += 1 if @cursor < @text.length
    end

    def content
      "#{@prefix}#{@text}"
    end
  end
end
