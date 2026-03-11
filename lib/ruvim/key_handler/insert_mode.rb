# frozen_string_literal: true

module RuVim
  class KeyHandler
    module InsertMode
      private

      def handle_insert_key(key)
        case key
        when :escape
          finish_insert_change_group
          finish_dot_change_capture
          @completion.clear_insert_completion
          @editor.enter_normal_mode
          @editor.echo("")
        when :backspace
          @completion.clear_insert_completion
          return unless insert_backspace_allowed?
          insert_backspace_in_insert_mode
        when :ctrl_n
          @completion.insert_complete(+1)
        when :ctrl_p
          @completion.insert_complete(-1)
        when :ctrl_i
          @completion.clear_insert_completion
          insert_tab_in_insert_mode
        when :enter
          @completion.clear_insert_completion
          y, x = @editor.current_buffer.insert_newline(@editor.current_window.cursor_y, @editor.current_window.cursor_x)
          x = apply_insert_autoindent(y, x, previous_row: y - 1)
          @editor.current_window.cursor_y = y
          @editor.current_window.cursor_x = x
        when :left
          @completion.clear_insert_completion
          dispatch_insert_cursor_motion("cursor.left")
        when :right
          @completion.clear_insert_completion
          dispatch_insert_cursor_motion("cursor.right")
        when :up
          @completion.clear_insert_completion
          @editor.current_window.move_up(@editor.current_buffer, 1)
        when :down
          @completion.clear_insert_completion
          @editor.current_window.move_down(@editor.current_buffer, 1)
        when :pageup, :pagedown
          @completion.clear_insert_completion
          invoke_page_key(key)
        else
          return unless key.is_a?(String)

          @completion.clear_insert_completion
          @editor.current_buffer.insert_char(@editor.current_window.cursor_y, @editor.current_window.cursor_x, key)
          @editor.current_window.cursor_x += 1
          maybe_showmatch_after_insert(key)
          maybe_dedent_after_insert(key)
        end
      end

      def finish_insert_change_group
        @editor.current_buffer.end_change_group
      end

      def insert_backspace_allowed?
        buf = @editor.current_buffer
        win = @editor.current_window
        row = win.cursor_y
        col = win.cursor_x
        return false if row.zero? && col.zero?

        opt = @editor.effective_option("backspace", window: win, buffer: buf).to_s
        allow = opt.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
        allow_all = allow.include?("2")
        allow_indent = allow_all || allow.include?("indent")

        if col.zero? && row.positive?
          return true if allow_all || allow.include?("eol")

          @editor.echo_error("backspace=eol required")
          return false
        end

        if @insert_start_location
          same_buf = @insert_start_location[:buffer_id] == buf.id
          if same_buf && (row < @insert_start_location[:row] || (row == @insert_start_location[:row] && col <= @insert_start_location[:col]))
            if allow_all || allow.include?("start")
              return true
            end

            if allow_indent && same_row_autoindent_backspace?(buf, row, col)
              return true
            end

            @editor.echo_error("backspace=start required")
            return false
          end
        end

        true
      end

      def insert_backspace_in_insert_mode
        buf = @editor.current_buffer
        win = @editor.current_window
        row = win.cursor_y
        col = win.cursor_x

        if row >= 0 && col.positive? && try_softtabstop_backspace(buf, win)
          return
        end

        y, x = buf.backspace(row, col)
        win.cursor_y = y
        win.cursor_x = x
      end

      def dispatch_insert_cursor_motion(id)
        @dispatcher.dispatch(@editor, CommandInvocation.new(id: id, count: 1))
      rescue StandardError => e
        @editor.echo_error("Motion error: #{e.message}")
      end

      def try_softtabstop_backspace(buf, win)
        row = win.cursor_y
        col = win.cursor_x
        line = buf.line_at(row)
        return false unless line
        return false unless @editor.effective_option("expandtab", window: win, buffer: buf)

        sts = @editor.effective_option("softtabstop", window: win, buffer: buf).to_i
        sts = @editor.effective_option("tabstop", window: win, buffer: buf).to_i if sts <= 0
        return false if sts <= 0

        prefix = line[0...col].to_s
        m = prefix.match(/ +\z/)
        return false unless m

        run = m[0].length
        return false if run <= 1

        tabstop = effective_tabstop(win, buf)
        cur_screen = RuVim::TextMetrics.screen_col_for_char_index(line, col, tabstop:)
        target_screen = [cur_screen - sts, 0].max
        target_col = RuVim::TextMetrics.char_index_for_screen_col(line, target_screen, tabstop:, align: :floor)
        delete_cols = col - target_col
        delete_cols = [delete_cols, run, sts].min
        return false if delete_cols <= 1

        run_start = col - run
        target_col = [target_col, run_start].max
        delete_cols = col - target_col
        return false if delete_cols <= 1

        buf.delete_span(row, target_col, row, col)
        win.cursor_x = target_col
        true
      rescue StandardError
        false
      end

      def same_row_autoindent_backspace?(buf, row, col)
        return false unless @insert_start_location
        return false unless row == @insert_start_location[:row]
        return false unless col <= @insert_start_location[:col]

        line = buf.line_at(row)
        line[0...@insert_start_location[:col]].to_s.match?(/\A[ \t]*\z/)
      rescue StandardError
        false
      end

      def insert_tab_in_insert_mode
        buf = @editor.current_buffer
        win = @editor.current_window
        if @editor.effective_option("expandtab", window: win, buffer: buf)
          width = @editor.effective_option("softtabstop", window: win, buffer: buf).to_i
          width = @editor.effective_option("tabstop", window: win, buffer: buf).to_i if width <= 0
          width = 2 if width <= 0
          line = buf.line_at(win.cursor_y)
          current_col = RuVim::TextMetrics.screen_col_for_char_index(line, win.cursor_x, tabstop: effective_tabstop(win, buf))
          spaces = width - (current_col % width)
          spaces = width if spaces <= 0
          _y, x = buf.insert_text(win.cursor_y, win.cursor_x, " " * spaces)
          win.cursor_x = x
        else
          buf.insert_char(win.cursor_y, win.cursor_x, "\t")
          win.cursor_x += 1
        end
      end

      def apply_insert_autoindent(row, x, previous_row:)
        return x if @paste_batch
        buf = @editor.current_buffer
        win = @editor.current_window
        return x unless @editor.effective_option("autoindent", window: win, buffer: buf)
        return x if previous_row.negative?

        prev = buf.line_at(previous_row)
        indent = prev[/\A[ \t]*/].to_s
        if @editor.effective_option("smartindent", window: win, buffer: buf)
          trimmed = prev.rstrip
          needs_indent = trimmed.end_with?("{", "[", "(")
          if !needs_indent
            needs_indent = buf.lang_module.indent_trigger?(trimmed)
          end
          if needs_indent
            sw = @editor.effective_option("shiftwidth", window: win, buffer: buf).to_i
            sw = effective_tabstop(win, buf) if sw <= 0
            sw = 2 if sw <= 0
            indent += " " * sw
          end
        end
        return x if indent.empty?

        _y, new_x = buf.insert_text(row, x, indent)
        new_x
      end

      def maybe_showmatch_after_insert(key)
        return unless [")", "]", "}"].include?(key)
        return unless @editor.effective_option("showmatch")

        mt = @editor.effective_option("matchtime").to_i
        mt = 5 if mt <= 0
        @editor.echo_temporary("match", duration_seconds: mt * 0.1)
      end

      def maybe_dedent_after_insert(key)
        return unless @editor.effective_option("smartindent", window: @editor.current_window, buffer: @editor.current_buffer)

        buf = @editor.current_buffer
        lang_mod = buf.lang_module

        pattern = lang_mod.dedent_trigger(key)
        return unless pattern

        row = @editor.current_window.cursor_y
        line = buf.line_at(row)
        m = line.match(pattern)
        return unless m

        sw = @editor.effective_option("shiftwidth", buffer: buf).to_i
        sw = 2 if sw <= 0
        target_indent = lang_mod.calculate_indent(buf.lines, row, sw)
        return unless target_indent

        current_indent = m[1].length
        return if current_indent == target_indent

        stripped = line.strip
        buf.delete_span(row, 0, row, current_indent) if current_indent > 0
        buf.insert_text(row, 0, " " * target_indent) if target_indent > 0
        @editor.current_window.cursor_x = target_indent + stripped.length
      end

      def effective_tabstop(window = @editor.current_window, buffer = @editor.current_buffer)
        v = @editor.effective_option("tabstop", window:, buffer:).to_i
        v.positive? ? v : 2
      end

      def current_page_step_lines
        [@editor.current_window_view_height_hint - 2, 1].max
      end
    end
  end
end
