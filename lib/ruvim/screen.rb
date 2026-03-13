# frozen_string_literal: true

module RuVim
  class Screen
    DEFAULT_TABSTOP = 2
    SYNTAX_CACHE_LIMIT = 2048
    WRAP_SEGMENTS_CACHE_LIMIT = 1024
    def initialize(terminal:)
      @terminal = terminal
      @last_frame = nil
      @syntax_color_cache = {}
      @wrapped_segments_cache = {}
      @sixel_overlays = []
      @sixel_cache = nil
    end

    def invalidate_cache!
      @last_frame = nil
    end

    def render(editor)
      @rich_render_info = nil
      @sixel_overlays = []

      rows, cols = @terminal.winsize
      editor.screen_columns = [cols.to_i, 1].max
      text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
      text_rows = [text_rows, 1].max
      text_cols = [text_cols, 1].max

      rects = window_rects(editor, text_rows:, text_cols:)
      if (current_rect = rects[editor.current_window_id])
        editor.current_window_view_height_hint = [current_rect[:height], 1].max
      end
      editor.window_order.each do |win_id|
        win = editor.windows.fetch(win_id)
        buf = editor.buffers.fetch(win.buffer_id)
        rect = rects[win_id]
        next unless rect
        content_width = [rect[:width] - number_column_width(editor, win, buf), 1].max
        if RuVim::RichView.active?(editor)
          # Vertical scrolling only — keep raw col_offset untouched
          win.ensure_visible(
            buf,
            height: [rect[:height], 1].max,
            width: content_width,
            tabstop: tabstop_for(editor, win, buf),
            scrolloff: editor.effective_option("scrolloff", window: win, buffer: buf),
            sidescrolloff: editor.effective_option("sidescrolloff", window: win, buffer: buf)
          )
          ensure_visible_rich(editor, win, buf, rect, content_width)
        else
          win.col_offset = 0 if wrap_enabled?(editor, win, buf)
          win.ensure_visible(
            buf,
            height: [rect[:height], 1].max,
            width: content_width,
            tabstop: tabstop_for(editor, win, buf),
            scrolloff: editor.effective_option("scrolloff", window: win, buffer: buf),
            sidescrolloff: editor.effective_option("sidescrolloff", window: win, buffer: buf)
          )
          if wrap_enabled?(editor, win, buf)
            ensure_visible_under_wrap(editor, win, buf, height: [rect[:height], 1].max, content_w: content_width)
          end
        end
      end

      frame = build_frame(editor, rows:, cols:, text_rows:, text_cols:, rects:)
      out = if can_diff_render?(frame)
              render_diff(frame)
            else
              render_full(frame)
            end
      cursor_row, cursor_col = cursor_screen_position(editor, text_rows, rects)
      out << "\e[#{cursor_row};#{cursor_col}H"
      if cursor_use_terminal?(editor)
        out << "\e[6 q"
        out << "\e[?25h"
      else
        out << "\e[?25l"
      end
      @last_frame = frame.merge(cursor_row:, cursor_col:)
      @terminal.write(out)
      emit_sixel_overlays
    end

    def current_window_view_height(editor)
      rows, cols = @terminal.winsize
      text_rows, text_cols = editor.text_viewport_size(rows:, cols:)
      text_rows = [text_rows, 1].max
      text_cols = [text_cols, 1].max
      rect = window_rects(editor, text_rows:, text_cols:)[editor.current_window_id]
      height = [rect ? rect[:height] : text_rows, 1].max
      editor.current_window_view_height_hint = height if editor.respond_to?(:current_window_view_height_hint=)
      height
    rescue StandardError
      1
    end

    private

    def build_frame(editor, rows:, cols:, text_rows:, text_cols:, rects:)
      lines = {}
      render_window_area(editor, lines, rects, text_rows:, text_cols:)

      if editor.hit_enter_active? && editor.hit_enter_lines
        render_hit_enter_overlay(editor, lines, text_rows:, cols:)
      else
        status_row = text_rows + 1
        lines[status_row] = "\e[7m#{truncate(status_line(editor, cols), cols)}\e[m"
        lines[status_row + 1] = ""

        if editor.command_line_active?
          cmd = editor.command_line
          lines[status_row + 1] = truncate("#{cmd.prefix}#{cmd.text}", cols)
        elsif editor.message_error?
          lines[status_row + 1] = error_message_line(editor.message.to_s, cols)
        elsif !editor.message.to_s.empty?
          lines[status_row + 1] = truncate(editor.message.to_s, cols)
        end
      end

      {
        rows: rows,
        cols: cols,
        lines: lines,
        rects: rects
      }
    end

    def render_hit_enter_overlay(editor, lines, text_rows:, cols:)
      msg_lines = editor.hit_enter_lines
      prompt = "Press ENTER or type command to continue"
      # Total rows available: text_rows (text area) + 1 (status) + 1 (command) = text_rows + 2
      total_rows = text_rows + 2
      # We need msg_lines.length rows for messages + 1 row for the prompt
      overlay_count = msg_lines.length + 1
      start_row = [total_rows - overlay_count + 1, 1].max
      msg_lines.each_with_index do |line, i|
        row_no = start_row + i
        break if row_no > total_rows
        lines[row_no] = truncate(line.to_s, cols)
      end
      prompt_row = start_row + msg_lines.length
      prompt_row = [prompt_row, total_rows].min
      lines[prompt_row] = "\e[7m#{truncate(prompt, cols)}\e[m"
    end

    def render_window_area(editor, lines, rects, text_rows:, text_cols:)
      render_tree_windows(editor, lines, rects, text_rows:, text_cols:)
    end

    def render_tree_windows(editor, lines, rects, text_rows:, text_cols:)
      # Pre-render each window's rows
      window_rows_cache = {}
      editor.window_order.each do |win_id|
        rect = rects[win_id]
        next unless rect
        window = editor.windows.fetch(win_id)
        buffer = editor.buffers.fetch(window.buffer_id)
        gutter_w = number_column_width(editor, window, buffer)
        content_w = [rect[:width] - gutter_w, 1].max
        window_rows_cache[win_id] = window_render_rows(editor, window, buffer, height: rect[:height], gutter_w:, content_w:)
      end

      # Build a row-plan: for each screen row, collect the pieces to concatenate
      row_plans = build_row_plans(editor.layout_tree, rects, text_rows, text_cols)

      1.upto(text_rows) do |row_no|
        plan = row_plans[row_no]
        unless plan
          lines[row_no] = " " * text_cols
          next
        end

        pieces = +""
        plan.each do |piece|
          case piece[:type]
          when :window
            rect = rects[piece[:id]]
            dy = row_no - rect[:top]
            rows = window_rows_cache[piece[:id]]
            text = (rows && dy >= 0 && dy < rect[:height]) ? (rows[dy] || " " * rect[:width]) : " " * rect[:width]
            pieces << text
          when :vsep
            pieces << "|"
          when :hsep
            pieces << "-" * piece[:width]
          when :blank
            pieces << " " * piece[:width]
          end
        end
        lines[row_no] = pieces
      end
    end

    # Build a row-by-row plan for compositing. Each row's plan is an array of
    # pieces to concatenate left-to-right.
    def build_row_plans(node, rects, text_rows, text_cols)
      plans = {}
      fill_row_plans(node, rects, plans, 1, text_rows)
      plans
    end

    def fill_row_plans(node, rects, plans, row_start, row_end)
      return unless node

      if node[:type] == :window
        rect = rects[node[:id]]
        return unless rect
        rect[:height].times do |dy|
          row_no = rect[:top] + dy
          next if row_no < row_start || row_no > row_end
          plans[row_no] ||= []
          plans[row_no] << { type: :window, id: node[:id] }
        end
        return
      end

      children = node[:children]
      if node[:type] == :vsplit
        children.each_with_index do |child, i|
          fill_row_plans(child, rects, plans, row_start, row_end)
          if i < children.length - 1
            # Insert vsep marker for the rows spanned by these children
            child_leaves = tree_leaves_for_rects(child)
            child_rects_list = child_leaves.filter_map { |id| rects[id] }
            next if child_rects_list.empty?
            top = child_rects_list.map { |r| r[:top] }.min
            bottom = child_rects_list.map { |r| r[:top] + r[:height] - 1 }.max
            top.upto(bottom) do |row_no|
              next if row_no < row_start || row_no > row_end
              plans[row_no] ||= []
              plans[row_no] << { type: :vsep }
            end
          end
        end
      elsif node[:type] == :hsplit
        children.each_with_index do |child, i|
          fill_row_plans(child, rects, plans, row_start, row_end)
          if i < children.length - 1
            child_leaves = tree_leaves_for_rects(child)
            child_rects_list = child_leaves.filter_map { |id| rects[id] }
            next if child_rects_list.empty?
            sep_row = child_rects_list.map { |r| r[:top] + r[:height] }.max
            left = child_rects_list.map { |r| r[:left] }.min
            right = child_rects_list.map { |r| r[:left] + r[:width] - 1 }.max
            next unless sep_row >= row_start && sep_row <= row_end
            plans[sep_row] ||= []
            plans[sep_row] << { type: :hsep, width: right - left + 1 }
          end
        end
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
      # Ultra-fast path: plain ASCII line with no highlighting — skip Cell creation entirely
      if can_bulk_render_line?(text, editor, buffer_row:, window:, buffer:)
        return bulk_render_line(text, width, col_offset: window.col_offset)
      end

      tabstop = tabstop_for(editor, window, buffer)
      cells, display_col = RuVim::TextMetrics.clip_cells_for_width(text, width, source_col_start: window.col_offset, tabstop:)
      render_cells(cells, display_col, editor, buffer_row:, window:, buffer:, width:, source_line: buffer.line_at(buffer_row),
                   source_col_offset: window.col_offset, leading_display_prefix: "")
    end

    def can_bulk_render_line?(text, editor, buffer_row:, window:, buffer:)
      return false if editor.current_window_id == window.id && window.cursor_y == buffer_row
      return false if editor.current_window_id == window.id && editor.visual_active?
      return false if !!editor.effective_option("cursorline", window:, buffer:)
      return false if !!editor.effective_option("list", window:, buffer:)
      return false unless colorcolumn_display_cols(editor, window, buffer).empty?
      return false if text.include?("\t")
      return false unless text.ascii_only?
      return false if text.match?(/[\x00-\x1f\x7f]/)  # control chars need sanitizing

      source_text = text[window.col_offset..].to_s
      return false unless search_highlight_source_cols(editor, source_text, source_col_offset: window.col_offset).empty?
      return false unless syntax_highlight_source_cols(editor, window, buffer, source_text, source_col_offset: window.col_offset).empty?

      true
    end

    def bulk_render_line(text, width, col_offset:)
      clipped = text[col_offset, width].to_s
      clipped + (" " * [width - clipped.length, 0].max)
    end

    def render_text_segment(source_line, editor, buffer_row:, window:, buffer:, width:, source_col_start:, display_prefix: "")
      prefix = display_prefix

      # Bulk path: no prefix, printable ASCII, no highlighting
      if prefix.empty? && can_bulk_render_line?(source_line, editor, buffer_row:, window:, buffer:)
        return bulk_render_line(source_line, width, col_offset: source_col_start)
      end

      tabstop = tabstop_for(editor, window, buffer)
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
        out = prefix_render + body
        out
      end
    end

    def render_cells(cells, display_col, editor, buffer_row:, window:, buffer:, width:, source_line:, source_col_offset:, leading_display_prefix:)
      highlighted = +""
      tabstop = tabstop_for(editor, window, buffer)
      visual = (editor.current_window_id == window.id && editor.visual_active?) ? editor.visual_selection(window) : nil
      text_for_highlight = source_line[source_col_offset..].to_s
      search_cols = search_highlight_source_cols(editor, text_for_highlight, source_col_offset: source_col_offset)
      syntax_cols = syntax_highlight_source_cols(editor, window, buffer, text_for_highlight, source_col_offset: source_col_offset)
      spell_cols = spell_highlight_source_cols(editor, window, buffer, text_for_highlight, source_col_offset: source_col_offset)
      list_enabled = !!editor.effective_option("list", window:, buffer:)
      listchars = parse_listchars(editor.effective_option("listchars", window:, buffer:))
      tab_seen = {}
      trail_from = source_line.rstrip.length
      cursorline = !!editor.effective_option("cursorline", window:, buffer:)
      current_line = (editor.current_window_id == window.id && window.cursor_y == buffer_row)
      cursorline_enabled = cursorline && current_line
      colorcolumns = colorcolumn_display_cols(editor, window, buffer)
      leading_prefix_width = RuVim::DisplayWidth.display_width(leading_display_prefix.to_s, tabstop:)
      display_pos = leading_prefix_width

      # Fast path: no highlighting needed — bulk output glyphs
      if !current_line && !visual && !cursorline_enabled &&
         !list_enabled && search_cols.empty? &&
         syntax_cols.empty? && spell_cols.empty? && colorcolumns.empty?
        cells.each do |cell|
          highlighted << cell.glyph
          display_pos += [cell.display_width, 1].max
        end
      else
        cells.each do |cell|
          ch = display_glyph_for_cell(cell, source_line, list_enabled, listchars, tab_seen, trail_from)
          buffer_col = cell.source_col
          selected = selected_in_visual?(visual, buffer_row, buffer_col)
          cursor_here = (current_line && window.cursor_x == buffer_col)
          colorcolumn_here = colorcolumns[display_pos]
          if cursor_here
            highlighted << cursor_cell_render(editor, ch)
          elsif selected
            highlighted << "\e[7m#{ch}\e[m"
          elsif search_cols[buffer_col]
            highlighted << "#{search_bg_seq(editor)}#{ch}\e[m"
          elsif colorcolumn_here
            highlighted << "#{colorcolumn_bg_seq(editor)}#{ch}\e[m"
          elsif cursorline_enabled
            highlighted << "#{cursorline_bg_seq(editor)}#{ch}\e[m"
          elsif (syntax_color = syntax_cols[buffer_col])
            if spell_cols[buffer_col]
              highlighted << "#{syntax_color}\e[4;31m#{ch}\e[m"
            else
              highlighted << "#{syntax_color}#{ch}\e[m"
            end
          elsif spell_cols[buffer_col]
            highlighted << "\e[4;31m#{ch}\e[m"
          else
            highlighted << ch
          end
          display_pos += [cell.display_width, 1].max
        end
      end

      if editor.current_window_id == window.id && window.cursor_y == buffer_row
        cursor_target = virtual_cursor_display_pos(source_line, window.cursor_x, source_col_offset:, tabstop:, leading_prefix_width:)
        if cursor_target && cursor_target >= display_pos && cursor_target < width
          gap = cursor_target - display_pos
          if gap.positive?
            highlighted << (" " * gap)
            display_col += gap
            display_pos += gap
          end
          highlighted << cursor_cell_render(editor, " ")
          display_col += 1
          display_pos += 1
        end
      end

      trailing = [width - display_col, 0].max
      if trailing.positive? && cursorline_enabled
        trailing.times do
          if colorcolumns[display_pos]
            highlighted << "#{colorcolumn_bg_seq(editor)} \e[m"
          else
            highlighted << "#{cursorline_bg_seq(editor)} \e[m"
          end
          display_pos += 1
        end
      else
        highlighted << (" " * trailing)
      end
      highlighted
    end

    def virtual_cursor_display_pos(source_line, cursor_x, source_col_offset:, tabstop:, leading_prefix_width:)
      return nil if cursor_x < source_col_offset

      base = RuVim::TextMetrics.screen_col_for_char_index(source_line, cursor_x, tabstop:) -
             RuVim::TextMetrics.screen_col_for_char_index(source_line, source_col_offset, tabstop:)
      extra = [cursor_x - source_line.length, 0].max
      leading_prefix_width + [base, 0].max + extra
    end

    def window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      return plain_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:) unless wrap_enabled?(editor, window, buffer)

      wrapped_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
    end

    def plain_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      if RuVim::RichView.active?(editor)
        return rich_view_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      end

      Array.new(height) do |dy|
        buffer_row = window.row_offset + dy
        if buffer_row < buffer.line_count
          render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
        else
          render_gutter_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w)
        end
      end
    end

    def rich_view_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      raw_lines = []
      height.times do |dy|
        row = window.row_offset + dy
        raw_lines << (row < buffer.line_count ? buffer.line_at(row) : nil)
      end

      non_nil = raw_lines.compact.map { |l| RuVim::TextMetrics.terminal_safe_text(l) }
      context = rich_view_context(editor, window, buffer)
      formatted = RuVim::RichView.render_visible_lines(editor, non_nil, context: context)
      fmt_idx = 0
      col_offset_sc = @rich_render_info ? @rich_render_info[:col_offset_sc] : 0
      sixel_enabled = sixel_enabled?(editor)

      Array.new(height) do |dy|
        buffer_row = window.row_offset + dy
        prefix = render_gutter_prefix(editor, window, buffer, buffer_row < buffer.line_count ? buffer_row : nil, gutter_w)
        if buffer_row < buffer.line_count
          line = formatted[fmt_idx] || ""
          fmt_idx += 1

          if line.is_a?(Hash) && line[:type] == :image
            body = render_image_placeholder(editor, buffer, line, content_w, sixel_enabled, gutter_w, dy)
            prefix + body
          else
            cursor_col = nil
            if editor.current_window_id == window.id && window.cursor_y == buffer_row && @rich_render_info
              cursor_col = @rich_render_info[:cursor_sc] - col_offset_sc
            end
            body = render_rich_view_line_sc(line, width: content_w, skip_sc: col_offset_sc, cursor_col: cursor_col)
            prefix + body
          end
        else
          prefix + pad_plain_display("~", content_w)
        end
      end
    end

    def rich_view_context(editor, window, buffer)
      state = editor.rich_state
      return {} unless state

      format = state[:format]
      renderer = RuVim::RichView.renderer_for(format)
      return {} unless renderer && renderer.respond_to?(:needs_pre_context?) && renderer.needs_pre_context?

      # Collect lines before the visible area for state tracking (e.g., code fences)
      pre_lines = []
      (0...window.row_offset).each do |row|
        pre_lines << buffer.line_at(row) if row < buffer.line_count
      end
      { pre_context_lines: pre_lines }
    end

    def sixel_enabled?(editor)
      opt = editor.effective_option("sixel").to_s
      case opt
      when "on"  then true
      when "off" then false
      else @terminal.respond_to?(:sixel_capable?) && @terminal.sixel_capable?
      end
    end

    def render_image_placeholder(editor, buffer, img_hash, content_w, sixel_enabled, gutter_w, dy)
      alt = img_hash[:alt].to_s
      path = img_hash[:path].to_s

      if sixel_enabled
        require_relative "sixel" unless defined?(RuVim::Sixel)
        buf_path = buffer.respond_to?(:file_path) ? buffer.file_path : nil
        buf_dir = buf_path && !buf_path.to_s.empty? ? File.dirname(buf_path) : nil
        cell_w, cell_h = @terminal.cell_size
        @sixel_cache ||= RuVim::Sixel::Cache.new
        sixel_data = RuVim::Sixel.load_image(path, buffer_dir: buf_dir,
                                              max_width_cells: [content_w, 1].max, max_height_cells: 10,
                                              cell_width: cell_w, cell_height: cell_h, cache: @sixel_cache)
        if sixel_data
          @sixel_overlays << { dy: dy, gutter_w: gutter_w, data: sixel_data[:sixel] }
        end
      end

      placeholder = "\e[90m[Image: #{alt.empty? ? path : alt}]\e[m"
      pad_plain_display(placeholder, content_w)
    end

    def emit_sixel_overlays
      return if @sixel_overlays.empty?

      out = +""
      @sixel_overlays.each do |overlay|
        # Move cursor to overlay position and emit sixel data
        row = overlay[:dy] + 1  # 1-based
        col = overlay[:gutter_w] + 1
        out << "\e[#{row};#{col}H"
        out << overlay[:data]
      end
      @terminal.write(out)
    end

    # Render a formatted rich-view line by skipping `skip_sc` display columns
    # then showing the next `width` display columns.  Using screen columns
    # instead of character indices keeps alignment correct when lines mix
    # CJK and ASCII characters with different char-to-display-width ratios.
    # ANSI escape sequences (\e[...m) are treated as zero-width and passed
    # through to the output unchanged.
    def render_rich_view_line_sc(text, width:, skip_sc:, cursor_col: nil)
      # Phase 1: skip `skip_sc` display columns
      # Collect ANSI sequences encountered during skip so active styles carry over.
      chars = text
      pos = 0
      skipped = 0
      len = chars.length
      pending_ansi = +""
      while pos < len
        if chars[pos] == "\e"
          end_pos = find_ansi_end(chars, pos)
          pending_ansi << chars[pos...end_pos]
          pos = end_pos
          next
        end
        ch = chars[pos]
        cw = RuVim::DisplayWidth.cell_width(ch, col: skipped, tabstop: 8)
        break if skipped + cw > skip_sc
        skipped += cw
        pos += 1
      end
      # If a wide char straddles the skip boundary, pad with a space
      leading_pad = skip_sc - skipped

      # Phase 2: collect `width` display columns
      out = +""
      out << pending_ansi unless pending_ansi.empty?
      col = 0
      if leading_pad > 0
        out << " " * leading_pad
        col += leading_pad
        pos += 1 if pos < len && chars[pos] != "\e"
      end
      cursor_rendered = false
      while pos < len
        if chars[pos] == "\e"
          end_pos = find_ansi_end(chars, pos)
          out << chars[pos...end_pos]
          pos = end_pos
          next
        end
        ch = chars[pos]
        cw = RuVim::DisplayWidth.cell_width(ch, col: skipped + col, tabstop: 8)
        break if col + cw > width
        if cursor_col && col == cursor_col && !cursor_rendered
          out << "\e[7m#{ch}\e[m"
          cursor_rendered = true
        else
          out << ch
        end
        col += cw
        pos += 1
      end
      trailing = [width - col, 0].max
      if cursor_col && !cursor_rendered && cursor_col >= col && cursor_col < col + trailing
        gap = cursor_col - col
        out << " " * gap if gap > 0
        out << "\e[7m \e[m"
        out << " " * [trailing - gap - 1, 0].max
      else
        out << " " * trailing
      end
      out << "\e[m"
      out
    end

    # Find the end position of an ANSI escape sequence starting at `pos`.
    # Handles CSI sequences (\e[...X) where X is a letter.
    def find_ansi_end(str, pos)
      i = pos + 1  # skip \e
      return i if i >= str.length
      if str[i] == "["
        i += 1
        # Skip parameter bytes and intermediate bytes
        i += 1 while i < str.length && str[i].ord >= 0x20 && str[i].ord <= 0x3F
        # Final byte
        i += 1 if i < str.length && str[i].ord >= 0x40 && str[i].ord <= 0x7E
      else
        i += 1
      end
      i
    end

    def wrapped_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
      rows = []
      row_idx = window.row_offset
      seg_skip = window.wrap_seg_offset
      while rows.length < height
        if row_idx >= buffer.line_count
          rows << (render_gutter_prefix(editor, window, buffer, nil, gutter_w) + pad_plain_display("~", content_w))
          next
        end

        line = buffer.line_at(row_idx)
        segments = wrapped_segments_for_line(editor, window, buffer, line, width: content_w)
        segments.each_with_index do |seg, seg_i|
          if seg_skip > 0
            seg_skip -= 1
            next
          end
          break if rows.length >= height

          show_line_nr = (seg_i.zero? && window.wrap_seg_offset.zero?) || (row_idx != window.row_offset)
          gutter = render_gutter_prefix(editor, window, buffer, (show_line_nr && seg_i.zero?) ? row_idx : nil, gutter_w)
          rows << gutter + render_text_segment(line, editor, buffer_row: row_idx, window:, buffer:, width: content_w,
                                               source_col_start: seg[:source_col_start], display_prefix: seg[:display_prefix])
        end
        row_idx += 1
      end
      rows
    end

    def ensure_visible_under_wrap(editor, window, buffer, height:, content_w:)
      return if height <= 0 || buffer.line_count <= 0

      window.row_offset = [[window.row_offset, 0].max, buffer.line_count - 1].min
      window.wrap_seg_offset = 0 if window.cursor_y != window.row_offset
      return if window.cursor_y < window.row_offset

      cursor_line = buffer.line_at(window.cursor_y)
      cursor_segs = wrapped_segments_for_line(editor, window, buffer, cursor_line, width: content_w)
      cursor_seg_index = wrapped_segment_index(cursor_segs, window.cursor_x)

      visual_rows_before = 0
      row = window.row_offset
      while row < window.cursor_y
        segs_count = wrapped_segments_for_line(editor, window, buffer, buffer.line_at(row), width: content_w).length
        segs_count -= window.wrap_seg_offset if row == window.row_offset
        visual_rows_before += segs_count
        row += 1
      end

      # Try to show all segments of the cursor line, not just the cursor's segment
      last_seg_visual_row = visual_rows_before + cursor_segs.length - 1
      while last_seg_visual_row >= height && window.row_offset < window.cursor_y
        first_line_segs = wrapped_segments_for_line(editor, window, buffer, buffer.line_at(window.row_offset), width: content_w).length
        dropped = first_line_segs - window.wrap_seg_offset
        window.wrap_seg_offset = 0
        window.row_offset += 1
        last_seg_visual_row -= dropped
        visual_rows_before -= dropped
      end

      # If cursor line itself wraps beyond viewport, skip leading segments to show cursor
      cursor_visual_row = visual_rows_before + cursor_seg_index
      if cursor_visual_row >= height && window.row_offset == window.cursor_y
        window.wrap_seg_offset = cursor_seg_index - (height - 1)
        window.wrap_seg_offset = 0 if window.wrap_seg_offset < 0
      end
    rescue StandardError
      nil
    end

    # Compute a screen-column-based horizontal scroll offset for rich mode.
    # Unlike normal mode (which stores a char index in window.col_offset),
    # rich mode must scroll by display columns because CJK-padded formatted
    # lines have different character counts for the same display width.
    def ensure_visible_rich(editor, win, buf, rect, content_w)
      state = editor.rich_state
      unless state
        @rich_render_info = nil
        @rich_col_offset_sc = 0
        return
      end

      format = state[:format]
      delimiter = state[:delimiter]
      renderer = RuVim::RichView.renderer_for(format)
      height = [rect[:height], 1].max

      raw_lines = height.times.map { |dy|
        row = win.row_offset + dy
        row < buf.line_count ? buf.line_at(row) : nil
      }.compact

      cursor_raw_line = buf.line_at(win.cursor_y)

      if renderer && renderer.respond_to?(:cursor_display_col)
        cursor_sc = renderer.cursor_display_col(
          cursor_raw_line, win.cursor_x, visible_lines: raw_lines, delimiter: delimiter
        )
      else
        cursor_sc = RuVim::TextMetrics.screen_col_for_char_index(cursor_raw_line, win.cursor_x)
      end

      # Use persisted screen-column offset from previous frame
      offset_sc = @rich_col_offset_sc || 0

      sso = editor.effective_option("sidescrolloff", window: win, buffer: buf).to_i
      sso = [[sso, 0].max, [content_w - 1, 0].max].min

      if cursor_sc < offset_sc + sso
        offset_sc = [cursor_sc - sso, 0].max
      elsif cursor_sc >= offset_sc + content_w - sso
        offset_sc = cursor_sc - content_w + sso + 1
      end
      offset_sc = [offset_sc, 0].max

      @rich_col_offset_sc = offset_sc

      if win == editor.current_window
        @rich_render_info = {
          col_offset_sc: offset_sc,
          cursor_sc: cursor_sc,
          delimiter: delimiter
        }
      end
    end

    def wrap_enabled?(editor, window, buffer)
      return false if editor.rich_state

      !!editor.effective_option("wrap", window:, buffer:)
    end

    def wrapped_segments_for_line(editor, window, buffer, line, width:)
      return [{ source_col_start: 0, display_prefix: "" }] if width <= 0

      tabstop = tabstop_for(editor, window, buffer)
      linebreak = !!editor.effective_option("linebreak", window:, buffer:)
      showbreak = editor.effective_option("showbreak", window:, buffer:).to_s
      breakindent = !!editor.effective_option("breakindent", window:, buffer:)
      return [{ source_col_start: 0, display_prefix: "" }] if line.empty?

      cache_key = [line.object_id, line.length, line.hash, width, tabstop, linebreak, showbreak, breakindent]
      if (cached = @wrapped_segments_cache[cache_key])
        return cached
      end

      indent_prefix = breakindent ? wrapped_indent_prefix(line, tabstop:, max_width: [width - RuVim::DisplayWidth.display_width(showbreak, tabstop:), 0].max) : ""
      segs = compute_wrapped_segments(line, width:, tabstop:, linebreak:, showbreak:, indent_prefix:)
      @wrapped_segments_cache[cache_key] = segs
      if @wrapped_segments_cache.length > WRAP_SEGMENTS_CACHE_LIMIT
        trim = @wrapped_segments_cache.length - WRAP_SEGMENTS_CACHE_LIMIT / 2
        trim.times { @wrapped_segments_cache.shift }
      end
      segs
    end

    def compute_wrapped_segments(line, width:, tabstop:, linebreak:, showbreak:, indent_prefix:)
      segs = []
      start_col = 0
      first = true

      while start_col < line.length
        display_prefix = first ? "" : "#{showbreak}#{indent_prefix}"
        prefix_w = RuVim::DisplayWidth.display_width(display_prefix, tabstop:)
        avail = [width - prefix_w, 1].max
        cells, = RuVim::TextMetrics.clip_cells_for_width(line[start_col..].to_s, avail, source_col_start: start_col, tabstop:)
        if cells.empty?
          segs << { source_col_start: start_col, display_prefix: display_prefix }.freeze
          break
        end

        if linebreak && cells.length > 1
          break_idx = linebreak_break_index(cells, line)
          if break_idx && break_idx < cells.length - 1
            cells = cells[0..break_idx]
          end
        end

        segs << { source_col_start: start_col, display_prefix: display_prefix }.freeze
        next_start = cells.last.source_col + 1
        if linebreak
          next_start += 1 while next_start < line.length && line[next_start] == " "
        end
        break if next_start <= start_col

        start_col = next_start
        first = false
      end

      segs.freeze
    end

    def wrapped_segment_index(segs, cursor_x)
      x = cursor_x
      seg_index = 0
      segs.each_with_index do |seg, i|
        nxt = segs[i + 1]
        if nxt.nil? || x < nxt[:source_col_start]
          seg_index = i
          break
        end
      end
      seg_index
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

    def display_glyph_for_cell(cell, source_line, list_enabled, listchars, tab_seen, trail_from)
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
      raw_key = raw
      @listchars_cache ||= {}
      return @listchars_cache[raw_key] if @listchars_cache.key?(raw_key)

      cfg = { tab_head: ">", tab_fill: "-", trail: "-", nbsp: "+" }
      raw_key.split(",").each do |entry|
        entry_key, val = entry.split(":", 2)
        next unless entry_key && val

        case entry_key.strip
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
      @listchars_cache[raw_key] = cfg.freeze
    rescue StandardError
      { tab_head: ">", tab_fill: "-", trail: "-", nbsp: "+" }
    end

    def render_window_row(editor, window, buffer, buffer_row, gutter_w:, content_w:)
      line = buffer.line_at(buffer_row)
      line = line[window.col_offset..] || ""
      prefix = render_gutter_prefix(editor, window, buffer, buffer_row, gutter_w)
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
      labels = buffer.options["gutter_labels"]
      if labels && !labels.empty?
        max_w = labels.map { |l| RuVim::DisplayWidth.display_width(l.to_s) }.max || 0
        return max_w
      end

      sign_w = sign_column_width(editor, window, buffer)
      enabled = editor.effective_option("number", window:, buffer:) || editor.effective_option("relativenumber", window:, buffer:)
      return sign_w unless enabled

      base = [buffer.line_count.to_s.length, 1].max
      minw = editor.effective_option("numberwidth", window:, buffer:).to_i
      sign_w + ([[base, minw].max, 1].max + 1)
    end

    def line_number_prefix(editor, window, buffer, buffer_row, width)
      return "" if width <= 0
      sign_w = sign_column_width(editor, window, buffer)
      sign = " " * sign_w
      num_width = [width - sign_w, 0].max
      show_abs = editor.effective_option("number", window:, buffer:)
      show_rel = editor.effective_option("relativenumber", window:, buffer:)
      return sign + (" " * num_width) unless show_abs || show_rel
      return sign + (" " * num_width) if buffer_row.nil?

      num =
        if show_rel && buffer_row != window.cursor_y
          (buffer_row - window.cursor_y).abs.to_s
        elsif show_abs
          (buffer_row + 1).to_s
        else
          "0"
        end
      sign + num.rjust([num_width - 1, 0].max) + (num_width.positive? ? " " : "")
    end

    def render_gutter_prefix(editor, window, buffer, buffer_row, width)
      labels = buffer.options["gutter_labels"]
      if labels
        return " " * width if buffer_row.nil?

        label = (labels[buffer_row] || "").ljust(width)[0, width]
        color = line_number_fg_seq(editor, current_line: false)
        return "#{color}#{label}\e[m"
      end

      prefix = line_number_prefix(editor, window, buffer, buffer_row, width)
      return prefix if prefix.empty?
      return prefix if buffer_row.nil?

      current_line = (buffer_row == window.cursor_y)
      "#{line_number_fg_seq(editor, current_line: current_line)}#{prefix}\e[m"
    end

    def sign_column_width(editor, window, buffer)
      raw = editor.effective_option("signcolumn", window:, buffer:).to_s
      case raw
      when "", "auto", "number"
        0
      when "no"
        0
      else
        if (m = /\Ayes(?::(\d+))?\z/.match(raw))
          n = m[1].to_i
          n = 1 if n <= 0
          n
        else
          1
        end
      end
    rescue StandardError
      0
    end

    def colorcolumn_display_cols(editor, window, buffer)
      raw = editor.effective_option("colorcolumn", window:, buffer:).to_s
      return {} if raw.empty?

      @colorcolumn_cache ||= {}
      return @colorcolumn_cache[raw] if @colorcolumn_cache.key?(raw)

      cols = {}
      raw.split(",").each do |tok|
        t = tok.strip
        next if t.empty?
        next unless t.match?(/\A\d+\z/)
        n = t.to_i
        next if n <= 0
        cols[n - 1] = true
      end
      @colorcolumn_cache[raw] = cols.freeze
    rescue StandardError
      {}
    end

    def pad_plain_display(text, width)
      RuVim::TextMetrics.pad_plain_to_screen_width(text, width, tabstop: DEFAULT_TABSTOP)
    end

    def search_bg_seq(editor)
      term_color(editor, "\e[48;2;255;215;0m", "\e[43m")
    end

    def colorcolumn_bg_seq(editor)
      term_color(editor, "\e[48;2;72;72;72m", "\e[48;5;238m")
    end

    def cursorline_bg_seq(editor)
      term_color(editor, "\e[48;2;58;58;58m", "\e[48;5;236m")
    end

    def term_color(editor, truecolor_seq, fallback_seq)
      truecolor_enabled?(editor) ? truecolor_seq : fallback_seq
    end

    def line_number_fg_seq(editor, current_line: false)
      if truecolor_enabled?(editor)
        current_line ? "\e[38;2;190;190;190m" : "\e[38;2;120;120;120m"
      else
        current_line ? "\e[37m" : "\e[90m"
      end
    end

    def truecolor_enabled?(editor)
      !!editor.effective_option("termguicolors")
    rescue StandardError
      false
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
             when :rich then "-- RICH --"
             else "-- NORMAL --"
             end

      path = buffer.display_name
      mod = buffer.modified? ? " [+]" : ""
      stream = buffer.stream_status ? " [#{buffer.stream_status}]" : ""
      cmd = buffer.stream_command ? " #{buffer.stream_command}" : ""
      tab = tab_status_token(editor)
      left = "#{mode} #{path}#{mod}#{stream}#{cmd}"
      right = " #{window.cursor_y + 1}:#{window.cursor_x + 1}#{tab} "
      body_width = [width - right.length, 0].max
      "#{left.ljust(body_width)[0, body_width]}#{right}"
    end


    def tab_status_token(editor)
      return "" if editor.tabpage_count <= 1

      " tab:#{editor.current_tabpage_number}/#{editor.tabpage_count}"
    end

    def truncate(str, width)
      safe = RuVim::TextMetrics.terminal_safe_text(str)
      RuVim::TextMetrics.pad_plain_to_screen_width(safe, width)
    end

    def error_message_line(msg, cols)
      "\e[97;41m#{truncate(msg, cols)}\e[m"
    end

    def cursor_cell_render(editor, ch)
      "#{cursor_cell_seq(editor)}#{ch}\e[m"
    end

    def cursor_cell_seq(editor)
      "\e[7m"
    end

    # Insert/command-line: show terminal bar cursor; otherwise: hide terminal cursor, use cell rendering
    def cursor_use_terminal?(editor)
      case editor.mode
      when :insert, :command_line
        true
      else
        false
      end
    end

    def cursor_screen_position(editor, text_rows, rects)
      window = editor.current_window

      if editor.hit_enter_active? && editor.hit_enter_lines
        total_rows = text_rows + 2
        msg_count = editor.hit_enter_lines.length
        prompt_row = [total_rows - msg_count, 1].max + msg_count
        prompt_row = [prompt_row, total_rows].min
        prompt_text = "Press ENTER or type command to continue"
        col = [prompt_text.length + 1, total_rows].min
        return [prompt_row, col]
      end

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
          segs_count = wrapped_segments_for_line(editor, window, buffer, buffer.line_at(row), width: content_w).length
          segs_count -= window.wrap_seg_offset if row == window.row_offset
          visual_rows_before += segs_count
          row += 1
        end
        segs = wrapped_segments_for_line(editor, window, buffer, line, width: content_w)
        seg_index = wrapped_segment_index(segs, window.cursor_x)
        seg = segs[seg_index] || { source_col_start: 0, display_prefix: "" }
        effective_seg_index = seg_index
        effective_seg_index -= window.wrap_seg_offset if window.cursor_y == window.row_offset
        row = rect[:top] + visual_rows_before + effective_seg_index
        seg_prefix_w = RuVim::DisplayWidth.display_width(seg[:display_prefix].to_s, tabstop:)
        extra_virtual = [window.cursor_x - line.length, 0].max
        cursor_sc = RuVim::TextMetrics.screen_col_for_char_index(line, window.cursor_x, tabstop:) + extra_virtual
        seg_sc = RuVim::TextMetrics.screen_col_for_char_index(line, seg[:source_col_start], tabstop:)
        col = rect[:left] + gutter_w + seg_prefix_w + [cursor_sc - seg_sc, 0].max
      elsif @rich_render_info
        row = rect[:top] + (window.cursor_y - window.row_offset)
        col = rect[:left] + gutter_w + [@rich_render_info[:cursor_sc] - @rich_render_info[:col_offset_sc], 0].max
      else
        row = rect[:top] + (window.cursor_y - window.row_offset)
        extra_virtual = [window.cursor_x - line.length, 0].max
        prefix_screen_col = RuVim::TextMetrics.screen_col_for_char_index(line, window.cursor_x, tabstop:) -
                            RuVim::TextMetrics.screen_col_for_char_index(line, window.col_offset, tabstop:)
        col = rect[:left] + gutter_w + [prefix_screen_col, 0].max + extra_virtual
      end
      min_row = [rect[:top], 1].max
      max_row = [rect[:top] + [rect[:height], 1].max - 1, min_row].max
      min_col = [rect[:left], 1].max
      max_col = [rect[:left] + [rect[:width], 1].max - 1, min_col].max
      row = [[row, min_row].max, max_row].min
      col = [[col, min_col].max, max_col].min
      [row, col]
    end

    def window_rects(editor, text_rows:, text_cols:)
      tree = editor.layout_tree
      return {} if tree.nil?
      ids = editor.window_order
      return {} if ids.empty?
      return { ids.first => { top: 1, left: 1, height: text_rows, width: text_cols } } if ids.length == 1

      compute_tree_rects(tree, top: 1, left: 1, height: text_rows, width: text_cols)
    end

    def compute_tree_rects(node, top:, left:, height:, width:)
      if node[:type] == :window
        return { node[:id] => { top: top, left: left, height: height, width: width } }
      end

      children = node[:children]
      n = children.length
      rects = {}
      weights = node[:weights]

      case node[:type]
      when :vsplit
        sep_count = n - 1
        usable = [width - sep_count, n].max
        widths = weighted_split_sizes(usable, n, weights)
        cur_left = left
        children.each_with_index do |child, i|
          w = widths[i]
          child_rects = compute_tree_rects(child, top: top, left: cur_left, height: height, width: w)
          child_rects.each_value { |r| r[:separator] = :vertical }
          rects.merge!(child_rects)
          cur_left += w + 1
        end
      when :hsplit
        sep_count = n - 1
        usable = [height - sep_count, n].max
        heights = weighted_split_sizes(usable, n, weights)
        cur_top = top
        children.each_with_index do |child, i|
          h = heights[i]
          child_rects = compute_tree_rects(child, top: cur_top, left: left, height: h, width: width)
          child_rects.each_value { |r| r[:separator] = :horizontal }
          rects.merge!(child_rects)
          if i < n - 1
            # Mark separator row for the last window in this child
            child_leaves = tree_leaves_for_rects(child)
            last_leaf = child_leaves.last
            rects[last_leaf][:sep_row] = cur_top + h if last_leaf && rects[last_leaf]
          end
          cur_top += h + 1
        end
      end

      rects
    end

    def tree_leaves_for_rects(node)
      return [node[:id]] if node[:type] == :window

      node[:children].flat_map { |c| tree_leaves_for_rects(c) }
    end

    def split_sizes(total, n)
      base = total / n
      rem = total % n
      Array.new(n) { |i| base + (i < rem ? 1 : 0) }
    end

    def weighted_split_sizes(total, n, weights)
      return split_sizes(total, n) unless weights && weights.length == n

      wsum = weights.sum.to_f
      return split_sizes(total, n) if wsum <= 0

      raw = weights.map { |w| (w / wsum * total).floor }
      raw.map! { |v| [v, 1].max }
      remainder = total - raw.sum
      remainder.times { |i| raw[i % n] += 1 } if remainder > 0
      if remainder < 0
        (-remainder).times do |i|
          idx = (n - 1 - i) % n
          raw[idx] -= 1 if raw[idx] > 1
        end
      end
      raw
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
      return {} if editor.hlsearch_suppressed?

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
      lang_mod = buffer.lang_module
      rel = cached_syntax_color_columns(lang_mod, source_line_text)
      return {} if rel.empty?

      rel.each_with_object({}) do |(idx, color), h|
        h[source_col_offset + idx] = color
      end
    rescue StandardError
      {}
    end

    def spell_highlight_source_cols(editor, window, buffer, source_line_text, source_col_offset:)
      return {} unless editor.effective_option("spell", window:, buffer:)

      SpellChecker.instance.spell_highlight_cols(source_line_text, source_col_offset: source_col_offset)
    end

    def cached_syntax_color_columns(lang_mod, source_line_text)
      key = [lang_mod, source_line_text.to_s]
      if (cached = @syntax_color_cache[key])
        return cached
      end

      cols = lang_mod.respond_to?(:color_columns) ? lang_mod.color_columns(source_line_text) : {}
      @syntax_color_cache[key] = cols
      if @syntax_color_cache.length > SYNTAX_CACHE_LIMIT
        trim = @syntax_color_cache.length - SYNTAX_CACHE_LIMIT / 2
        trim.times { @syntax_color_cache.shift }
      end
      cols
    end
  end
end
