# frozen_string_literal: true

module RuVim
  module Lang
    class Tsv < Base
      # Detect TSV from buffer content: tabs >= commas and tabs > 0
      def self.detect?(buffer)
      sample = (0...[buffer.line_count, 20].min).map { |i| buffer.line_at(i) }
      tabs = sample.sum { |l| l.count("\t") }
      commas = sample.sum { |l| l.count(",") }
      tabs > 0 && tabs >= commas
      end
    end
  end

  RichView.register(:tsv, RichView::TableRenderer, detector: Lang::Tsv.method(:detect?))
end
