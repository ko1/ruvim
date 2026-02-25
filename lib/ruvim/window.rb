module RuVim
  class Window
    attr_reader :id
    attr_accessor :buffer_id, :row_offset, :col_offset
    attr_reader :cursor_x, :cursor_y
    attr_reader :options

    def initialize(id:, buffer_id:)
      @id = id
      @buffer_id = buffer_id
      @cursor_x = 0
      @cursor_y = 0
      @row_offset = 0
      @col_offset = 0
      @preferred_x = nil
      @options = {}
    end

    def cursor_x=(value)
      @cursor_x = value.to_i
      @preferred_x = nil
    end

    def cursor_y=(value)
      @cursor_y = value.to_i
    end

    def clamp_to_buffer(buffer, max_extra_col: 0)
      @cursor_y = [[@cursor_y, 0].max, buffer.line_count - 1].min
      max_col = buffer.line_length(@cursor_y) + [max_extra_col.to_i, 0].max
      @cursor_x = [[@cursor_x, 0].max, max_col].min
      self
    end

    def move_left(buffer, count = 1)
      @preferred_x = nil
      count.times do
        break if @cursor_x <= 0
        @cursor_x = RuVim::TextMetrics.previous_grapheme_char_index(buffer.line_at(@cursor_y), @cursor_x)
      end
      clamp_to_buffer(buffer)
    end

    def move_right(buffer, count = 1)
      @preferred_x = nil
      count.times do
        line = buffer.line_at(@cursor_y)
        break if @cursor_x >= line.length
        @cursor_x = RuVim::TextMetrics.next_grapheme_char_index(line, @cursor_x)
      end
      clamp_to_buffer(buffer)
    end

    def move_up(buffer, count = 1)
      desired_x = @preferred_x || @cursor_x
      @cursor_y -= count
      clamp_to_buffer(buffer)
      @cursor_x = [desired_x, buffer.line_length(@cursor_y)].min
      @preferred_x = desired_x
    end

    def move_down(buffer, count = 1)
      desired_x = @preferred_x || @cursor_x
      @cursor_y += count
      clamp_to_buffer(buffer)
      @cursor_x = [desired_x, buffer.line_length(@cursor_y)].min
      @preferred_x = desired_x
    end

    def ensure_visible(buffer, height:, width:, tabstop: 2, scrolloff: 0, sidescrolloff: 0)
      clamp_to_buffer(buffer)
      so = [[scrolloff.to_i, 0].max, [height.to_i - 1, 0].max].min

      top_target = @cursor_y - so
      bottom_target = @cursor_y + so
      @row_offset = top_target if top_target < @row_offset
      @row_offset = bottom_target - height + 1 if bottom_target >= @row_offset + height
      @row_offset = 0 if @row_offset.negative?

      line = buffer.line_at(@cursor_y)
      cursor_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, @cursor_x, tabstop:)
      offset_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, @col_offset, tabstop:)
      sso = [[sidescrolloff.to_i, 0].max, [width.to_i - 1, 0].max].min

      if cursor_screen_col < offset_screen_col + sso
        target_left = [cursor_screen_col - sso, 0].max
        @col_offset = RuVim::TextMetrics.char_index_for_screen_col(line, target_left, tabstop:)
      elsif cursor_screen_col >= offset_screen_col + width - sso
        target_left = cursor_screen_col - width + sso + 1
        @col_offset = RuVim::TextMetrics.char_index_for_screen_col(line, target_left, tabstop:, align: :ceil)
      end
      @col_offset = 0 if @col_offset.negative?
    end

  end
end
