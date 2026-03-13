# frozen_string_literal: true

module RuVim
  module RichView
    module ImageRenderer
      module_function

      def auto_open?
        true
      end

      def open_view!(editor)
        buffer = editor.current_buffer
        path = buffer.path
        unless path && !path.to_s.empty?
          editor.echo_error("No file path for image view")
          return
        end

        abs_path = File.expand_path(path)
        name = File.basename(path)
        old_buffer_id = buffer.id

        buf = editor.add_virtual_buffer(
          kind: :image_view,
          name: "[Image: #{name}]",
          lines: ["![#{name}](#{abs_path})"],
          readonly: true,
          modifiable: false
        )
        editor.switch_to_buffer(buf.id)
        # Remove the binary data buffer to free memory
        editor.delete_buffer(old_buffer_id)
        RichView.bind_close_keys(editor, buf.id)
        editor.enter_rich_mode(format: :markdown, delimiter: nil)
        editor.echo("[Image: #{name}]")
      end
    end
  end
end
