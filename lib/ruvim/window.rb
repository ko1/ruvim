module RuVim
  class Window
    attr_reader :id
    attr_accessor :buffer_id, :cursor_x, :cursor_y, :row_offset, :col_offset
    attr_reader :options

    def initialize(id:, buffer_id:)
      @id = id
      @buffer_id = buffer_id
      @cursor_x = 0
      @cursor_y = 0
      @row_offset = 0
      @col_offset = 0
      @options = {}
    end

    def clamp_to_buffer(buffer)
      @cursor_y = [[@cursor_y, 0].max, buffer.line_count - 1].min
      @cursor_x = [[@cursor_x, 0].max, buffer.line_length(@cursor_y)].min
      self
    end

    def move_left(buffer, count = 1)
      count.times do
        break if @cursor_x <= 0
        @cursor_x = RuVim::TextMetrics.previous_grapheme_char_index(buffer.line_at(@cursor_y), @cursor_x)
      end
      clamp_to_buffer(buffer)
    end

    def move_right(buffer, count = 1)
      count.times do
        line = buffer.line_at(@cursor_y)
        break if @cursor_x >= line.length
        @cursor_x = RuVim::TextMetrics.next_grapheme_char_index(line, @cursor_x)
      end
      clamp_to_buffer(buffer)
    end

    def move_up(buffer, count = 1)
      @cursor_y -= count
      clamp_to_buffer(buffer)
    end

    def move_down(buffer, count = 1)
      @cursor_y += count
      clamp_to_buffer(buffer)
    end

    def ensure_visible(buffer, height:, width:, tabstop: 2)
      clamp_to_buffer(buffer)

      @row_offset = @cursor_y if @cursor_y < @row_offset
      @row_offset = @cursor_y - height + 1 if @cursor_y >= @row_offset + height
      @row_offset = 0 if @row_offset.negative?

      line = buffer.line_at(@cursor_y)
      cursor_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, @cursor_x, tabstop:)
      offset_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, @col_offset, tabstop:)

      if cursor_screen_col < offset_screen_col
        @col_offset = RuVim::TextMetrics.char_index_for_screen_col(line, cursor_screen_col, tabstop:)
      elsif cursor_screen_col >= offset_screen_col + width
        target_left = cursor_screen_col - width + 1
        @col_offset = RuVim::TextMetrics.char_index_for_screen_col(line, target_left, tabstop:, align: :ceil)
      end
      @col_offset = 0 if @col_offset.negative?
    end

  end
end
