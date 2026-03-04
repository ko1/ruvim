require_relative "rich_view/table_renderer"
require_relative "rich_view/markdown_renderer"

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

    # Enter rich mode on the current buffer (same buffer, no virtual buffer).
    def open!(editor, format: nil)
      buffer = editor.current_buffer
      format ||= detect_format(buffer)
      raise RuVim::CommandError, "Cannot detect format for rich view" unless format

      renderer = @renderers[format]
      raise RuVim::CommandError, "No renderer for format: #{format}" unless renderer

      delimiter = renderer.delimiter_for(format)
      editor.enter_rich_mode(format: format, delimiter: delimiter)
      editor.echo("[Rich: #{format}]")
    end

    # Check if rich view rendering is active (persists during command-line mode).
    def active?(editor)
      !!editor.rich_state
    end

    # Render visible lines through the appropriate renderer.
    # Takes raw lines from buffer, returns formatted lines for display.
    def render_visible_lines(editor, lines, context: {})
      state = editor.rich_state
      return lines unless state

      format = state[:format]
      renderer = @renderers[format]
      return lines unless renderer

      delimiter = state[:delimiter]
      if renderer.respond_to?(:needs_pre_context?) && renderer.needs_pre_context?
        renderer.render_visible(lines, delimiter: delimiter, context: context)
      else
        renderer.render_visible(lines, delimiter: delimiter)
      end
    end

    # Toggle: if in rich mode, exit; otherwise enter.
    def toggle!(editor, format: nil)
      if active?(editor)
        close!(editor)
      else
        open!(editor, format: format)
      end
    end

    # Exit rich mode and return to normal mode.
    def close!(editor)
      return unless active?(editor)

      editor.exit_rich_mode
    end

    # Register built-in renderers
    register("tsv", TableRenderer)
    register("csv", TableRenderer)
    register("markdown", MarkdownRenderer)
  end
end
