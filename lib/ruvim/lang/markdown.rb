# frozen_string_literal: true

module RuVim
  module Lang
    class Markdown < Base
      # --- Regex patterns ---

      HEADING_RE        = /\A(\s*)(\#{1,6})\s/
      FENCE_RE          = /\A(`{3,}|~{3,})/
      HR_RE             = /\A(\-{3,}|\*{3,}|_{3,})\s*\z/
      BLOCK_QUOTE_RE    = /\A\s*> /
      TABLE_LINE_RE     = /\A\s*\|.*\|\s*\z/
      TABLE_SEPARATOR_RE = /\A\|[\s\-:|]+\|\z/

      BOLD_RE           = /\*\*([^*]+)\*\*/
      ITALIC_RE         = /(?<!\*)\*([^*]+)\*(?!\*)/
      INLINE_CODE_RE    = /`([^`]+)`/
      LINK_RE           = /\[([^\]]+)\]\(([^)]+)\)/
      IMAGE_RE              = /\A\s*!?\[([^\]]*)\]\(([^)]+)\)\s*\z/
      CHECKBOX_CHECKED_RE   = /^(\s*-\s*)\[x\]/
      CHECKBOX_UNCHECKED_RE = /^(\s*-\s*)\[ \]/

      # --- Heading styles (for color_columns) ---

      HEADING_COLORS = {
      1 => "\e[1;33m",   # bold yellow
      2 => "\e[1;36m",   # bold cyan
      3 => "\e[1;32m",   # bold green
      4 => "\e[1;35m",   # bold magenta
      5 => "\e[1;34m",   # bold blue
      6 => "\e[1;90m"    # bold dim
      }.freeze

      # --- FenceState: tracks code fence open/close across lines ---

      class FenceState
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

      # --- Detection helpers ---

      def heading_level(line)
        m = line.to_s.match(HEADING_RE)
        m ? m[2].length : 0
      end

      def fence_line?(stripped)
        stripped.to_s.match?(FENCE_RE)
      end

      def horizontal_rule?(stripped)
        stripped.to_s.match?(HR_RE)
      end

      def block_quote?(line)
        line.to_s.match?(BLOCK_QUOTE_RE)
      end

      def table_line?(line)
        stripped = line.to_s.strip
        stripped.start_with?("|") && stripped.end_with?("|") && stripped.length > 1
      end

      def parse_image(line)
        m = line.to_s.match(IMAGE_RE)
        m ? [m[1], m[2]] : nil
      end

      def table_separator?(stripped)
        stripped.to_s.match?(TABLE_SEPARATOR_RE)
      end

      def parse_table_cells(line)
        stripped = line.to_s.strip
        inner = stripped[1...-1] || ""
        inner.split("|", -1).map(&:strip)
      end

      # --- Syntax highlight: color_columns ---

      def color_columns(text)
        cols = {}
        return cols if text.nil? || text.empty?

        stripped = text.strip

        # Fence line: entire line dim
        if fence_line?(stripped)
          fill_line(cols, text, "\e[90m")
          return cols
        end

        # HR: entire line dim
        if horizontal_rule?(stripped)
          fill_line(cols, text, "\e[90m")
          return cols
        end

        # Heading: entire line colored by level
        if (m = text.match(HEADING_RE))
          level = m[2].length
          color = HEADING_COLORS[level] || HEADING_COLORS[6]
          fill_line(cols, text, color)
          return cols
        end

        # Block quote marker
        if (m = text.match(/\A(\s*>)/))
          apply_regex(cols, text, /\A\s*>/, "\e[36m")
        end

        # Inline elements
        apply_regex(cols, text, CHECKBOX_CHECKED_RE, "\e[32m")
        apply_regex(cols, text, CHECKBOX_UNCHECKED_RE, "\e[90m")
        apply_regex(cols, text, BOLD_RE, "\e[1m")
        apply_regex(cols, text, ITALIC_RE, "\e[3m")
        apply_regex(cols, text, INLINE_CODE_RE, "\e[33m")
        apply_regex(cols, text, LINK_RE, "\e[4m")

        cols
      end


      # Extract the path from a markdown link [text](path) at cursor position.
      # Returns the path string or nil if cursor is not on a link.
      def self.link_path_at(line, cursor_x)
        return nil if line.nil? || line.empty?

        line.scan(LINK_RE) do
          m = Regexp.last_match
          if cursor_x >= m.begin(0) && cursor_x < m.end(0)
            return m[2]
          end
        end
        nil
      end

      def self.register_filetype_bindings(cmd_registry, keymaps, _filetype)
        cmd_registry.register("file.goto_markdown_link",
          call: method(:goto_link),
          desc: "Open markdown link under cursor") unless cmd_registry.registered?("file.goto_markdown_link")
        keymaps.bind_filetype("markdown", "gf", "file.goto_markdown_link")
      end

      # gf command handler for markdown filetype.
      # Tries markdown link first, falls back to default gf.
      def self.goto_link(ctx, **)
        line = ctx.buffer.line_at(ctx.window.cursor_y)
        token = link_path_at(line, ctx.window.cursor_x)
        if token
          gc = GlobalCommands.instance
          target = gc.send(:parse_gf_target, token)
          path = gc.send(:resolve_gf_path, ctx, target[:path])
          if path
            if ctx.buffer.modified? && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
              unless gc.send(:maybe_autowrite_before_switch, ctx)
                ctx.editor.echo_error("Unsaved changes (set hidden or :w)")
                return
              end
            end
            ctx.editor.open_path(path)
            gc.send(:move_cursor_to_gf_line, ctx, target[:line], target[:col]) if target[:line]
            return
          end
        end
        GlobalCommands.instance.file_goto_under_cursor(ctx)
      end

      def fill_line(cols, text, color)
        text.length.times { |i| cols[i] = color }
      end
      private :fill_line
    end
  end
end
