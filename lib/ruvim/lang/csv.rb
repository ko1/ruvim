# frozen_string_literal: true

module RuVim
  module Lang
    class Csv < Base
      # Detect CSV from buffer content: commas > 0 (and not TSV)
      def detect?(buffer)
      sample = (0...[buffer.line_count, 20].min).map { |i| buffer.line_at(i) }
      commas = sample.sum { |l| l.count(",") }
      commas > 0
      end
    end
  end

  RichView.register(:csv, RichView::TableRenderer, detector: ->(buf) { Lang::Csv.new.detect?(buf) })
end
