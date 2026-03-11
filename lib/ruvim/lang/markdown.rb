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

      def self.heading_level(line)
        m = line.to_s.match(HEADING_RE)
        m ? m[2].length : 0
      end

      def self.fence_line?(stripped)
        stripped.to_s.match?(FENCE_RE)
      end

      def self.horizontal_rule?(stripped)
        stripped.to_s.match?(HR_RE)
      end

      def self.block_quote?(line)
        line.to_s.match?(BLOCK_QUOTE_RE)
      end

      def self.table_line?(line)
        stripped = line.to_s.strip
        stripped.start_with?("|") && stripped.end_with?("|") && stripped.length > 1
      end

      def self.table_separator?(stripped)
        stripped.to_s.match?(TABLE_SEPARATOR_RE)
      end

      def self.parse_table_cells(line)
        stripped = line.to_s.strip
        inner = stripped[1...-1] || ""
        inner.split("|", -1).map(&:strip)
      end

      # --- Syntax highlight: color_columns ---

      def self.color_columns(text)
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


      def self.fill_line(cols, text, color)
        text.length.times { |i| cols[i] = color }
      end
      private_class_method :fill_line
    end
  end
end
