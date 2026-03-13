#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for C-extension candidate hotspots in RuVim
#
# Usage: ruby benchmark/hotspots.rb

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruvim/display_width"
require "ruvim/text_metrics"
require "ruvim/lang/registry"
require "ruvim/lang/base"
require "ruvim/lang/ruby"
require "ruvim/lang/c"
require "ruvim/lang/markdown"
require "ruvim/lang/json"
require "ruvim/lang/javascript"

# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------
ASCII_LINE   = '  def foo(bar, baz) = bar + baz # comment with some padding text here!!!' * 2
CJK_LINE     = "日本語テキスト　漢字カタカナ　テスト用の行　全角文字を含む行" * 2
MIXED_LINE   = "Hello 世界! def foo(x) = x + 1  # コメント 🚀 emoji test"
EMOJI_LINE   = "🎉🔥💡🚀✨🎊🌟💎🏆🎯" * 5
TAB_LINE     = "\t\tif (x > 0) {\n\t\t\treturn x;\n\t\t}"

RUBY_LINE    = '  def initialize(name, value: nil) # keyword args'
C_LINE       = '  int *ptr = malloc(sizeof(struct node)); /* alloc */'
MD_LINE      = '## Heading with **bold** and `code` and [link](url)'
JSON_LINE    = '  {"key": "value", "number": 42, "bool": true, "null": null}'
JS_LINE      = '  const fn = async (x) => { return await fetch(url); };'

LINES_80COL  = [ASCII_LINE, CJK_LINE, MIXED_LINE, RUBY_LINE, C_LINE].freeze
SCREEN_WIDTH = 120
SCREEN_ROWS  = 50

N_ITER = 10_000
N_RENDER = 2_000

puts "RuVim Hotspot Benchmark"
puts "=" * 60
puts "Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Iterations: #{N_ITER} (width), #{N_RENDER} (render)"
puts

# ---------------------------------------------------------------------------
# 1. DisplayWidth.cell_width — per-character width lookup
# ---------------------------------------------------------------------------
puts "--- 1. DisplayWidth.cell_width ---"
chars = {
  "ASCII 'A'"   => "A",
  "CJK '漢'"    => "漢",
  "Emoji '🚀'"  => "🚀",
  "Combining"   => "\u0301",   # combining acute
  "Tab"         => "\t",
}
Benchmark.bm(20) do |x|
  chars.each do |label, ch|
    x.report(label) { N_ITER.times { RuVim::DisplayWidth.cell_width(ch) } }
  end
end
puts

# ---------------------------------------------------------------------------
# 2. DisplayWidth.display_width — whole-line width
# ---------------------------------------------------------------------------
puts "--- 2. DisplayWidth.display_width ---"
lines = {
  "ASCII (140c)"  => ASCII_LINE,
  "CJK (56c)"     => CJK_LINE,
  "Mixed"         => MIXED_LINE,
  "Emoji (50c)"   => EMOJI_LINE,
  "Tabs"          => TAB_LINE,
}
Benchmark.bm(20) do |x|
  lines.each do |label, line|
    x.report(label) { N_ITER.times { RuVim::DisplayWidth.display_width(line) } }
  end
end
puts

# ---------------------------------------------------------------------------
# 3. TextMetrics.clip_cells_for_width — cell array construction
# ---------------------------------------------------------------------------
puts "--- 3. TextMetrics.clip_cells_for_width ---"
Benchmark.bm(20) do |x|
  lines.each do |label, line|
    x.report(label) { N_RENDER.times { RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH) } }
  end
end
puts

# ---------------------------------------------------------------------------
# 4. TextMetrics.char_index_for_screen_col — cursor positioning
# ---------------------------------------------------------------------------
puts "--- 4. TextMetrics.char_index_for_screen_col ---"
Benchmark.bm(20) do |x|
  lines.each do |label, line|
    target = RuVim::DisplayWidth.display_width(line) / 2
    x.report(label) { N_ITER.times { RuVim::TextMetrics.char_index_for_screen_col(line, target) } }
  end
end
puts

# ---------------------------------------------------------------------------
# 5. Lang::*.color_columns — syntax highlighting
# ---------------------------------------------------------------------------
puts "--- 5. Lang color_columns ---"
highlight_cases = {
  "Ruby"       => ["ruby", RUBY_LINE],
  "C"          => ["c", C_LINE],
  "Markdown"   => ["markdown", MD_LINE],
  "JSON"       => ["json", JSON_LINE],
  "JavaScript" => ["javascript", JS_LINE],
}
Benchmark.bm(20) do |x|
  highlight_cases.each do |label, (ft, line)|
    mod = RuVim::Lang::Registry.resolve_module(ft)
    x.report(label) { N_RENDER.times { mod.color_columns(line) } }
  end
end
puts

# ---------------------------------------------------------------------------
# 6. Simulated full-screen render pass (clip + highlight per line)
# ---------------------------------------------------------------------------
puts "--- 6. Simulated screen render (#{SCREEN_ROWS} lines × #{SCREEN_WIDTH} cols) ---"
screen_lines = Array.new(SCREEN_ROWS) { |i| LINES_80COL[i % LINES_80COL.size] }
Benchmark.bm(20) do |x|
  x.report("clip_cells only") do
    N_RENDER.times do
      screen_lines.each { |line| RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH) }
    end
  end
  lang_mods = %w[ruby c markdown json javascript].map { |ft| RuVim::Lang::Registry.resolve_module(ft) }
  x.report("highlight only") do
    N_RENDER.times do
      screen_lines.each_with_index do |line, i|
        lang_mods[i % 5].color_columns(line)
      end
    end
  end
  x.report("clip + highlight") do
    N_RENDER.times do
      screen_lines.each_with_index do |line, i|
        RuVim::TextMetrics.clip_cells_for_width(line, SCREEN_WIDTH)
        lang_mods[i % 5].color_columns(line)
      end
    end
  end
end
puts

# ---------------------------------------------------------------------------
# 7. DisplayWidth.expand_tabs
# ---------------------------------------------------------------------------
puts "--- 7. DisplayWidth.expand_tabs ---"
tab_lines = {
  "2 tabs"   => "\t\tcode here",
  "mixed"    => "abc\tdef\tghi\tjkl",
  "heavy"    => "\t" * 20 + "end",
}
Benchmark.bm(20) do |x|
  tab_lines.each do |label, line|
    x.report(label) { N_ITER.times { RuVim::DisplayWidth.expand_tabs(line) } }
  end
end
puts

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "=" * 60
puts "Done. Compare user+sys times to identify C-extension priorities."
