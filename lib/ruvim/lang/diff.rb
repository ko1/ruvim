# frozen_string_literal: true

module RuVim
  module Lang
    class Diff < Base
      ADD_COLOR    = "\e[32m"  # green
      DELETE_COLOR = "\e[31m"  # red
      HUNK_COLOR   = "\e[36m"  # cyan
      HEADER_COLOR = "\e[1m"   # bold
      META_COLOR   = "\e[33m"  # yellow

      def color_columns(text)
      cols = {}
      color = line_color(text)
      return cols unless color

      text.length.times { |i| cols[i] = color }
      cols
      end

      def line_color(text)
      return nil if text.empty?

      case text
      when /\A@@/
        HUNK_COLOR
      when /\Adiff /
        HEADER_COLOR
      when /\A\+/
        ADD_COLOR
      when /\A-/
        DELETE_COLOR
      when /\Aindex /, /\Anew file/, /\Adeleted file/, /\Arename/, /\Asimilarity/
        META_COLOR
      end
      end
    end
  end
end
