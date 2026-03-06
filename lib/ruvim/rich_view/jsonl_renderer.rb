# frozen_string_literal: true

require "json"

module RuVim
  module RichView
    module JsonlRenderer
      module_function

      SEPARATOR = "---"

      def open_view!(editor)
        buffer = editor.current_buffer
        window = editor.current_window
        cursor_row = window.cursor_y

        output_lines = []
        # Map from source line index to starting line in output
        line_map = {}

        buffer.lines.each_with_index do |raw_line, idx|
          line = raw_line.to_s.strip
          next if line.empty?

          output_lines << SEPARATOR unless output_lines.empty?
          line_map[idx] = output_lines.length

          begin
            parsed = JSON.parse(line)
            formatted = JSON.pretty_generate(parsed)
            formatted.each_line(chomp: true) { |l| output_lines << l }
          rescue JSON::ParserError
            output_lines << "// PARSE ERROR: #{raw_line}"
          end
        end

        output_lines << "" if output_lines.empty?

        target_line = line_map[cursor_row] || 0

        buf = editor.add_virtual_buffer(
          kind: :jsonl_formatted,
          name: "[JSONL Formatted]",
          lines: output_lines,
          filetype: "json",
          readonly: true,
          modifiable: false
        )
        editor.switch_to_buffer(buf.id)
        RichView.bind_close_keys(editor, buf.id)
        window.cursor_y = [target_line, output_lines.length - 1].min
        window.cursor_x = 0
        editor.echo("[JSONL Formatted] #{output_lines.length} lines")
      end
    end
  end
end
