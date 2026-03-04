module RuVim
  module RichView
    module TableRenderer
      SEPARATOR = " | "
      SEPARATOR_WIDTH = 3

      module_function

      def delimiter_for(format)
        case format.to_s
        when "csv" then ","
        when "tsv" then "\t"
        else "\t"
        end
      end

      # Compute max display width per column from visible lines.
      # Returns an Array of column widths, or nil if single-column / empty.
      def compute_col_widths(lines, delimiter:)
        return nil if lines.nil? || lines.empty?

        rows = lines.map { |line| split_fields(line, delimiter) }
        max_cols = rows.map(&:length).max
        return nil if max_cols.nil? || max_cols <= 1

        col_widths = Array.new(max_cols, 0)
        rows.each do |fields|
          fields.each_with_index do |field, i|
            w = RuVim::DisplayWidth.display_width(field)
            col_widths[i] = w if w > col_widths[i]
          end
        end
        col_widths
      end

      # Format a single raw line using pre-computed column widths.
      def format_line(raw_line, delimiter:, col_widths:)
        fields = split_fields(raw_line, delimiter)
        padded = fields.each_with_index.map do |field, i|
          pad_field(field, col_widths[i] || 0)
        end
        (fields.length...col_widths.length).each do |i|
          padded << " " * col_widths[i]
        end
        padded.join(SEPARATOR)
      end

      # Map a character index in the raw line to the corresponding index
      # in the formatted line.  Needed for correct horizontal scrolling
      # and cursor placement in rich mode.
      def raw_to_formatted_char_index(raw_line, raw_char_index, delimiter:, col_widths:)
        fields = split_fields(raw_line, delimiter)
        pos = 0
        formatted_pos = 0
        fields.each_with_index do |field, i|
          field_end = pos + field.length
          if raw_char_index <= field_end
            offset = [raw_char_index - pos, field.length].min
            return formatted_pos + offset
          end
          pos = field_end + 1 # skip delimiter
          field_dw = RuVim::DisplayWidth.display_width(field)
          pad_chars = [(col_widths[i] || 0) - field_dw, 0].max
          formatted_pos += field.length + pad_chars + SEPARATOR.length
        end
        formatted_pos
      end

      # Map a character index in the raw line to the display column
      # in the formatted line.  Unlike raw_to_formatted_char_index (which
      # returns a character index), this returns the screen column directly,
      # which is needed for display-column-based horizontal scrolling.
      def raw_to_formatted_display_col(raw_line, raw_char_index, delimiter:, col_widths:)
        fields = split_fields(raw_line, delimiter)
        pos = 0
        display_col = 0
        fields.each_with_index do |field, i|
          field_end = pos + field.length
          if raw_char_index <= field_end
            offset_chars = [raw_char_index - pos, field.length].min
            offset_dw = RuVim::DisplayWidth.display_width(field[0...offset_chars])
            return display_col + offset_dw
          end
          display_col += (col_widths[i] || 0) + SEPARATOR_WIDTH
          pos = field_end + 1
        end
        display_col
      end

      # Compute the display column for the cursor position in a formatted line.
      def cursor_display_col(raw_line, cursor_x, visible_lines:, delimiter:)
        col_widths = compute_col_widths(visible_lines, delimiter: delimiter)
        return RuVim::TextMetrics.screen_col_for_char_index(raw_line, cursor_x) unless col_widths

        raw_to_formatted_display_col(raw_line, cursor_x, delimiter: delimiter, col_widths: col_widths)
      end

      # Render visible lines: split by delimiter, compute column widths, pad and join.
      # Returns an array of formatted strings.
      def render_visible(lines, delimiter:)
        return lines if lines.nil? || lines.empty?

        col_widths = compute_col_widths(lines, delimiter:)
        return lines unless col_widths

        lines.map { |line| format_line(line, delimiter:, col_widths:) }
      end

      # Split a line into fields respecting the delimiter.
      # For CSV, handles quoted fields minimally.
      def split_fields(line, delimiter)
        if delimiter == ","
          parse_csv_fields(line)
        else
          line.to_s.split(delimiter, -1)
        end
      end

      # Minimal CSV field parser: handles double-quoted fields with embedded
      # commas and escaped quotes ("").
      def parse_csv_fields(line)
        fields = []
        s = line.to_s
        pos = 0

        while pos <= s.length
          if pos < s.length && s[pos] == '"'
            # Quoted field
            pos += 1
            field = +""
            while pos < s.length
              if s[pos] == '"'
                if pos + 1 < s.length && s[pos + 1] == '"'
                  field << '"'
                  pos += 2
                else
                  pos += 1
                  break
                end
              else
                field << s[pos]
                pos += 1
              end
            end
            fields << field
            # Skip comma after quoted field
            pos += 1 if pos < s.length && s[pos] == ','
          else
            # Unquoted field
            comma_idx = s.index(',', pos)
            if comma_idx
              fields << s[pos...comma_idx]
              pos = comma_idx + 1
              # Trailing comma means empty last field
              fields << "" if pos == s.length
            else
              fields << s[pos..]
              break
            end
          end
        end

        fields
      end

      # Pad a field to a target display width using spaces.
      def pad_field(field, target_width)
        current = RuVim::DisplayWidth.display_width(field)
        gap = target_width - current
        gap > 0 ? "#{field}#{' ' * gap}" : field
      end
    end
  end
end
