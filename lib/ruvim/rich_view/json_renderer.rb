# frozen_string_literal: true

require "json"

module RuVim
  module RichView
    module JsonRenderer
      module_function

      # Signal that this renderer creates a virtual buffer
      # instead of entering rich mode on the same buffer.
      def open_view!(editor)
        buffer = editor.current_buffer
        window = editor.current_window
        text = buffer.lines.join("\n")

        begin
          parsed = JSON.parse(text)
        rescue JSON::ParserError => e
          editor.echo_error("JSON parse error: #{e.message}")
          return
        end

        # Compute cursor's significant char offset before formatting
        cursor_offset = char_offset_for(buffer.lines, window.cursor_y, window.cursor_x)
        sig_count = significant_char_count(text, cursor_offset + 1)

        formatted = JSON.pretty_generate(parsed)
        lines = formatted.lines(chomp: true)

        target_line = line_for_significant_count(formatted, sig_count)

        buf = editor.add_virtual_buffer(
          kind: :json_formatted,
          name: "[JSON Formatted]",
          lines: lines,
          filetype: "json",
          readonly: true,
          modifiable: false
        )
        editor.switch_to_buffer(buf.id)
        window.cursor_y = [target_line, lines.length - 1].min
        window.cursor_x = 0
        editor.echo("[JSON Formatted] #{lines.length} lines")
      end

      # Count significant (non-whitespace-outside-strings) characters
      # in text[0...byte_offset].
      def significant_char_count(text, byte_offset)
        in_string = false
        escape = false
        count = 0
        text.each_char.with_index do |ch, i|
          break if i >= byte_offset
          if in_string
            if escape
              escape = false
            elsif ch == "\\"
              escape = true
            elsif ch == '"'
              in_string = false
            end
            count += 1
          else
            case ch
            when '"'
              in_string = true
              count += 1
            when " ", "\n", "\r", "\t"
              # skip whitespace outside strings
            else
              count += 1
            end
          end
        end
        count
      end

      # Find the line number in text where the N-th significant character falls.
      def line_for_significant_count(text, target_count)
        return 0 if target_count <= 0

        in_string = false
        escape = false
        count = 0
        line = 0
        text.each_char do |ch|
          if ch == "\n" && !in_string
            line += 1
            next
          end
          if in_string
            if escape
              escape = false
            elsif ch == "\\"
              escape = true
            elsif ch == '"'
              in_string = false
            end
            count += 1
          else
            case ch
            when '"'
              in_string = true
              count += 1
            when " ", "\r", "\t"
              # skip
            else
              count += 1
            end
          end
          return line if count >= target_count
        end
        line
      end

      # Compute character offset in joined text from cursor row/col.
      def char_offset_for(lines, row, col)
        offset = 0
        lines.each_with_index do |line, i|
          if i == row
            return offset + [col, line.length].min
          end
          offset += line.length + 1 # +1 for "\n"
        end
        offset
      end
    end
  end
end
