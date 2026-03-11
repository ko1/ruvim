# frozen_string_literal: true

module RuVim
  module Commands
    # Insert mode, delete, change, join, replace, indent, undo/redo, visual entry, text objects
    module Edit
      def enter_insert_mode(ctx, **)
        materialize_intro_buffer_if_needed(ctx)
        ensure_modifiable_for_insert!(ctx)
        ctx.buffer.begin_change_group
        ctx.editor.enter_insert_mode
        ctx.editor.echo("-- INSERT --")
      end

      def append_mode(ctx, **)
        x = ctx.window.cursor_x
        len = ctx.buffer.line_length(ctx.window.cursor_y)
        ctx.window.cursor_x = [x + 1, len].min
        enter_insert_mode(ctx)
      end

      def append_line_end_mode(ctx, **)
        ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
        enter_insert_mode(ctx)
      end

      def insert_line_start_nonblank_mode(ctx, **)
        cursor_first_nonblank(ctx)
        enter_insert_mode(ctx)
      end

      def open_line_below(ctx, **)
        materialize_intro_buffer_if_needed(ctx)
        ensure_modifiable_for_insert!(ctx)
        y = ctx.window.cursor_y
        x = ctx.buffer.line_length(y)
        ctx.buffer.begin_change_group
        new_y, new_x = ctx.buffer.insert_newline(y, x)
        new_x = apply_autoindent_to_newline(ctx, row: new_y, previous_row: y, start_col: new_x)
        ctx.window.cursor_y = new_y
        ctx.window.cursor_x = new_x
        ctx.editor.enter_insert_mode
        ctx.editor.echo("-- INSERT --")
      end

      def open_line_above(ctx, **)
        materialize_intro_buffer_if_needed(ctx)
        ensure_modifiable_for_insert!(ctx)
        y = ctx.window.cursor_y
        ctx.buffer.begin_change_group
        _new_y, new_x = ctx.buffer.insert_newline(y, 0)
        new_x = apply_autoindent_to_newline(ctx, row: y, previous_row: y + 1, start_col: 0)
        ctx.window.cursor_y = y
        ctx.window.cursor_x = new_x
        ctx.editor.enter_insert_mode
        ctx.editor.echo("-- INSERT --")
      end

      def enter_visual_char_mode(ctx, **)
        ctx.editor.enter_visual(:visual_char)
        ctx.editor.echo("-- VISUAL --")
      end

      def enter_visual_line_mode(ctx, **)
        ctx.editor.enter_visual(:visual_line)
        ctx.editor.echo("-- VISUAL LINE --")
      end

      def enter_visual_block_mode(ctx, **)
        ctx.editor.enter_visual(:visual_block)
        ctx.editor.echo("-- VISUAL BLOCK --")
      end

      def enter_command_line_mode(ctx, **)
        ctx.editor.enter_command_line_mode(":")
        ctx.editor.clear_message
      end

      def enter_search_forward_mode(ctx, **)
        ctx.editor.enter_command_line_mode("/")
        ctx.editor.clear_message
      end

      def enter_search_backward_mode(ctx, **)
        ctx.editor.enter_command_line_mode("?")
        ctx.editor.clear_message
      end

      def delete_char(ctx, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        count = normalized_count(count)
        ctx.buffer.begin_change_group
        deleted = +""
        count.times do
          chunk = char_at_cursor_for_delete(ctx.buffer, ctx.window.cursor_y, ctx.window.cursor_x)
          ok = ctx.buffer.delete_char(ctx.window.cursor_y, ctx.window.cursor_x)
          break unless ok
          deleted << chunk
        end
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def substitute_char(ctx, count:, bang:, **)
        call(:change_motion, ctx, count:, bang:, kwargs: { motion: "l" })
      end

      def swapcase_char(ctx, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        count = normalized_count(count)

        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        processed = false

        ctx.buffer.begin_change_group
        count.times do
          line = ctx.buffer.line_at(y)
          break if x >= line.length

          ch = line[x]
          swapped = ch.swapcase
          if !swapped.empty? && swapped != ch
            ctx.buffer.delete_span(y, x, y, x + 1)
            ctx.buffer.insert_char(y, x, swapped[0])
          end
          processed = true
          x += 1
        end
        ctx.buffer.end_change_group

        ctx.window.cursor_y = y
        ctx.window.cursor_x = processed ? x : ctx.window.cursor_x
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def join_lines(ctx, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        joins = [normalized_count(count) - 1, 1].max
        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        changed = false

        ctx.buffer.begin_change_group
        joins.times do
          break if y >= ctx.buffer.line_count - 1

          left = ctx.buffer.line_at(y)
          right = ctx.buffer.line_at(y + 1)
          join_col = left.length

          # Join raw lines first.
          break unless ctx.buffer.delete_char(y, join_col)

          right_trimmed = right.sub(/\A\s+/, "")
          trimmed_count = right.length - right_trimmed.length
          if trimmed_count.positive?
            ctx.buffer.delete_span(y, join_col, y, join_col + trimmed_count)
          end

          need_space = !left.empty? && !left.match?(/\s\z/) && !right_trimmed.empty? && !right_trimmed.match?(/\A\s/)
          ctx.buffer.insert_char(y, join_col, " ") if need_space

          x = join_col
          changed = true
        end
        ctx.buffer.end_change_group

        ctx.window.cursor_y = y
        ctx.window.cursor_x = x
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("joined") if changed
      end

      def delete_line(ctx, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        count = normalized_count(count)
        ctx.buffer.begin_change_group
        deleted_lines = []
        count.times { deleted_lines << ctx.buffer.delete_line(ctx.window.cursor_y) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted_lines.join("\n") + "\n", type: :linewise)
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def delete_motion(ctx, count:, kwargs:, **)
        materialize_intro_buffer_if_needed(ctx)
        motion = (kwargs[:motion] || kwargs["motion"]).to_s
        ncount = normalized_count(count)
        handled =
          case motion
          when "h" then delete_chars_left(ctx, ncount)
          when "l" then delete_chars_right(ctx, ncount)
          when "j" then delete_lines_down(ctx, ncount)
          when "k" then delete_lines_up(ctx, ncount)
          when "$" then delete_to_end_of_line(ctx)
          when "w" then delete_word_forward(ctx, ncount)
          when "G" then delete_lines_to_end(ctx)
          when "gg" then delete_lines_to_start(ctx)
          when "iw" then delete_text_object_word(ctx, around: false)
          when "aw" then delete_text_object_word(ctx, around: true)
          else
            text_object_motion?(motion) ? delete_text_object(ctx, motion) : false
          end
        ctx.editor.echo("Unsupported motion for d: #{motion}") unless handled
        handled
      end

      def change_motion(ctx, count:, kwargs:, **)
        materialize_intro_buffer_if_needed(ctx)
        motion = (kwargs[:motion] || kwargs["motion"]).to_s
        result = delete_motion(ctx, count:, kwargs:)
        return unless result

        if result == :linewise
          case motion
          when "G"
            y = ctx.buffer.lines.length
            ctx.buffer.insert_lines_at(y, [""])
            ctx.window.cursor_y = y
          when "gg"
            ctx.buffer.insert_lines_at(0, [""])
            ctx.window.cursor_y = 0
          end
          ctx.window.cursor_x = 0
        end
        enter_insert_mode(ctx)
      end

      def change_line(ctx, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        delete_line(ctx, count:)
        enter_insert_mode(ctx)
      end

      def buffer_undo(ctx, **)
        if ctx.buffer.undo!
          ctx.window.clamp_to_buffer(ctx.buffer)
          ctx.editor.echo("Undo")
        else
          ctx.editor.echo("Already at oldest change")
        end
      end

      def buffer_redo(ctx, **)
        if ctx.buffer.redo!
          ctx.window.clamp_to_buffer(ctx.buffer)
          ctx.editor.echo("Redo")
        else
          ctx.editor.echo("Already at newest change")
        end
      end

      def replace_char(ctx, argv:, count:, **)
        materialize_intro_buffer_if_needed(ctx)
        count = normalized_count(count)
        ch = argv[0].to_s
        raise RuVim::CommandError, "replace requires a character" if ch.empty?

        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        line = ctx.buffer.line_at(y)
        return if x >= line.length

        ctx.buffer.begin_change_group
        count.times do |i|
          cx = x + i
          break if cx >= ctx.buffer.line_length(y)
          ctx.buffer.delete_span(y, cx, y, cx + 1)
          ctx.buffer.insert_char(y, cx, ch[0])
        end
        ctx.buffer.end_change_group
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def indent_lines(ctx, count:, **)
        count = normalized_count(count)
        start_row = ctx.window.cursor_y
        end_row = [start_row + count - 1, ctx.buffer.line_count - 1].min
        reindent_range(ctx, start_row, end_row)
      end

      def indent_motion(ctx, count:, kwargs:, **)
        motion = (kwargs[:motion] || kwargs["motion"]).to_s
        ncount = normalized_count(count)
        start_row = ctx.window.cursor_y
        case motion
        when "j"
          end_row = [start_row + ncount, ctx.buffer.line_count - 1].min
        when "k"
          end_row = start_row
          start_row = [start_row - ncount, 0].max
        when "G"
          end_row = ctx.buffer.line_count - 1
        when "gg"
          end_row = start_row
          start_row = 0
        else
          ctx.editor.echo("Unsupported motion for =: #{motion}")
          return
        end
        reindent_range(ctx, start_row, end_row)
      end

      def visual_indent(ctx, **)
        sel = ctx.editor.visual_selection
        return unless sel

        start_row = sel[:start_row]
        end_row = sel[:end_row]
        reindent_range(ctx, start_row, end_row)
        ctx.editor.enter_normal_mode
      end

      def visual_select_text_object(ctx, kwargs:, **)
        motion = (kwargs[:motion] || kwargs["motion"]).to_s
        span = text_object_span(ctx.buffer, ctx.window, motion)
        return false unless span

        ctx.editor.enter_visual(:visual_char) unless ctx.editor.mode == :visual_char
        v = ctx.editor.visual_state
        v[:anchor_y] = span[:start_row]
        v[:anchor_x] = span[:start_col]
        ctx.window.cursor_y = span[:end_row]
        ctx.window.cursor_x = [span[:end_col] - 1, 0].max
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      private

      def char_at_cursor_for_delete(buffer, row, col)
        line = buffer.line_at(row)
        if col < line.length
          line[col]
        elsif row < buffer.line_count - 1
          "\n"
        else
          ""
        end
      end

      def apply_autoindent_to_newline(ctx, row:, previous_row:, start_col: 0)
        return start_col unless ctx.editor.effective_option("autoindent", window: ctx.window, buffer: ctx.buffer)

        prev = ctx.buffer.line_at(previous_row)
        indent = prev[/\A[ \t]*/].to_s

        if ctx.editor.effective_option("smartindent", window: ctx.window, buffer: ctx.buffer)
          trimmed = prev.rstrip
          if trimmed.end_with?("{", "[", "(")
            sw = ctx.editor.effective_option("shiftwidth", window: ctx.window, buffer: ctx.buffer).to_i
            sw = 2 if sw <= 0
            indent += " " * sw
          end
        end

        return start_col if indent.empty?

        _y, x = ctx.buffer.insert_text(row, start_col, indent)
        x
      end

      def reindent_range(ctx, start_row, end_row)
        buf = ctx.buffer
        lang_mod = buf.lang_module

        sw = ctx.editor.effective_option("shiftwidth", buffer: buf).to_i
        sw = 2 if sw <= 0

        buf.begin_change_group
        (start_row..end_row).each do |row|
          target_indent = lang_mod.calculate_indent(buf.lines, row, sw)
          next unless target_indent

          line = buf.line_at(row)
          current_indent = line[/\A */].to_s.length
          next if current_indent == target_indent

          buf.delete_span(row, 0, row, current_indent) if current_indent > 0
          buf.insert_text(row, 0, " " * target_indent) if target_indent > 0
        end
        buf.end_change_group

        ctx.window.cursor_y = start_row
        line = buf.line_at(start_row)
        ctx.window.cursor_x = (line[/\A */]&.length || 0)
        ctx.window.clamp_to_buffer(buf)
        count = end_row - start_row + 1
        ctx.editor.echo("#{count} line#{"s" if count > 1} indented")
      end

      def delete_chars_left(ctx, count)
        return true if count <= 0

        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        start_x = [x - count, 0].max
        return true if start_x == x

        deleted = ctx.buffer.span_text(y, start_x, y, x)
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(y, start_x, y, x)
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
        ctx.window.cursor_x = start_x
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_chars_right(ctx, count)
        return true if count <= 0

        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        line_len = ctx.buffer.line_length(y)
        end_x = [x + count, line_len].min
        return true if end_x == x

        deleted = ctx.buffer.span_text(y, x, y, end_x)
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(y, x, y, end_x)
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_lines_down(ctx, count)
        total = count + 1
        deleted = ctx.buffer.line_block_text(ctx.window.cursor_y, total)
        ctx.buffer.begin_change_group
        total.times { ctx.buffer.delete_line(ctx.window.cursor_y) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :linewise)
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_lines_up(ctx, count)
        y = ctx.window.cursor_y
        start = [y - count, 0].max
        total = y - start + 1
        deleted = ctx.buffer.line_block_text(start, total)
        ctx.buffer.begin_change_group
        total.times { ctx.buffer.delete_line(start) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :linewise)
        ctx.window.cursor_y = start
        ctx.window.cursor_x = 0 if ctx.window.cursor_x > ctx.buffer.line_length(ctx.window.cursor_y)
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_lines_to_end(ctx)
        y = ctx.window.cursor_y
        total = ctx.buffer.lines.length - y
        deleted = ctx.buffer.line_block_text(y, total)
        ctx.buffer.begin_change_group
        total.times { ctx.buffer.delete_line(y) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :linewise)
        ctx.window.clamp_to_buffer(ctx.buffer)
        :linewise
      end

      def delete_lines_to_start(ctx)
        y = ctx.window.cursor_y
        total = y + 1
        deleted = ctx.buffer.line_block_text(0, total)
        ctx.buffer.begin_change_group
        total.times { ctx.buffer.delete_line(0) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :linewise)
        ctx.window.cursor_y = 0
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
        :linewise
      end

      def delete_to_end_of_line(ctx)
        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        line_len = ctx.buffer.line_length(y)
        return true if x >= line_len

        deleted = ctx.buffer.span_text(y, x, y, line_len)
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(y, x, y, line_len)
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_word_forward(ctx, count)
        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        target = advance_word_forward(ctx.buffer, y, x, count, editor: ctx.editor, window: ctx.window)
        return true unless target

        deleted = ctx.buffer.span_text(y, x, target[:row], target[:col])
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(y, x, target[:row], target[:col])
        ctx.buffer.end_change_group
        store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def delete_text_object_word(ctx, around:)
        delete_span(ctx, word_object_span(ctx.buffer, ctx.window, around:))
      end

      def delete_text_object(ctx, motion)
        delete_span(ctx, text_object_span(ctx.buffer, ctx.window, motion))
      end

      def delete_span(ctx, span)
        return false unless span

        text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
        ctx.buffer.end_change_group
        store_delete_register(ctx, text:, type: :charwise) unless text.empty?
        ctx.window.cursor_y = span[:start_row]
        ctx.window.cursor_x = span[:start_col]
        ctx.window.clamp_to_buffer(ctx.buffer)
        true
      end

      def text_object_span(buffer, window, motion)
        around = motion.start_with?("a")
        kind = motion[1..]
        case kind
        when "w"
          word_object_span(buffer, window, around:)
        when "p"
          paragraph_object_span(buffer, window, around:)
        when '"'
          quote_object_span(buffer, window, quote: '"', around:)
        when "'"
          quote_object_span(buffer, window, quote: "'", around:)
        when "`"
          quote_object_span(buffer, window, quote: "`", around:)
        when ")"
          paren_object_span(buffer, window, open: "(", close: ")", around:)
        when "]"
          paren_object_span(buffer, window, open: "[", close: "]", around:)
        when "}"
          paren_object_span(buffer, window, open: "{", close: "}", around:)
        else
          nil
        end
      end

      def text_object_motion?(motion)
        motion.is_a?(String) && motion.match?(/\A[ia](w|p|["'`\)\]\}])\z/)
      end

      def word_object_span(buffer, window, around:)
        row = window.cursor_y
        line = buffer.line_at(row)
        return nil if line.empty?

        x = [window.cursor_x, line.length - 1].min
        x = 0 if x.negative?

        if x < line.length && line[x] =~ /\s/
          if around
            left = x
            left -= 1 while left.positive? && line[left - 1] =~ /\s/
            right = x
            right += 1 while right < line.length && line[right] =~ /\s/
            return { start_row: row, start_col: left, end_row: row, end_col: right }
          end

          nxt = line.index(/\S/, x)
          return nil unless nxt
          x = nxt
        end

        keyword_rx = keyword_char_regex(nil, buffer, window)
        cls = keyword_char?(line[x], keyword_rx) ? :word : :punct
        start_col = x
        start_col -= 1 while start_col.positive? && same_word_class?(line[start_col - 1], cls, keyword_rx)
        end_col = x + 1
        end_col += 1 while end_col < line.length && same_word_class?(line[end_col], cls, keyword_rx)

        if around
          while end_col < line.length && line[end_col] =~ /\s/
            end_col += 1
          end
        end

        { start_row: row, start_col:, end_row: row, end_col: }
      end

      def quote_object_span(buffer, window, quote:, around:)
        row = window.cursor_y
        line = buffer.line_at(row)
        return nil if line.empty?
        x = [window.cursor_x, line.length - 1].min
        return nil if x.negative?

        left = find_quote(line, x, quote, :left)
        right_from = [x, (left ? left + 1 : 0)].max
        right = find_quote(line, right_from, quote, :right)
        return nil unless left && right && left < right

        if around
          { start_row: row, start_col: left, end_row: row, end_col: right + 1 }
        else
          { start_row: row, start_col: left + 1, end_row: row, end_col: right }
        end
      end

      def paren_object_span(buffer, window, open:, close:, around:)
        row = window.cursor_y
        line = buffer.line_at(row)
        return nil if line.empty?
        x = [window.cursor_x, line.length - 1].min
        return nil if x.negative?

        left = find_matching_left_delim(line, x, open:, close:)
        right = find_matching_right_delim(line, [x, left || 0].max, open:, close:)
        return nil unless left && right && left < right

        if around
          { start_row: row, start_col: left, end_row: row, end_col: right + 1 }
        else
          { start_row: row, start_col: left + 1, end_row: row, end_col: right }
        end
      end

      def paragraph_object_span(buffer, window, around:)
        row = [[window.cursor_y, 0].max, buffer.line_count - 1].min
        return nil if row.negative?

        blank = buffer.line_at(row).strip.empty?
        start_row = row
        end_row = row

        while start_row.positive? && (buffer.line_at(start_row - 1).strip.empty? == blank)
          start_row -= 1
        end
        while end_row + 1 < buffer.line_count && (buffer.line_at(end_row + 1).strip.empty? == blank)
          end_row += 1
        end

        if around && !blank
          if end_row + 1 < buffer.line_count && buffer.line_at(end_row + 1).strip.empty?
            while end_row + 1 < buffer.line_count && buffer.line_at(end_row + 1).strip.empty?
              end_row += 1
            end
          elsif start_row.positive? && buffer.line_at(start_row - 1).strip.empty?
            while start_row.positive? && buffer.line_at(start_row - 1).strip.empty?
              start_row -= 1
            end
          end
        end

        if around && end_row + 1 < buffer.line_count
          {
            start_row: start_row,
            start_col: 0,
            end_row: end_row + 1,
            end_col: 0
          }
        else
          {
            start_row: start_row,
            start_col: 0,
            end_row: end_row,
            end_col: buffer.line_length(end_row)
          }
        end
      end

      def find_quote(line, x, quote, direction)
        i = x
        if direction == :left
          while i >= 0
            return i if line[i] == quote && !escaped?(line, i)
            i -= 1
          end
        else
          while i < line.length
            return i if line[i] == quote && !escaped?(line, i)
            i += 1
          end
        end
        nil
      end

      def escaped?(line, idx)
        backslashes = 0
        i = idx - 1
        while i >= 0 && line[i] == "\\"
          backslashes += 1
          i -= 1
        end
        backslashes.odd?
      end

      def find_matching_left_delim(line, x, open:, close:)
        depth = 0
        i = x
        while i >= 0
          ch = line[i]
          if ch == close
            depth += 1
          elsif ch == open
            return i if depth.zero?
            depth -= 1
          end
          i -= 1
        end
        nil
      end

      def find_matching_right_delim(line, x, open:, close:)
        depth = 0
        i = x
        while i < line.length
          ch = line[i]
          if ch == open
            depth += 1
          elsif ch == close
            if depth <= 1
              return i
            end
            depth -= 1
          end
          i += 1
        end
        nil
      end
    end
  end
end
