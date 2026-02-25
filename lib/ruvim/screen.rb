module RuVim
  class Screen
    DEFAULT_TABSTOP = 2
    def initialize(terminal:)
      @terminal = terminal
      @last_frame = nil
    end

    def invalidate_cache!
      @last_frame = nil
    end

    def render(editor)
      rows, cols = @terminal.winsize
      text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
      text_rows = [text_rows, 1].max
      text_cols = [text_cols, 1].max

      rects = window_rects(editor, text_rows:, text_cols:)
      editor.window_order.each do |win_id|
        win = editor.windows.fetch(win_id)
        buf = editor.buffers.fetch(win.buffer_id)
        rect = rects[win_id]
        next unless rect
        content_width = [rect[:width] - number_column_width(editor, win, buf), 1].max
        win.ensure_visible(
          buf,
          height: [rect[:height], 1].max,
          width: content_width,
          tabstop: tabstop_for(editor, win, buf)
        )
      end

      frame = build_frame(editor, rows:, cols:, text_rows:, text_cols:, rects:)
      out = if can_diff_render?(frame)
              render_diff(frame)
            else
              render_full(frame)
            end
      cursor_row, cursor_col = cursor_screen_position(editor, text_rows, rects)
      out << "\e[#{cursor_row};#{cursor_col}H"
      out << "\e[?25h"
      @last_frame = frame.merge(cursor_row:, cursor_col:)
      @terminal.write(out)
    end

    private

    def build_frame(editor, rows:, cols:, text_rows:, text_cols:, rects:)
      lines = {}
      render_window_area(editor, lines, rects, text_rows:, text_cols:)

      status_row = text_rows + 1
      lines[status_row] = "\e[7m#{truncate(status_line(editor, cols), cols)}\e[m"

      if editor.command_line_active?
        cmd = editor.command_line
        lines[status_row + 1] = truncate("#{cmd.prefix}#{cmd.text}", cols)
      end

      {
        rows: rows,
        cols: cols,
        lines: lines,
        rects: rects
      }
    end

    def render_window_area(editor, lines, rects, text_rows:, text_cols:)
      if rects.values.any? { |r| r[:separator] == :vertical }
        render_vertical_windows(editor, lines, rects, text_rows:, text_cols:)
      else
        render_horizontal_windows(editor, lines, rects, text_rows:, text_cols:)
      end
    end

    def render_horizontal_windows(editor, lines, rects, text_rows:, text_cols:)
      1.upto(text_rows) { |row_no| lines[row_no] = " " * text_cols }

      editor.window_order.each do |win_id|
        rect = rects[win_id]
        next unless rect

          window = editor.windows.fetch(win_id)
          buffer = editor.buffers.fetch(window.buffer_id)
          gutter_w = number_column_width(editor, window, buffer)
          content_w = [rect[:width] - gutter_w, 1].max
          rect[:height].times do |dy|
            row_no = rect[:top] + dy
            buffer_row = window.row_offset + dy
            text =
              if buffer_row < buffer.line_count
                render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
              else
                line_number_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w)
              end
            lines[row_no] = text
          end
      end

      rects.each_value do |rect|
        next unless rect[:separator] == :horizontal
        lines[rect[:sep_row]] = ("-" * text_cols)
      end
    end

    def render_vertical_windows(editor, lines, rects, text_rows:, text_cols:)
      1.upto(text_rows) do |row_no|
        pieces = +""
        editor.window_order.each_with_index do |win_id, idx|
          rect = rects[win_id]
          next unless rect
          window = editor.windows.fetch(win_id)
          buffer = editor.buffers.fetch(window.buffer_id)
          gutter_w = number_column_width(editor, window, buffer)
          content_w = [rect[:width] - gutter_w, 1].max
          dy = row_no - rect[:top]
          text =
            if dy >= 0 && dy < rect[:height]
              buffer_row = window.row_offset + dy
              if buffer_row < buffer.line_count
                render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
              else
                line_number_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w)
              end
            else
              " " * rect[:width]
            end
          pieces << text
          pieces << "|" if idx < editor.window_order.length - 1
        end
        lines[row_no] = pieces
      end
    end

    def can_diff_render?(frame)
      return false unless @last_frame
      @last_frame[:rows] == frame[:rows] && @last_frame[:cols] == frame[:cols]
    end

    def render_full(frame)
      out = +""
      out << "\e[?25l"
      out << "\e[H"
      1.upto(frame[:rows]) do |row_no|
        out << "\e[2K"
        out << (frame[:lines][row_no] || "")
        out << "\r\n" unless row_no == frame[:rows]
      end
      out
    end

    def render_diff(frame)
      out = +""
      out << "\e[?25l"
      max_rows = [frame[:rows], @last_frame[:rows]].max
      1.upto(max_rows) do |row_no|
        new_line = frame[:lines][row_no] || ""
        old_line = @last_frame[:lines][row_no] || ""
        next if new_line == old_line

        out << "\e[#{row_no};1H"
        out << "\e[2K"
        out << new_line
      end
      out
    end

    def render_text_line(text, editor, buffer_row:, window:, buffer:, width:)
      tabstop = tabstop_for(editor, window, buffer)
      cells, display_col = RuVim::TextMetrics.clip_cells_for_width(text, width, source_col_start: window.col_offset, tabstop:)
      highlighted = +""
      visual = (editor.current_window_id == window.id && editor.visual_active?) ? editor.visual_selection(window) : nil
      search_cols = search_highlight_source_cols(editor, text, source_col_offset: window.col_offset)
      syntax_cols = syntax_highlight_source_cols(editor, window, buffer, text, source_col_offset: window.col_offset)

      cells.each_with_index do |cell, idx|
        ch = cell.glyph
        buffer_col = cell.source_col
        selected = selected_in_visual?(visual, buffer_row, buffer_col)
        cursor_here = (editor.current_window_id == window.id && window.cursor_y == buffer_row && window.cursor_x == buffer_col)
        if selected || cursor_here
          highlighted << "\e[7m#{ch}\e[m"
        elsif search_cols[buffer_col]
          highlighted << "\e[43m#{ch}\e[m"
        elsif (syntax_color = syntax_cols[buffer_col])
          highlighted << "#{syntax_color}#{ch}\e[m"
        else
          highlighted << ch
        end
      end

      if editor.current_window_id == window.id && window.cursor_y == buffer_row
        col = window.cursor_x - window.col_offset
        if col >= cells.length && col >= 0 && display_col < width
          highlighted << "\e[7m \e[m"
          display_col += 1
        end
      end

      highlighted << (" " * [width - display_col, 0].max)
      highlighted
    end

    def render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
      line = buffer.line_at(buffer_row)
      line = line[window.col_offset..] || ""
      prefix = line_number_prefix(editor, window, buffer, buffer_row, gutter_w)
      body = render_text_line(line, editor, buffer_row:, window:, buffer:, width: content_w)
      prefix + body
    end

    def tabstop_for(editor, window, buffer)
      val = editor.effective_option("tabstop", window:, buffer:)
      iv = val.to_i
      iv.positive? ? iv : DEFAULT_TABSTOP
    rescue StandardError
      DEFAULT_TABSTOP
    end

    def number_column_width(editor, window, buffer)
      enabled = editor.effective_option("number", window:, buffer:) || editor.effective_option("relativenumber", window:, buffer:)
      return 0 unless enabled

      [buffer.line_count.to_s.length, 1].max + 1
    end

    def line_number_prefix(editor, window, buffer, buffer_row, width)
      return "" if width <= 0
      show_abs = editor.effective_option("number", window:, buffer:)
      show_rel = editor.effective_option("relativenumber", window:, buffer:)
      return " " * width unless show_abs || show_rel
      return " " * (width - 1) + " " if buffer_row.nil?

      num =
        if show_rel && buffer_row != window.cursor_y
          (buffer_row - window.cursor_y).abs.to_s
        elsif show_abs
          (buffer_row + 1).to_s
        else
          "0"
        end
      num.rjust(width - 1) + " "
    end

    def pad_plain_display(text, width)
      RuVim::TextMetrics.pad_plain_to_screen_width(text, width, tabstop: DEFAULT_TABSTOP)
    end

    def status_line(editor, width)
      buffer = editor.current_buffer
      window = editor.current_window
      mode = case editor.mode
             when :insert then "-- INSERT --"
             when :command_line then "-- COMMAND --"
             when :visual_char then "-- VISUAL --"
             when :visual_line then "-- VISUAL LINE --"
             else "-- NORMAL --"
             end

      path = buffer.display_name
      ft = editor.effective_option("filetype", buffer:, window:) || File.extname(buffer.path.to_s).delete_prefix(".")
      ft = "-" if ft.empty?
      mod = buffer.modified? ? " [+]" : ""
      msg = editor.message.to_s
      win_idx = (editor.window_order.index(editor.current_window_id) || 0) + 1
      win_total = editor.window_order.length
      tab_info = "t#{editor.current_tabpage_number}/#{editor.tabpage_count}"
      left = "#{mode} #{tab_info} w#{win_idx}/#{win_total} b#{buffer.id} #{path} [ft=#{ft}]#{mod}"
      right = " #{window.cursor_y + 1}:#{window.cursor_x + 1} "
      body_width = [width - right.length, 0].max
      "#{compose_status_body(left, msg, body_width)}#{right}"
    end

    def compose_status_body(left, msg, width)
      w = [width.to_i, 0].max
      return "" if w.zero?
      return left.ljust(w)[0, w] if msg.to_s.empty?

      msg_part = " | #{msg}"
      if msg_part.length >= w
        return msg_part[0, w]
      end

      left_budget = w - msg_part.length
      "#{left.ljust(left_budget)[0, left_budget]}#{msg_part}"
    end

    def truncate(str, width)
      str.to_s.ljust(width)[0, width]
    end

    def cursor_screen_position(editor, text_rows, rects)
      window = editor.current_window

      if editor.command_line_active?
        row = text_rows + 2
        col = 1 + editor.command_line.prefix.length + editor.command_line.cursor
        return [row, col]
      end

      rect = rects[window.id] || { top: 1, left: 1 }
      row = rect[:top] + (window.cursor_y - window.row_offset)
      line = editor.current_buffer.line_at(window.cursor_y)
      gutter_w = number_column_width(editor, window, editor.current_buffer)
      tabstop = tabstop_for(editor, window, editor.current_buffer)
      prefix_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, window.cursor_x, tabstop:) -
                          RuVim::TextMetrics.screen_col_for_char_index(line, window.col_offset, tabstop:)
      col = rect[:left] + gutter_w + [prefix_screen_col, 0].max
      [row, col]
    end

    def window_rects(editor, text_rows:, text_cols:)
      ids = editor.window_order
      return {} if ids.empty?
      return { ids.first => { top: 1, left: 1, height: text_rows, width: text_cols } } if ids.length == 1 || editor.window_layout == :single

      if editor.window_layout == :vertical
        sep = ids.length - 1
        usable = [text_cols - sep, ids.length].max
        widths = split_sizes(usable, ids.length)
        left = 1
        rects = {}
        ids.each_with_index do |id, i|
          w = widths[i]
          rects[id] = { top: 1, left: left, height: text_rows, width: w, separator: :vertical }
          left += w + 1
        end
        rects
      else
        sep = ids.length - 1
        usable = [text_rows - sep, ids.length].max
        heights = split_sizes(usable, ids.length)
        top = 1
        rects = {}
        ids.each_with_index do |id, i|
          h = heights[i]
          rects[id] = { top: top, left: 1, height: h, width: text_cols, separator: :horizontal }
          top += h
          if i < ids.length - 1
            rects[id][:sep_row] = top
            top += 1
          end
        end
        rects
      end
    end

    def split_sizes(total, n)
      base = total / n
      rem = total % n
      Array.new(n) { |i| base + (i < rem ? 1 : 0) }
    end

    def selected_in_visual?(visual, row, col)
      return false unless visual

      if visual[:mode] == :linewise
        row >= visual[:start_row] && row <= visual[:end_row]
      else
        return false if row < visual[:start_row] || row > visual[:end_row]
        if visual[:start_row] == visual[:end_row]
          col >= visual[:start_col] && col < visual[:end_col]
        elsif row == visual[:start_row]
          col >= visual[:start_col]
        elsif row == visual[:end_row]
          col < visual[:end_col]
        else
          true
        end
      end
    end

    def search_highlight_source_cols(editor, source_line_text, source_col_offset:)
      search = editor.last_search
      return {} unless search && search[:pattern]
      return {} unless editor.effective_option("hlsearch")

      regex = build_screen_search_regex(editor, search[:pattern])
      cols = {}
      offset = 0
      while (m = regex.match(source_line_text, offset))
        from = m.begin(0)
        to = [m.end(0), from + 1].max
        (from...to).each { |i| cols[source_col_offset + i] = true }
        offset = to
        break if offset > source_line_text.length
      end
      cols
    rescue RegexpError
      {}
    end

    def build_screen_search_regex(editor, pattern)
      ignorecase = !!editor.effective_option("ignorecase")
      smartcase = !!editor.effective_option("smartcase")
      flags = if ignorecase && !(smartcase && pattern.to_s.match?(/[A-Z]/))
                Regexp::IGNORECASE
              else
                0
              end
      Regexp.new(pattern.to_s, flags)
    end

    def syntax_highlight_source_cols(editor, window, buffer, source_line_text, source_col_offset:)
      filetype = editor.effective_option("filetype", buffer:, window:)
      rel = RuVim::Highlighter.color_columns(filetype, source_line_text)
      return {} if rel.empty?

      rel.each_with_object({}) do |(idx, color), h|
        h[source_col_offset + idx] = color
      end
    rescue StandardError
      {}
    end
  end
end
