# frozen_string_literal: true

module RuVim
  class Editor
    module MarksJumps
      def current_location
        { buffer_id: current_buffer.id, row: current_window.cursor_y, col: current_window.cursor_x }
      end

      def set_mark(name, window = current_window)
        mark = name.to_s
        return false unless mark.match?(/\A[A-Za-z]\z/)

        loc = { buffer_id: window.buffer_id, row: window.cursor_y, col: window.cursor_x }
        if mark.match?(/\A[a-z]\z/)
          @local_marks[window.buffer_id][mark] = loc
        else
          @global_marks[mark] = loc
        end
        true
      end

      def mark_location(name, buffer_id: current_buffer.id)
        mark = name.to_s
        return nil unless mark.match?(/\A[A-Za-z]\z/)

        if mark.match?(/\A[a-z]\z/)
          @local_marks[buffer_id][mark]
        else
          @global_marks[mark]
        end
      end

      def push_jump_location(location = current_location)
        loc = normalize_location(location)
        return nil unless loc

        if @jump_index && @jump_index < @jumplist.length - 1
          @jumplist = @jumplist[0..@jump_index]
        end
        @jumplist << loc unless same_location?(@jumplist.last, loc)
        @jump_index = @jumplist.length - 1 unless @jumplist.empty?
        loc
      end

      def jump_older(linewise: false)
        return nil if @jumplist.empty?

        if @jump_index.nil?
          push_jump_location(current_location)
        else
          @jump_index = [@jump_index - 1, 0].max
        end
        jump_to_location(@jumplist[@jump_index], linewise:)
      end

      def jump_newer(linewise: false)
        return nil if @jumplist.empty? || @jump_index.nil?

        next_idx = @jump_index + 1
        return nil if next_idx >= @jumplist.length

        @jump_index = next_idx
        jump_to_location(@jumplist[@jump_index], linewise:)
      end

      def jump_to_mark(name, linewise: false)
        loc = mark_location(name)
        return nil unless loc

        jump_to_location(loc, linewise:)
      end

      def jump_to_location(loc, linewise: false)
        location = normalize_location(loc)
        return nil unless location
        return nil unless @buffers.key?(location[:buffer_id])

        switch_to_buffer(location[:buffer_id]) if current_buffer.id != location[:buffer_id]
        current_window.cursor_y = location[:row]
        current_window.cursor_x = linewise ? 0 : location[:col]
        current_window.clamp_to_buffer(current_buffer)
        current_window.cursor_x = first_nonblank_col(current_buffer, current_window.cursor_y) if linewise
        current_window.clamp_to_buffer(current_buffer)
        current_location
      end

      private

      def first_nonblank_col(buffer, row)
        line = buffer.line_at(row)
        line.index(/\S/) || 0
      end

      def normalize_location(loc)
        return nil unless loc

        {
          buffer_id: Integer(loc[:buffer_id] || loc["buffer_id"]),
          row: [Integer(loc[:row] || loc["row"]), 0].max,
          col: [Integer(loc[:col] || loc["col"]), 0].max
        }
      rescue StandardError
        nil
      end

      def same_location?(a, b)
        return false unless a && b

        a[:buffer_id] == b[:buffer_id] && a[:row] == b[:row] && a[:col] == b[:col]
      end
    end
  end
end
