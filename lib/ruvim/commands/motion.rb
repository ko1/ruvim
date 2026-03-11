# frozen_string_literal: true

module RuVim
  module Commands
    # Cursor movement, scrolling, word movement, bracket matching
    module Motion
      def cursor_left(ctx, count:, **)
        move_cursor_horizontally(ctx, direction: :left, count:)
      end

      def cursor_right(ctx, count:, **)
        move_cursor_horizontally(ctx, direction: :right, count:)
      end

      def cursor_up(ctx, count:, **)
        ctx.window.move_up(ctx.buffer, normalized_count(count))
      end

      def cursor_down(ctx, count:, **)
        ctx.window.move_down(ctx.buffer, normalized_count(count))
      end

      def cursor_page_up(ctx, kwargs:, count:, **)
        page_lines = [(kwargs[:page_lines] || kwargs["page_lines"] || 1).to_i, 1].max
        ctx.window.move_up(ctx.buffer, page_lines * [count.to_i, 1].max)
      end

      def cursor_page_down(ctx, kwargs:, count:, **)
        page_lines = [(kwargs[:page_lines] || kwargs["page_lines"] || 1).to_i, 1].max
        ctx.window.move_down(ctx.buffer, page_lines * [count.to_i, 1].max)
      end

      def cursor_page_up_default(ctx, count:, bang:, **)
        call(:cursor_page_up, ctx, count:, bang:, kwargs: { page_lines: current_page_step_lines(ctx) })
      end

      def cursor_page_down_default(ctx, count:, bang:, **)
        call(:cursor_page_down, ctx, count:, bang:, kwargs: { page_lines: current_page_step_lines(ctx) })
      end

      def cursor_page_up_half(ctx, count:, bang:, **)
        call(:cursor_page_up, ctx, count:, bang:, kwargs: { page_lines: current_half_page_step_lines(ctx) })
      end

      def cursor_page_down_half(ctx, count:, bang:, **)
        call(:cursor_page_down, ctx, count:, bang:, kwargs: { page_lines: current_half_page_step_lines(ctx) })
      end

      def window_scroll_up(ctx, kwargs:, count:, **)
        scroll_window_vertically(ctx, direction: :up, lines: kwargs[:lines] || kwargs["lines"], view_height: kwargs[:view_height] || kwargs["view_height"], count:)
      end

      def window_scroll_down(ctx, kwargs:, count:, **)
        scroll_window_vertically(ctx, direction: :down, lines: kwargs[:lines] || kwargs["lines"], view_height: kwargs[:view_height] || kwargs["view_height"], count:)
      end

      def window_scroll_up_line(ctx, count:, bang:, **)
        call(:window_scroll_up, ctx, count:, bang:, kwargs: { lines: 1, view_height: current_view_height(ctx) + 1 })
      end

      def window_scroll_down_line(ctx, count:, bang:, **)
        call(:window_scroll_down, ctx, count:, bang:, kwargs: { lines: 1, view_height: current_view_height(ctx) + 1 })
      end

      def window_cursor_line_top(ctx, count:, **)
        place_cursor_line_in_window(ctx, where: :top, count:)
      end

      def window_cursor_line_center(ctx, count:, **)
        place_cursor_line_in_window(ctx, where: :center, count:)
      end

      def window_cursor_line_bottom(ctx, count:, **)
        place_cursor_line_in_window(ctx, where: :bottom, count:)
      end

      def cursor_line_start(ctx, **)
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def cursor_line_end(ctx, **)
        ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def cursor_first_nonblank(ctx, **)
        line = ctx.buffer.line_at(ctx.window.cursor_y)
        idx = line.index(/\S/) || 0
        ctx.window.cursor_x = idx
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def cursor_buffer_start(ctx, count:, **)
        record_jump(ctx)
        target_row = [normalized_count(count).to_i - 1, 0].max
        target_row = [target_row, ctx.buffer.line_count - 1].min
        ctx.window.cursor_y = target_row
        cursor_first_nonblank(ctx)
      end

      def cursor_buffer_end(ctx, count:, **)
        record_jump(ctx)
        target_row = count.nil? ? (ctx.buffer.line_count - 1) : [normalized_count(count) - 1, ctx.buffer.line_count - 1].min
        ctx.window.cursor_y = target_row
        cursor_first_nonblank(ctx)
      end

      def cursor_word_forward(ctx, count:, **)
        move_cursor_word(ctx, count:, kind: :forward_start)
      end

      def cursor_word_backward(ctx, count:, **)
        move_cursor_word(ctx, count:, kind: :backward_start)
      end

      def cursor_word_end(ctx, count:, **)
        move_cursor_word(ctx, count:, kind: :forward_end)
      end

      def cursor_match_bracket(ctx, **)
        line = ctx.buffer.line_at(ctx.window.cursor_y)
        ch = line[ctx.window.cursor_x]
        unless ch
          ctx.editor.echo_error("No bracket under cursor")
          return
        end

        pair_map = {
          "(" => [")", :forward],
          "[" => ["]", :forward],
          "{" => ["}", :forward],
          ")" => ["(", :backward],
          "]" => ["[", :backward],
          "}" => ["{", :backward]
        }
        pair = pair_map[ch]
        unless pair
          ctx.editor.echo_error("No bracket under cursor")
          return
        end

        target_char, direction = pair
        record_jump(ctx)
        loc = find_matching_bracket(ctx.buffer, ctx.window.cursor_y, ctx.window.cursor_x, ch, target_char, direction)
        if loc
          ctx.window.cursor_y = loc[:row]
          ctx.window.cursor_x = loc[:col]
          ctx.window.clamp_to_buffer(ctx.buffer)
        else
          ctx.editor.echo_error("Match not found")
        end
      end

      private

      def move_cursor_horizontally(ctx, direction:, count:)
        count = [count.to_i, 1].max
        allow_wrap = whichwrap_allows?(ctx, direction)
        virtualedit_mode = virtualedit_mode(ctx)
        count.times do
          line = ctx.buffer.line_at(ctx.window.cursor_y)
          if direction == :left
            if ctx.window.cursor_x > line.length && virtualedit_mode
              ctx.window.cursor_x -= 1
            elsif ctx.window.cursor_x.positive?
              ctx.window.cursor_x = RuVim::TextMetrics.previous_grapheme_char_index(line, ctx.window.cursor_x)
            elsif allow_wrap && ctx.window.cursor_y.positive?
              ctx.window.cursor_y -= 1
              ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
            end
          else
            max_right =
              case virtualedit_mode
              when :all then line.length + count + 1024 # practical cap; clamp below uses current cursor
              when :onemore then line.length + 1
              else line.length
              end
            if ctx.window.cursor_x < max_right
              ctx.window.cursor_x =
                if virtualedit_mode == :onemore && ctx.window.cursor_x == line.length
                  line.length + 1
                elsif virtualedit_mode == :all && ctx.window.cursor_x >= line.length
                  ctx.window.cursor_x + 1
                else
                  RuVim::TextMetrics.next_grapheme_char_index(line, ctx.window.cursor_x)
                end
              ctx.window.cursor_x = [ctx.window.cursor_x, max_right].min
            elsif allow_wrap && ctx.window.cursor_y < ctx.buffer.line_count - 1
              ctx.window.cursor_y += 1
              ctx.window.cursor_x = 0
            end
          end
        end
        extra =
          case virtualedit_mode
          when :all
            [ctx.window.cursor_x - ctx.buffer.line_length(ctx.window.cursor_y), 0].max
          when :onemore
            1
          else
            0
          end
        ctx.window.clamp_to_buffer(ctx.buffer, max_extra_col: extra)
      end

      def whichwrap_allows?(ctx, direction)
        toks = ctx.editor.effective_option("whichwrap", window: ctx.window, buffer: ctx.buffer).to_s
                 .split(",").map { |s| s.strip.downcase }.reject(&:empty?)
        return false if toks.empty?

        if direction == :left
          toks.include?("h") || toks.include?("<") || toks.include?("left")
        else
          toks.include?("l") || toks.include?(">") || toks.include?("right")
        end
      end

      def virtualedit_mode(ctx)
        spec = ctx.editor.effective_option("virtualedit", window: ctx.window, buffer: ctx.buffer).to_s
        toks = spec.split(",").map { |s| s.strip.downcase }
        return :all if toks.include?("all")
        return :onemore if toks.include?("onemore")

        nil
      end

      def current_view_height(ctx)
        hint = ctx.editor.respond_to?(:current_window_view_height_hint) ? ctx.editor.current_window_view_height_hint : nil
        [hint.to_i, 1].max
      rescue StandardError
        1
      end

      def current_page_step_lines(ctx)
        [current_view_height(ctx) - 1, 1].max
      end

      def current_half_page_step_lines(ctx)
        [current_view_height(ctx) / 2, 1].max
      end

      def scroll_window_vertically(ctx, direction:, lines:, view_height:, count:)
        step = [[lines.to_i, 1].max * [count.to_i, 1].max, 1].max
        height = [view_height.to_i, 1].max
        max_row_offset = [ctx.buffer.line_count - height, 0].max

        before = ctx.window.row_offset.to_i
        after =
          if direction == :up
            [before - step, 0].max
          else
            [before + step, max_row_offset].min
          end
        return if after == before

        ctx.window.row_offset = after

        # Vim-like behavior: scroll viewport first, then keep cursor inside it.
        top = after
        bottom = after + height - 1
        if ctx.window.cursor_y < top
          ctx.window.cursor_y = top
        elsif ctx.window.cursor_y > bottom
          ctx.window.cursor_y = bottom
        end
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def place_cursor_line_in_window(ctx, where:, count:)
        if count
          target_row = [[normalized_count(count) - 1, 0].max, ctx.buffer.line_count - 1].min
          ctx.window.cursor_y = target_row
          ctx.window.clamp_to_buffer(ctx.buffer)
        end

        height = current_view_height(ctx)
        max_row_offset = [ctx.buffer.line_count - height, 0].max
        desired =
          case where
          when :top
            ctx.window.cursor_y
          when :center
            ctx.window.cursor_y - (height / 2)
          when :bottom
            ctx.window.cursor_y - height + 1
          else
            ctx.window.row_offset
          end
        ctx.window.row_offset = [[desired, 0].max, max_row_offset].min
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def cursor_to_offset(buffer, row, col)
        offset = 0
        row.times { |r| offset += buffer.line_length(r) + 1 }
        offset + col
      end

      def offset_to_cursor(buffer, offset)
        remaining = offset
        (0...buffer.line_count).each do |row|
          len = buffer.line_length(row)
          return { row:, col: [remaining, len].min } if remaining <= len
          remaining -= (len + 1)
        end
        { row: buffer.line_count - 1, col: buffer.line_length(buffer.line_count - 1) }
      end

      def move_cursor_word(ctx, count:, kind:)
        buffer = ctx.buffer
        row = ctx.window.cursor_y
        col = ctx.window.cursor_x
        count = normalized_count(count)
        target = { row:, col: }
        count.times do
          target =
            case kind
            when :forward_start then advance_word_forward(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
            when :backward_start then advance_word_backward(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
            when :forward_end then advance_word_end(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
            end
          break unless target
        end
        return unless target

        ctx.window.cursor_y = target[:row]
        ctx.window.cursor_x = target[:col]
        ctx.window.clamp_to_buffer(buffer)
      end

      def advance_word_forward(buffer, row, col, count, editor: nil, window: nil)
        text = buffer.lines.join("\n")
        flat = cursor_to_offset(buffer, row, col)
        idx = flat
        keyword_rx = keyword_char_regex(editor, buffer, window)
        count = normalized_count(count)
        count.times do
          idx = next_word_start_offset(text, idx, keyword_rx)
          return nil unless idx
        end
        offset_to_cursor(buffer, idx)
      end

      def advance_word_backward(buffer, row, col, _count, editor: nil, window: nil)
        text = buffer.lines.join("\n")
        idx = cursor_to_offset(buffer, row, col)
        idx = [idx - 1, 0].max
        keyword_rx = keyword_char_regex(editor, buffer, window)
        while idx > 0 && char_class(text[idx], keyword_rx) == :space
          idx -= 1
        end
        cls = char_class(text[idx], keyword_rx)
        while idx > 0 && char_class(text[idx - 1], keyword_rx) == cls && cls != :space
          idx -= 1
        end
        while idx > 0 && char_class(text[idx], keyword_rx) == :space
          idx += 1
        end
        offset_to_cursor(buffer, idx)
      end

      def advance_word_end(buffer, row, col, _count, editor: nil, window: nil)
        text = buffer.lines.join("\n")
        idx = cursor_to_offset(buffer, row, col)
        n = text.length
        keyword_rx = keyword_char_regex(editor, buffer, window)

        # Vim-like `e`: if already on the end of a word, move to the next word's end.
        if idx < n
          cur_cls = char_class(text[idx], keyword_rx)
          next_cls = (idx + 1 < n) ? char_class(text[idx + 1], keyword_rx) : nil
          idx += 1 if cur_cls != :space && next_cls != cur_cls
        end

        while idx < n && char_class(text[idx], keyword_rx) == :space
          idx += 1
        end
        return nil if idx >= n

        cls = char_class(text[idx], keyword_rx)
        idx += 1 while idx + 1 < n && char_class(text[idx + 1], keyword_rx) == cls && cls != :space
        offset_to_cursor(buffer, idx)
      end

      def next_word_start_offset(text, from_offset, keyword_rx = nil)
        i = [from_offset, 0].max
        n = text.length
        return nil if i >= n

        cls = char_class(text[i], keyword_rx)
        if cls == :word
          i += 1 while i < n && char_class(text[i], keyword_rx) == :word
        elsif cls == :space
          i += 1 while i < n && char_class(text[i], keyword_rx) == :space
        else
          i += 1
        end
        i += 1 while i < n && char_class(text[i], keyword_rx) == :space
        return n if i > n

        i <= n ? i : nil
      end

      def char_class(ch, keyword_rx = nil)
        return :space if ch == "\n"
        return :space if ch =~ /\s/
        return :word if keyword_char?(ch, keyword_rx)
        :punct
      end

      def same_word_class?(ch, cls, keyword_rx = nil)
        return false if ch.nil?
        case cls
        when :word then keyword_char?(ch, keyword_rx)
        when :punct then !(keyword_char?(ch, keyword_rx) || ch =~ /\s/)
        else false
        end
      end

      def keyword_char?(ch, keyword_rx = nil)
        return false if ch.nil?

        (keyword_rx || /[[:alnum:]_]/).match?(ch)
      end

      def keyword_char_regex(editor, buffer, window)
        win = window || editor&.current_window
        buf = buffer || editor&.current_buffer
        raw =
          if editor
            editor.effective_option("iskeyword", window: win, buffer: buf).to_s
          else
            buf&.options&.fetch("iskeyword", nil).to_s
          end
        RuVim::KeywordChars.regex(raw)
      end

      def find_matching_bracket(buffer, row, col, open_ch, close_ch, direction)
        depth = 1
        pos = { row: row, col: col }
        loop do
          pos = direction == :forward ? next_buffer_pos(buffer, pos[:row], pos[:col]) : prev_buffer_pos(buffer, pos[:row], pos[:col])
          return nil unless pos

          ch = buffer.line_at(pos[:row])[pos[:col]]
          next unless ch

          if ch == open_ch
            depth += 1
          elsif ch == close_ch
            depth -= 1
            return pos if depth.zero?
          end
        end
      end

      def next_buffer_pos(buffer, row, col)
        line = buffer.line_at(row)
        if col + 1 < line.length
          { row: row, col: col + 1 }
        elsif row + 1 < buffer.line_count
          { row: row + 1, col: 0 }
        end
      end

      def prev_buffer_pos(buffer, row, col)
        if col.positive?
          { row: row, col: col - 1 }
        elsif row.positive?
          prev_row = row - 1
          prev_len = buffer.line_length(prev_row)
          return { row: prev_row, col: prev_len - 1 } if prev_len.positive?

          { row: prev_row, col: 0 }
        end
      end
    end
  end
end
