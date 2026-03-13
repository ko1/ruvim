#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare Ruby vs C extension for DisplayWidth and TextMetrics
#
# Usage: ruby benchmark/cext_compare.rb

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ruvim/display_width"
require "ruvim/text_metrics"
require "ruvim/ruvim_ext"

# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------
ASCII_LINE = '  def foo(bar, baz) = bar + baz # comment with some padding text here!!!' * 2
CJK_LINE   = "日本語テキスト　漢字カタカナ　テスト用の行　全角文字を含む行" * 2
MIXED_LINE = "Hello 世界! def foo(x) = x + 1  # コメント 🚀 emoji test"
EMOJI_LINE = "🎉🔥💡🚀✨🎊🌟💎🏆🎯" * 5
TAB_LINE   = "\t\tif (x > 0) {\n\t\t\treturn x;\n\t\t}"

LINES = {
  "ASCII (140c)" => ASCII_LINE,
  "CJK (56c)"    => CJK_LINE,
  "Mixed"        => MIXED_LINE,
  "Emoji (50c)"  => EMOJI_LINE,
  "Tabs"         => TAB_LINE,
}.freeze

SCREEN_WIDTH = 120
SCREEN_ROWS  = 50

N = 10_000
N_RENDER = 2_000

puts "DisplayWidth + TextMetrics: Ruby vs C Extension"
puts "=" * 70
puts "Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Iterations: #{N} (per-call), #{N_RENDER} (render)"
puts

# ===================================================================
# Correctness checks
# ===================================================================
puts "--- Correctness check ---"
ok = true

# DisplayWidth
LINES.each do |label, line|
  rw = RuVim::DisplayWidth.display_width(line)
  cw = RuVim::DisplayWidthExt.display_width(line)
  status = rw == cw ? "OK" : "MISMATCH"
  puts "  display_width %-15s Ruby=%3d  C=%3d  %s" % [label, rw, cw, status]
  ok = false if rw != cw
end

# clip_cells_for_width
LINES.each do |label, line|
  r_cells, r_col = RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH)
  c_cells, c_col = RuVim::TextMetricsExt.clip_cells_for_width(line, SCREEN_WIDTH)
  col_ok = r_col == c_col
  count_ok = r_cells.size == c_cells.size
  glyphs_ok = r_cells.map(&:glyph) == c_cells.map(&:glyph)
  src_ok = r_cells.map(&:source_col) == c_cells.map(&:source_col)
  widths_ok = r_cells.map(&:display_width) == c_cells.map(&:display_width)
  all_ok = col_ok && count_ok && glyphs_ok && src_ok && widths_ok
  status = all_ok ? "OK" : "MISMATCH"
  unless all_ok
    puts "  clip_cells %-15s %s (col:%s cnt:%s glyph:%s src:%s w:%s)" %
      [label, status, col_ok, count_ok, glyphs_ok, src_ok, widths_ok]
    ok = false
  else
    puts "  clip_cells %-15s %s (cells=%d, col=%d)" % [label, status, r_cells.size, r_col]
  end
end

# char_index_for_screen_col
LINES.each do |label, line|
  target = RuVim::DisplayWidth.display_width(line) / 2
  ri = RuVim::TextMetrics.char_index_for_screen_col(line, target)
  ci = RuVim::TextMetricsExt.char_index_for_screen_col(line, target)
  status = ri == ci ? "OK" : "MISMATCH"
  puts "  char_idx_for_sc %-11s Ruby=%3d  C=%3d  %s" % [label, ri, ci, status]
  ok = false if ri != ci
end

unless ok
  puts "\n*** CORRECTNESS FAILURES — fix C extension before benchmarking ***"
  exit 1
end
puts "  All checks passed!"
puts

# ===================================================================
# 1. DisplayWidth benchmarks
# ===================================================================
puts "--- 1. cell_width ---"
test_chars = { "ASCII 'A'" => "A", "CJK '漢'" => "漢", "Emoji '🚀'" => "🚀" }
Benchmark.bm(25) do |x|
  test_chars.each do |label, ch|
    x.report("Ruby  #{label}") { N.times { RuVim::DisplayWidth.cell_width(ch) } }
    x.report("C     #{label}") { N.times { RuVim::DisplayWidthExt.cell_width(ch) } }
  end
end
puts

puts "--- 2. display_width ---"
Benchmark.bm(25) do |x|
  LINES.each do |label, line|
    x.report("Ruby  #{label}") { N.times { RuVim::DisplayWidth.display_width(line) } }
    x.report("C     #{label}") { N.times { RuVim::DisplayWidthExt.display_width(line) } }
  end
end
puts

# ===================================================================
# 2. TextMetrics benchmarks
# ===================================================================
puts "--- 3. clip_cells_for_width (Ruby TM vs C TM) ---"
Benchmark.bm(25) do |x|
  LINES.each do |label, line|
    x.report("Ruby  #{label}") { N_RENDER.times { RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH) } }
    x.report("C     #{label}") { N_RENDER.times { RuVim::TextMetricsExt.clip_cells_for_width(line, SCREEN_WIDTH) } }
  end
end
puts

puts "--- 4. char_index_for_screen_col (Ruby TM vs C TM) ---"
Benchmark.bm(25) do |x|
  LINES.each do |label, line|
    target = RuVim::DisplayWidth.display_width(line) / 2
    x.report("Ruby  #{label}") { N.times { RuVim::TextMetrics.char_index_for_screen_col(line, target) } }
    x.report("C     #{label}") { N.times { RuVim::TextMetricsExt.char_index_for_screen_col(line, target) } }
  end
end
puts

# ===================================================================
# 3. Full screen simulation
# ===================================================================
puts "--- 5. Full screen render sim (#{SCREEN_ROWS} lines × #{SCREEN_WIDTH} cols) ---"
lines_80 = [ASCII_LINE, CJK_LINE, MIXED_LINE, ASCII_LINE, CJK_LINE].freeze
screen_lines = Array.new(SCREEN_ROWS) { |i| lines_80[i % lines_80.size] }

Benchmark.bm(25) do |x|
  x.report("Ruby TM + Ruby DW") do
    N_RENDER.times do
      screen_lines.each { |line| RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH) }
    end
  end

  x.report("C TM (full C)") do
    N_RENDER.times do
      screen_lines.each { |line| RuVim::TextMetricsExt.clip_cells_for_width(line, SCREEN_WIDTH) }
    end
  end
end
puts

puts "=" * 70
puts "Done."
