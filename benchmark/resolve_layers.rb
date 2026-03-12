# frozen_string_literal: true

# Benchmark for KeymapManager#resolve_with_context
# Usage: ruby -Ilib benchmark/resolve_layers.rb

require "benchmark"
require "ruvim"

km = RuVim::KeymapManager.new
editor = RuVim::Editor.new
editor.ensure_bootstrap_buffer!

# Simulate realistic keymap size (~150 bindings)
bindings = %w[
  x dd yy p P u o O A I J gj gk gg G w b e W B E
  0 $ ^ f F t T ; , / ? n N * # % zz zt zb
  H M L r R ~ . q @ m
]
bindings.each { |seq| km.bind(:normal, seq, "cmd.#{seq}") }

# Multi-char bindings
%w[ci ca di da yi ya vi va gU gu g~ gc].each do |prefix|
  %w[w W b B e E ( ) { } [ ] < > " ' ` t].each do |obj|
    km.bind(:normal, "#{prefix}#{obj}", "cmd.#{prefix}#{obj}")
  end
end

tokens_list = [
  ["x"],
  %w[d d],
  ["g"],
  %w[g g],
  %w[c i w],
  ["z"],
]

n = 50_000
Benchmark.bm(25) do |bm|
  tokens_list.each do |tokens|
    label = tokens.join("")
    bm.report("resolve '#{label}'") do
      n.times { km.resolve_with_context(:normal, tokens, editor: editor) }
    end
  end
end
