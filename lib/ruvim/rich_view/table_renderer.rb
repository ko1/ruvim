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

      # Render visible lines: split by delimiter, compute column widths, pad and join.
      # Returns an array of formatted strings.
      def render_visible(lines, delimiter:)
        return lines if lines.nil? || lines.empty?

        rows = lines.map { |line| split_fields(line, delimiter) }

        # If all rows have only 1 column, return lines as-is
        max_cols = rows.map(&:length).max
        return lines if max_cols.nil? || max_cols <= 1

        # Compute max display width per column from visible rows only
        col_widths = Array.new(max_cols, 0)
        rows.each do |fields|
          fields.each_with_index do |field, i|
            w = RuVim::DisplayWidth.display_width(field)
            col_widths[i] = w if w > col_widths[i]
          end
        end

        rows.map do |fields|
          padded = fields.each_with_index.map do |field, i|
            pad_field(field, col_widths[i])
          end
          # Pad missing columns
          (fields.length...max_cols).each do |i|
            padded << " " * col_widths[i]
          end
          padded.join(SEPARATOR)
        end
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
