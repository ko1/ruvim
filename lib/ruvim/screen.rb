module RuVim
  class Screen
    DEFAULT_TABSTOP = 2
    SYNTAX_CACHE_LIMIT = 2048
    def initialize(terminal:)
      @terminal = terminal
      @last_frame = nil
      @syntax_color_cache = {}
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
        win.col_offset = 0 if wrap_enabled?(editor, win, buf)
        win.ensure_visible(
          buf,
          height: [rect[:height], 1].max,
          width: content_width,
          tabstop: tabstop_for(editor, win, buf),
          scrolloff: editor.effective_option("scrolloff", window: win, buffer: buf),
          sidescrolloff: editor.effective_option("sidescrolloff", window: win, buffer: buf)
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

    def current_window_view_height(editor)
      rows, cols = @terminal.winsize
      text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
      text_rows = [text_rows, 1].max
      text_cols = [text_cols, 1].max
      rect = window_rects(editor, text_rows:, text_cols:)[editor.current_window_id]
      [rect ? rect[:height].to_i : text_rows, 1].max
    rescue StandardError
      1
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
      elsif editor.message_error?
        lines[status_row + 1] = error_message_line(editor.message.to_s, cols)
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
        rows = window_render_rows(editor, window, buffer, height: rect[:height], gutter_w:, content_w:)
        rect[:height].times do |dy|
          row_no = rect[:top] + dy
          lines[row_no] = rows[dy] || (" " * rect[:width])
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
              @__window_rows_cache ||= {}
              key = [window.id, rect[:height], gutter_w, content_w, window.row_offset, window.col_offset, window.cursor_y, window.cursor_x,
                     editor.effective_option("wrap", window:, buffer:), editor.effective_option("linebreak", window:, buffer:),
                     editor.effective_option("breakindent", window:, buffer:), editor.effective_option("showbreak", window:, buffer:)]
              @__window_rows_cache[key] ||= window_render_rows(editor, window, buffer, height: rect[:height], gutter_w:, content_w:)
              @__window_rows_cache[key][dy] || (" " * rect[:width])
            else
              " " * rect[:width]
            end
          pieces << text
          pieces << "|" if idx < editor.window_order.length - 1
        end
        lines[row_no] = pieces
      end
      @__window_rows_cache = nil
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
      render_cells(cells, display_col, editor, buffer_row:, window:, buffer:, width:, source_line: buffer.line_at(buffer_row),
                   source_col_offset: window.col_offset, leading_display_prefix: "")
    end

    def render_text_segment(source_line, editor, buffer_row:, window:, buffer:, width:, source_col_start:, display_prefix: "")
      tabstop = tabstop_for(editor, window, buffer)
      prefix = display_prefix.to_s
      prefix_w = RuVim::DisplayWidth.display_width(prefix, tabstop:)
      avail = [width - prefix_w, 0].max
      cells, display_col = RuVim::TextMetrics.clip_cells_for_width(source_line[source_col_start..].to_s, avail, source_col_start:, tabstop:)
      body = render_cells(cells, display_col, editor, buffer_row:, window:, buffer:, width: avail, source_line: source_line,
                          source_col_offset: source_col_start, leading_display_prefix: prefix)
      if width <= 0
        ""
      elsif prefix_w <= 0
        body
      else
        prefix_render = RuVim::TextMetrics.pad_plain_to_screen_width(prefix, [width, 0].max, tabstop:)[0...prefix.length].to_s
        # body already includes padding for avail; prepend the visible prefix and trim to width.
        out = prefix_render + body
        out
      end
    end

    def render_cells(cells, display_col, editor, buffer_row:, window:, buffer:, width:, source_line:, source_col_offset:, leading_display_prefix:)
      highlighted = +""
      visual = (editor.current_window_id == window.id && editor.visual_active?) ? editor.visual_selection(window) : nil
      text_for_highlight = source_line[source_col_offset..].to_s
      search_cols = search_highlight_source_cols(editor, text_for_highlight, source_col_offset: source_col_offset)
      syntax_cols = syntax_highlight_source_cols(editor, window, buffer, text_for_highlight, source_col_offset: source_col_offset)
      list_enabled = !!editor.effective_option("list", window:, buffer:)
      listchars = parse_listchars(editor.effective_option("listchars", window:, buffer:))
      tab_seen = {}
      trail_from = source_line.rstrip.length
      cursorline = !!editor.effective_option("cursorline", window:, buffer:)
      current_line = (editor.current_window_id == window.id && window.cursor_y == buffer_row)
      cursorline_enabled = cursorline && current_line
      colorcolumns = colorcolumn_display_cols(editor, window, buffer)
      display_pos = RuVim::DisplayWidth.display_width(leading_display_prefix.to_s, tabstop: tabstop_for(editor, window, buffer))

      cells.each_with_index do |cell, idx|
        ch = display_glyph_for_cell(cell, source_line, list_enabled:, listchars:, tab_seen:, trail_from:)
        buffer_col = cell.source_col
        selected = selected_in_visual?(visual, buffer_row, buffer_col)
        cursor_here = (editor.current_window_id == window.id && window.cursor_y == buffer_row && window.cursor_x == buffer_col)
        colorcolumn_here = colorcolumns[display_pos]
        if selected || cursor_here
          highlighted << "\e[7m#{ch}\e[m"
        elsif search_cols[buffer_col]
          highlighted << "\e[43m#{ch}\e[m"
        elsif colorcolumn_here
          highlighted << "\e[48;5;238m#{ch}\e[m"
        elsif cursorline_enabled
          highlighted << "\e[48;5;236m#{ch}\e[m"
        elsif (syntax_color = syntax_cols[buffer_col])
          highlighted << "#{syntax_color}#{ch}\e[m"
        else
          highlighted << ch
        end
        display_pos += [cell.display_width.to_i, 1].max
      end

      if editor.current_window_id == window.id && window.cursor_y == buffer_row
        if window.cursor_x >= source_col_offset && window.cursor_x >= (cells.last&.source_col.to_i + 1) && display_col < width
          highlighted << "\e[7m \e[m"
          display_col += 1
        end
      end

      trailing = [width - display_col, 0].max
      if trailing.positive? && cursorline_enabled
        trailing.times do
          if colorcolumns[display_pos]
            highlighted << "\e[48;5;238m \e[m"
          else
            highlighted << "\e[48;5;236m \e[m"
          end
          display_pos += 1
        end
      else
        highlighted << (" " * trailing)
      end
      highlighted
    end

    def window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      return plain_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:) unless wrap_enabled?(editor, window, buffer)

      wrapped_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
    end

    def plain_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      Array.new(height) do |dy|
        buffer_row = window.row_offset + dy
        if buffer_row < buffer.line_count
          render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
        else
          line_number_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w)
        end
      end
    end

    def wrapped_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      rows = []
      row_idx = window.row_offset
      while rows.length < height
        if row_idx >= buffer.line_count
          rows << (line_number_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w))
          next
        end

        line = buffer.line_at(row_idx)
        segments = wrapped_segments_for_line(editor, window, buffer, line, width: content_w)
        segments.each_with_index do |seg, seg_i|
          break if rows.length >= height

          gutter = line_number_prefix(editor, window, buffer, seg_i.zero? ? row_idx : nil, gutter_w)
          rows << gutter + render_text_segment(line, editor, buffer_row: row_idx, window:, buffer:, width: content_w,
                                               source_col_start: seg[:source_col_start], display_prefix: seg[:display_prefix])
        end
        row_idx += 1
      end
      rows
    end

    def wrap_enabled?(editor, window, buffer)
      !!editor.effective_option("wrap", window:, buffer:)
    end

    def wrapped_segments_for_line(editor, window, buffer, line, width:)
      return [{ source_col_start: 0, display_prefix: "" }] if width <= 0

      tabstop = tabstop_for(editor, window, buffer)
      linebreak = !!editor.effective_option("linebreak", window:, buffer:)
      showbreak = editor.effective_option("showbreak", window:, buffer:).to_s
      breakindent = !!editor.effective_option("breakindent", window:, buffer:)
      indent_prefix = breakindent ? wrapped_indent_prefix(line, tabstop:, max_width: [width - RuVim::DisplayWidth.display_width(showbreak, tabstop:), 0].max) : ""

      segs = []
      start_col = 0
      first = true
      line = line.to_s
      if line.empty?
        return [{ source_col_start: 0, display_prefix: "" }]
      end

      while start_col < line.length
        display_prefix = first ? "" : "#{showbreak}#{indent_prefix}"
        prefix_w = RuVim::DisplayWidth.display_width(display_prefix, tabstop:)
        avail = [width - prefix_w, 1].max
        cells, = RuVim::TextMetrics.clip_cells_for_width(line[start_col..].to_s, avail, source_col_start: start_col, tabstop:)
        if cells.empty?
          segs << { source_col_start: start_col, display_prefix: display_prefix }
          break
        end

        if linebreak && cells.length > 1
          break_idx = linebreak_break_index(cells, line)
          if break_idx && break_idx < cells.length - 1
            cells = cells[0..break_idx]
          end
        end

        segs << { source_col_start: start_col, display_prefix: display_prefix }
        next_start = cells.last.source_col.to_i + 1
        if linebreak
          next_start += 1 while next_start < line.length && line[next_start] == " "
        end
        break if next_start <= start_col

        start_col = next_start
        first = false
      end

      segs
    end

    def linebreak_break_index(cells, line)
      idx = nil
      cells.each_with_index do |cell, i|
        ch = line[cell.source_col]
        idx = i if ch =~ /\s/
      end
      idx
    end

    def wrapped_indent_prefix(line, tabstop:, max_width:)
      indent = line.to_s[/\A[ \t]*/].to_s
      return "" if indent.empty? || max_width <= 0

      RuVim::TextMetrics.pad_plain_to_screen_width(indent, max_width, tabstop:)[0...indent.length].to_s
    rescue StandardError
      ""
    end

    def display_glyph_for_cell(cell, source_line, list_enabled:, listchars:, tab_seen:, trail_from:)
      return cell.glyph unless list_enabled

      src = source_line[cell.source_col]
      case src
      when "\t"
        first = !tab_seen[cell.source_col]
        tab_seen[cell.source_col] = true
        first ? listchars[:tab_head] : listchars[:tab_fill]
      when " "
        cell.source_col >= trail_from ? listchars[:trail] : cell.glyph
      when "\u00A0"
        listchars[:nbsp]
      else
        cell.glyph
      end
    end

    def parse_listchars(raw)
      cfg = { tab_head: ">", tab_fill: "-", trail: "-", nbsp: "+" }
      raw.to_s.split(",").each do |entry|
        key, val = entry.split(":", 2)
        next unless key && val

        case key.strip
        when "tab"
          chars = val.to_s.each_char.to_a
          cfg[:tab_head] = chars[0] if chars[0]
          cfg[:tab_fill] = chars[1] if chars[1]
        when "trail"
          ch = val.to_s.each_char.first
          cfg[:trail] = ch if ch
        when "nbsp"
          ch = val.to_s.each_char.first
          cfg[:nbsp] = ch if ch
        end
      end
      cfg
    rescue StandardError
      { tab_head: ">", tab_fill: "-", trail: "-", nbsp: "+" }
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

      base = [buffer.line_count.to_s.length, 1].max
      minw = editor.effective_option("numberwidth", window:, buffer:).to_i
      [[base, minw].max, 1].max + 1
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

    def colorcolumn_display_cols(editor, window, buffer)
      raw = editor.effective_option("colorcolumn", window:, buffer:).to_s
      return {} if raw.empty?

      cols = {}
      raw.split(",").each do |tok|
        t = tok.strip
        next if t.empty?
        next unless t.match?(/\A\d+\z/)
        n = t.to_i
        next if n <= 0
        cols[n - 1] = true
      end
      cols
    rescue StandardError
      {}
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
             when :visual_block then "-- VISUAL BLOCK --"
             else "-- NORMAL --"
             end

      path = buffer.display_name
      ft = editor.effective_option("filetype", buffer:, window:) || File.extname(buffer.path.to_s).delete_prefix(".")
      ft = "-" if ft.empty?
      mod = buffer.modified? ? " [+]" : ""
      msg = editor.message_error? ? "" : editor.message.to_s
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

    def error_message_line(msg, cols)
      "\e[97;41m#{truncate(msg, cols)}\e[m"
    end

    def cursor_screen_position(editor, text_rows, rects)
      window = editor.current_window

      if editor.command_line_active?
        row = text_rows + 2
        col = 1 + editor.command_line.prefix.length + editor.command_line.cursor
        return [row, col]
      end

      rect = rects[window.id] || { top: 1, left: 1 }
      buffer = editor.current_buffer
      line = buffer.line_at(window.cursor_y)
      gutter_w = number_column_width(editor, window, buffer)
      content_w = [rect[:width] - gutter_w, 1].max
      tabstop = tabstop_for(editor, window, buffer)
      if wrap_enabled?(editor, window, buffer)
        visual_rows_before = 0
        row = window.row_offset
        while row < window.cursor_y
          visual_rows_before += wrapped_segments_for_line(editor, window, buffer, buffer.line_at(row), width: content_w).length
          row += 1
        end
        segs = wrapped_segments_for_line(editor, window, buffer, line, width: content_w)
        seg_index = 0
        segs.each_with_index do |seg, i|
          nxt = segs[i + 1]
          if nxt.nil? || window.cursor_x < nxt[:source_col_start]
            seg_index = i
            break
          end
        end
        seg = segs[seg_index] || { source_col_start: 0, display_prefix: "" }
        row = rect[:top] + visual_rows_before + seg_index
        seg_prefix_w = RuVim::DisplayWidth.display_width(seg[:display_prefix].to_s, tabstop:)
        cursor_sc = RuVim::TextMetrics.screen_col_for_char_index(line, window.cursor_x, tabstop:)
        seg_sc = RuVim::TextMetrics.screen_col_for_char_index(line, seg[:source_col_start], tabstop:)
        col = rect[:left] + gutter_w + seg_prefix_w + [cursor_sc - seg_sc, 0].max
      else
        row = rect[:top] + (window.cursor_y - window.row_offset)
        prefix_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, window.cursor_x, tabstop:) -
                            RuVim::TextMetrics.screen_col_for_char_index(line, window.col_offset, tabstop:)
        col = rect[:left] + gutter_w + [prefix_screen_col, 0].max
      end
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
      elsif visual[:mode] == :blockwise
        row >= visual[:start_row] && row <= visual[:end_row] &&
          col >= visual[:start_col] && col < visual[:end_col]
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
      rel = cached_syntax_color_columns(filetype, source_line_text)
      return {} if rel.empty?

      rel.each_with_object({}) do |(idx, color), h|
        h[source_col_offset + idx] = color
      end
    rescue StandardError
      {}
    end

    def cached_syntax_color_columns(filetype, source_line_text)
      key = [filetype.to_s, source_line_text.to_s]
      if (cached = @syntax_color_cache[key])
        return cached
      end

      cols = RuVim::Highlighter.color_columns(filetype, source_line_text)
      @syntax_color_cache[key] = cols
      @syntax_color_cache.shift while @syntax_color_cache.length > SYNTAX_CACHE_LIMIT
      cols
    end
  end
end
