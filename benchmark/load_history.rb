# frozen_string_literal: true

# Benchmark for CompletionManager#load_history!
# Usage: ruby -Ilib benchmark/load_history.rb

require "benchmark"
require "json"
require "ruvim"

# Generate a history file with 100 items per prefix, some duplicates
items = (1..100).map { |i| "command_#{i}" }
items += items.sample(30) # add duplicates
payload = { ":" => items, "/" => items.first(50), "?" => items.first(20) }

tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
Dir.mkdir(tmpdir) unless Dir.exist?(tmpdir)
history_path = File.join(tmpdir, "bench_history.json")
File.write(history_path, JSON.pretty_generate(payload))

editor = RuVim::Editor.new
editor.ensure_bootstrap_buffer!

n = 5_000
Benchmark.bm(20) do |bm|
  bm.report("load_history!") do
    n.times do
      cm = RuVim::CompletionManager.new(editor: editor)
      # Temporarily override history_file_path
      cm.define_singleton_method(:history_file_path) { history_path }
      cm.load_history!
    end
  end
end

File.delete(history_path) if File.exist?(history_path)
