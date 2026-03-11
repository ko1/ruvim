# frozen_string_literal: true

require_relative "rich_view/table_renderer"
require_relative "rich_view/markdown_renderer"
require_relative "rich_view/json_renderer"
require_relative "rich_view/jsonl_renderer"

module RuVim
  module RichView
    @renderers = {}
    @detectors = []

    module_function

    def register(filetype, renderer, detector: nil)
      @renderers[filetype.to_sym] = renderer
      @detectors << { filetype: filetype.to_sym, detector: detector } if detector
    end

    def renderer_for(filetype)
      @renderers[filetype.to_sym]
    end

    def registered_filetypes
      @renderers.keys
    end

    # Detect format from filetype or buffer content.
    # Returns a filetype symbol (:tsv, :csv, :markdown) or nil.
    def detect_format(buffer)
      raw = buffer.options["filetype"]
      if raw && !raw.to_s.empty?
        ft = raw.to_sym
        return ft if @renderers.key?(ft)
      end

      # Ask registered detectors
      @detectors.each do |entry|
        return entry[:filetype] if entry[:detector].call(buffer)
      end

      nil
    end

    # Enter rich mode on the current buffer (same buffer, no virtual buffer).
    def open!(editor, format: nil)
      buffer = editor.current_buffer
      format = format ? format.to_sym : detect_format(buffer)
      raise RuVim::CommandError, "Cannot detect format for rich view" unless format

      renderer = @renderers[format]
      raise RuVim::CommandError, "No renderer for format: #{format}" unless renderer

      if renderer.respond_to?(:open_view!)
        renderer.open_view!(editor)
        return
      end

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

    # Bind Esc and C-c to close a virtual buffer created by a renderer.
    def bind_close_keys(editor, buffer_id)
      km = editor.keymap_manager
      return unless km

      km.bind_buffer(buffer_id, "\e", "rich.close_buffer")
      km.bind_buffer(buffer_id, "<C-c>", "rich.close_buffer")
    end

    register(:markdown, MarkdownRenderer)
    register(:json, JsonRenderer)
    register(:jsonl, JsonlRenderer)
  end
end

# Load format modules that register with RichView.
require_relative "lang/tsv"
require_relative "lang/csv"
