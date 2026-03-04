module RuVim
  module RichView
    module MarkdownRenderer
      module_function

      def delimiter_for(_format)
        nil
      end

      def needs_pre_context?
        true
      end

      def render_visible(lines, delimiter:, context: {})
        return lines if lines.nil? || lines.empty?

        state = BlockState.new
        pre = context[:pre_context_lines]
        if pre
          pre.each { |l| state.scan_line(l) }
        end

        # Identify table groups for column-width alignment
        table_groups = identify_table_groups(lines)

        lines.each_with_index.map do |line, idx|
          rendered = render_line(line, state, table_groups[idx])
          state.scan_line(line)
          rendered
        end
      end

      def cursor_display_col(raw_line, cursor_x, visible_lines:, delimiter:)
        if table_line?(raw_line)
          table_lines = visible_lines.select { |l| table_line?(l) }
          group = build_table_group(table_lines)
          if group
            return table_cursor_display_col(raw_line, cursor_x, group)
          end
        end
        RuVim::TextMetrics.screen_col_for_char_index(raw_line, cursor_x)
      end

      # --- BlockState: tracks code fence open/close ---

      class BlockState
        attr_reader :in_code_block, :fence_marker

        def initialize
          @in_code_block = false
          @fence_marker = nil
        end

        def scan_line(line)
          stripped = line.to_s.strip
          if @in_code_block
            if fence_close?(stripped)
              @in_code_block = false
              @fence_marker = nil
            end
          else
            marker = fence_open(stripped)
            if marker
              @in_code_block = true
              @fence_marker = marker
            end
          end
        end

        private

        def fence_open(stripped)
          if (m = stripped.match(/\A(`{3,})(.*)\z/))
            m[1]
          elsif (m = stripped.match(/\A(~{3,})(.*)\z/))
            m[1]
          end
        end

        def fence_close?(stripped)
          return false unless @fence_marker
          if @fence_marker.start_with?("`")
            stripped.match?(/\A`{#{@fence_marker.length},}\s*\z/)
          else
            stripped.match?(/\A~{#{@fence_marker.length},}\s*\z/)
          end
        end
      end

      # --- Line rendering ---

      def render_line(line, state, table_group)
        stripped = line.to_s.strip

        # Code fence open/close
        if !state.in_code_block && fence_line?(stripped)
          return "\e[90m#{line}\e[m"
        end

        if state.in_code_block
          if fence_line?(stripped)
            return "\e[90m#{line}\e[m"
          end
          return "\e[38;5;223m#{line}\e[m"
        end

        # HR
        if stripped.match?(/\A(\-{3,}|\*{3,}|_{3,})\s*\z/)
          return render_hr(line)
        end

        # Heading
        if (m = line.match(/\A(\s*)(\#{1,6})\s/))
          return render_heading(line, m[2].length)
        end

        # Block quote
        if line.match?(/\A\s*> /)
          return "\e[36m#{apply_inline(line)}\e[m"
        end

        # Table
        if table_group
          return render_table_line(line, stripped, table_group)
        end

        # Default: inline decoration only
        apply_inline(line)
      end

      def fence_line?(stripped)
        stripped.match?(/\A(`{3,}|~{3,})/)
      end

      # --- Heading rendering ---

      HEADING_STYLES = {
        1 => "\e[1;33m",   # bold yellow
        2 => "\e[1;36m",   # bold cyan
        3 => "\e[1;32m",   # bold green
        4 => "\e[1;35m",   # bold magenta
        5 => "\e[1;34m",   # bold blue
        6 => "\e[1;90m"    # bold dim
      }.freeze

      def render_heading(line, level)
        style = HEADING_STYLES[level] || HEADING_STYLES[6]
        "#{style}#{line}\e[m"
      end

      # --- HR rendering ---

      def render_hr(line)
        # Replace the HR marker with box-drawing horizontal line
        width = [line.length, 3].max
        "\e[90m#{"─" * width}\e[m"
      end

      # --- Inline decoration ---

      def apply_inline(line)
        result = line.to_s.dup

        # Checkbox (must come before bold/italic to avoid interference)
        result = result.gsub(/^(\s*-\s*)\[x\]/) { "#{$1}\e[32m[x]\e[m" }
        result = result.gsub(/^(\s*-\s*)\[ \]/) { "#{$1}\e[90m[ ]\e[m" }

        # Bold **text**
        result = result.gsub(/\*\*([^*]+)\*\*/) { "\e[1m**#{$1}**\e[22m" }

        # Italic *text* (but not ** which is bold)
        result = result.gsub(/(?<!\*)\*([^*]+)\*(?!\*)/) { "\e[3m*#{$1}*\e[23m" }

        # Inline code `text`
        result = result.gsub(/`([^`]+)`/) { "\e[33m`#{$1}`\e[m" }

        # Links [text](url)
        result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "\e[4m#{$1}\e[24m(\e[2m#{$2}\e[22m)" }

        result
      end

      # --- Table rendering ---

      def table_line?(line)
        stripped = line.to_s.strip
        stripped.start_with?("|") && stripped.end_with?("|") && stripped.length > 1
      end

      def separator_line?(stripped)
        stripped.match?(/\A\|[\s\-:|]+\|\z/)
      end

      def identify_table_groups(lines)
        groups = {}
        i = 0
        while i < lines.length
          if table_line?(lines[i])
            start = i
            table_lines = []
            while i < lines.length && table_line?(lines[i])
              table_lines << lines[i]
              i += 1
            end
            group = build_table_group(table_lines)
            (start...(start + table_lines.length)).each { |j| groups[j] = group }
          else
            i += 1
          end
        end
        groups
      end

      def build_table_group(table_lines)
        return nil if table_lines.nil? || table_lines.empty?

        cells = table_lines.map { |l| parse_table_cells(l) }
        max_cols = cells.map(&:length).max
        return nil if max_cols.nil? || max_cols.zero?

        col_widths = Array.new(max_cols, 0)
        cells.each do |row|
          row.each_with_index do |cell, ci|
            w = RuVim::DisplayWidth.display_width(cell)
            col_widths[ci] = w if w > col_widths[ci]
          end
        end

        { col_widths: col_widths, max_cols: max_cols }
      end

      def parse_table_cells(line)
        stripped = line.to_s.strip
        # Remove leading and trailing |
        inner = stripped[1...-1] || ""
        inner.split("|", -1).map(&:strip)
      end

      def render_table_line(line, stripped, group)
        if separator_line?(stripped)
          render_table_separator(group)
        else
          render_table_data_row(line, group)
        end
      end

      def render_table_separator(group)
        col_widths = group[:col_widths]
        cells = col_widths.map { |w| "─" * (w + 2) }
        "├#{cells.join("┼")}┤"
      end

      def render_table_data_row(line, group)
        col_widths = group[:col_widths]
        cells = parse_table_cells(line)
        padded = cells.each_with_index.map do |cell, i|
          target = col_widths[i] || 0
          pad_cell(cell, target)
        end
        # Fill missing columns
        (cells.length...group[:max_cols]).each do |i|
          padded << " " * (col_widths[i] || 0)
        end
        "│ #{padded.join(" │ ")} │"
      end

      def pad_cell(cell, target_width)
        current = RuVim::DisplayWidth.display_width(cell)
        gap = target_width - current
        gap > 0 ? "#{cell}#{" " * gap}" : cell
      end

      # --- Table cursor mapping ---

      def table_cursor_display_col(raw_line, cursor_x, group)
        col_widths = group[:col_widths]
        cells = parse_table_cells(raw_line)

        # Map cursor_x (in raw line) to display col in formatted line
        # Raw line: "| cell1 | cell2 |"
        # Formatted: "│ cell1  │ cell2  │"

        # Walk through the raw line to find which cell cursor_x is in
        pos = 0
        raw = raw_line.to_s
        # Skip leading whitespace
        pos += 1 while pos < raw.length && raw[pos] == " "
        # Skip leading |
        pos += 1 if pos < raw.length && raw[pos] == "|"

        display_col = 2  # "│ " prefix
        cells.each_with_index do |cell, ci|
          # Skip whitespace before cell content
          pos += 1 while pos < raw.length && raw[pos] == " "

          cell_start = pos
          cell_end = cell_start + cell.length

          if cursor_x < cell_end || ci == cells.length - 1
            # Cursor is in this cell
            offset_in_cell = [cursor_x - cell_start, 0].max
            offset_in_cell = [offset_in_cell, cell.length].min
            return display_col + RuVim::DisplayWidth.display_width(cell[0...offset_in_cell])
          end

          display_col += (col_widths[ci] || 0) + 3  # " │ "
          pos = cell_end
          # Skip whitespace after cell
          pos += 1 while pos < raw.length && raw[pos] == " "
          # Skip |
          pos += 1 if pos < raw.length && raw[pos] == "|"
        end

        display_col
      end
    end
  end
end
