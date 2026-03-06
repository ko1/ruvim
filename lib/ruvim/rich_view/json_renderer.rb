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
        text = buffer.lines.join("\n")

        begin
          parsed = JSON.parse(text)
        rescue JSON::ParserError => e
          editor.echo_error("JSON parse error: #{e.message}")
          return
        end

        formatted = JSON.pretty_generate(parsed)
        lines = formatted.lines(chomp: true)

        buf = editor.add_virtual_buffer(
          kind: :json_formatted,
          name: "[JSON Formatted]",
          lines: lines,
          filetype: "json",
          readonly: true,
          modifiable: false
        )
        editor.switch_to_buffer(buf.id)
        editor.echo("[JSON Formatted] #{lines.length} lines")
      end
    end
  end
end
