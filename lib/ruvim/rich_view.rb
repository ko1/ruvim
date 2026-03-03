require_relative "rich_view/table_renderer"

module RuVim
  module RichView
    @renderers = {}

    module_function

    def register(filetype, renderer)
      @renderers[filetype.to_s] = renderer
    end

    def renderer_for(filetype)
      @renderers[filetype.to_s]
    end

    def registered_filetypes
      @renderers.keys
    end

    # Detect format from filetype or buffer content.
    # Returns a filetype string ("tsv", "csv") or nil.
    def detect_format(buffer)
      ft = buffer.options["filetype"].to_s
      return ft if @renderers.key?(ft)

      # Auto-detect from content: count tabs vs commas in first few lines
      sample = (0...[buffer.line_count, 20].min).map { |i| buffer.line_at(i) }
      tabs = sample.sum { |l| l.count("\t") }
      commas = sample.sum { |l| l.count(",") }

      if tabs > 0 && tabs >= commas
        "tsv"
      elsif commas > 0
        "csv"
      end
    end

    # Open a Rich View buffer for the current buffer.
    # Returns the new rich view buffer.
    def open!(editor, format: nil)
      source_buffer = editor.current_buffer
      format ||= detect_format(source_buffer)
      raise RuVim::CommandError, "Cannot detect format for rich view" unless format

      renderer = @renderers[format]
      raise RuVim::CommandError, "No renderer for format: #{format}" unless renderer

      lines = (0...source_buffer.line_count).map { |i| source_buffer.line_at(i) }

      buffer = editor.add_virtual_buffer(
        kind: :rich_view,
        name: "[Rich View: #{source_buffer.display_name}]",
        lines: lines,
        readonly: true,
        modifiable: false
      )
      buffer.options["wrap"] = false
      buffer.options["__rich_view__"] = { format: format, delimiter: renderer.delimiter_for(format) }

      editor.switch_to_buffer(buffer.id)
      editor.echo("[Rich View: #{format}]")
      buffer
    end

    # Check if a buffer is a Rich View buffer.
    def active?(buffer)
      buffer.kind == :rich_view && !!buffer.options["__rich_view__"]
    end

    # Render visible lines through the appropriate renderer.
    # Takes raw lines from buffer, returns formatted lines for display.
    def render_visible_lines(buffer, lines)
      meta = buffer.options["__rich_view__"]
      return lines unless meta

      format = meta[:format]
      renderer = @renderers[format]
      return lines unless renderer

      delimiter = meta[:delimiter]
      renderer.render_visible(lines, delimiter: delimiter)
    end

    # Toggle: if current buffer is rich view, close it; otherwise open one.
    def toggle!(editor, format: nil)
      if active?(editor.current_buffer)
        close!(editor)
      else
        open!(editor, format: format)
      end
    end

    # Close the rich view buffer and return to the previous buffer.
    def close!(editor)
      buffer = editor.current_buffer
      return unless active?(buffer)

      editor.delete_buffer(buffer.id)
    end

    # Register built-in renderers
    register("tsv", TableRenderer)
    register("csv", TableRenderer)
  end
end
