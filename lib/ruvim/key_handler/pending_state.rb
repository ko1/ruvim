# frozen_string_literal: true

module RuVim
  class KeyHandler
    module PendingState
      private

      # --- Operator pending ---

      def start_operator_pending(name)
        @operator_pending = { name:, count: @editor.pending_count }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo(name == :delete ? "d" : name.to_s)
      end

      def handle_operator_pending_key(token)
        op = @operator_pending
        if %w[i a g].include?(token) && !op[:motion_prefix]
          @operator_pending[:motion_prefix] = token
          @editor.echo("#{op[:name].to_s[0]}#{token}")
          return
        end

        motion = [op[:motion_prefix], token].compact.join
        @operator_pending = nil

        if token == "\e"
          @editor.clear_message
          return
        end

        if op[:name] == :delete && motion == "d"
          inv = CommandInvocation.new(id: "buffer.delete_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(op[:count], ["d", "d"]))
          return
        end

        if op[:name] == :delete
          inv = CommandInvocation.new(id: "buffer.delete_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(op[:count], ["d", *motion.each_char.to_a]))
          return
        end

        if op[:name] == :yank && motion == "y"
          inv = CommandInvocation.new(id: "buffer.yank_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :yank
          inv = CommandInvocation.new(id: "buffer.yank_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :indent && motion == "="
          inv = CommandInvocation.new(id: "buffer.indent_lines", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :indent
          inv = CommandInvocation.new(id: "buffer.indent_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        if op[:name] == :change && motion == "c"
          inv = CommandInvocation.new(id: "buffer.change_line", count: op[:count])
          @dispatcher.dispatch(@editor, inv)
          begin_dot_change_capture(count_prefixed_keys(op[:count], ["c", "c"])) if @editor.mode == :insert
          return
        end

        if op[:name] == :change
          inv = CommandInvocation.new(id: "buffer.change_motion", count: op[:count], kwargs: { motion: motion })
          @dispatcher.dispatch(@editor, inv)
          begin_dot_change_capture(count_prefixed_keys(op[:count], ["c", *motion.each_char.to_a])) if @editor.mode == :insert
          return
        end

        @editor.echo_error("Unknown operator")
      end

      # --- Register / mark / jump pending ---

      def start_register_pending
        @register_pending = true
        @editor.echo('"')
      end

      def finish_register_pending(token)
        @register_pending = false
        if token.is_a?(String) && token.length == 1
          @editor.set_active_register(token)
          @editor.echo(%("#{token}))
        else
          @editor.echo_error("Invalid register")
        end
      end

      def start_mark_pending
        @mark_pending = true
        @editor.echo("m")
      end

      def finish_mark_pending(token)
        @mark_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && token.match?(/\A[A-Za-z]\z/)
          @editor.echo_error("Invalid mark")
          return
        end

        inv = CommandInvocation.new(id: "mark.set", kwargs: { mark: token })
        @dispatcher.dispatch(@editor, inv)
      end

      def start_jump_pending(linewise:, repeat_token:)
        @jump_pending = { linewise: linewise, repeat_token: repeat_token }
        @editor.echo(repeat_token)
      end

      def finish_jump_pending(token)
        pending = @jump_pending
        @jump_pending = nil
        return unless pending
        if token == "\e"
          @editor.clear_message
          return
        end

        if token == pending[:repeat_token]
          inv = CommandInvocation.new(id: "jump.older", kwargs: { linewise: pending[:linewise] })
          @dispatcher.dispatch(@editor, inv)
          return
        end

        unless token.is_a?(String) && token.match?(/\A[A-Za-z]\z/)
          @editor.echo_error("Invalid mark")
          return
        end

        inv = CommandInvocation.new(id: "mark.jump", kwargs: { mark: token, linewise: pending[:linewise] })
        @dispatcher.dispatch(@editor, inv)
      end

      # --- Replace pending ---

      def start_replace_pending
        @replace_pending = { count: @editor.pending_count }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo("r")
      end

      def handle_replace_pending_key(token)
        pending = @replace_pending
        @replace_pending = nil
        if token == "\e"
          @editor.clear_message
          return
        end

        if token.is_a?(String) && !token.empty?
          inv = CommandInvocation.new(id: "buffer.replace_char", argv: [token], count: pending[:count])
          @dispatcher.dispatch(@editor, inv)
          record_last_change_keys(count_prefixed_keys(pending[:count], ["r", token]))
        else
          @editor.echo("r expects one character")
        end
      end

      # --- Find character on line ---

      def start_find_pending(token)
        @find_pending = {
          direction: (token == "f" || token == "t") ? :forward : :backward,
          till: (token == "t" || token == "T"),
          count: @editor.pending_count
        }
        @editor.pending_count = nil
        @pending_keys = []
        @editor.echo(token)
      end

      def finish_find_pending(token)
        pending = @find_pending
        @find_pending = nil
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && !token.empty?
          @editor.echo("find expects one character")
          return
        end

        moved = perform_find_on_line(
          char: token,
          direction: pending[:direction],
          till: pending[:till],
          count: pending[:count]
        )
        if moved
          @editor.set_last_find(char: token, direction: pending[:direction], till: pending[:till])
        else
          @editor.echo("Char not found: #{token}")
        end
      end

      def repeat_last_find(reverse:)
        last = @editor.last_find
        unless last
          @editor.echo("No previous f/t")
          return
        end

        direction =
          if reverse
            last[:direction] == :forward ? :backward : :forward
          else
            last[:direction]
          end
        count = @editor.pending_count
        @editor.pending_count = nil
        @pending_keys = []
        moved = perform_find_on_line(char: last[:char], direction:, till: last[:till], count:)
        @editor.echo("Char not found: #{last[:char]}") unless moved
      end

      def perform_find_on_line(char:, direction:, till:, count:)
        win = @editor.current_window
        buf = @editor.current_buffer
        line = buf.line_at(win.cursor_y)
        pos = win.cursor_x
        target = nil

        [count.to_i, 1].max.times do
          idx =
            if direction == :forward
              line.index(char, pos + 1)
            else
              rindex_from(line, char, pos - 1)
            end
          return false if idx.nil?

          target = idx
          pos = idx
        end

        if till
          target =
            if direction == :forward
              RuVim::TextMetrics.previous_grapheme_char_index(line, target)
            else
              RuVim::TextMetrics.next_grapheme_char_index(line, target)
            end
        end

        win.cursor_x = target
        win.clamp_to_buffer(buf)
        true
      end

      def rindex_from(line, char, pos)
        return nil if pos.negative?

        line.rindex(char, pos)
      end
    end
  end
end
