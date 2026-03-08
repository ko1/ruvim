#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark file loading hotspots
#
# Usage: ruby benchmark/file_load.rb [path]
#   Default: huge_file in project root

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruvim/buffer"
require "ruvim/lang/registry"
require "ruvim/lang/base"

FILE = ARGV[0] || File.expand_path("../huge_file", __dir__)
unless File.exist?(FILE)
  abort "File not found: #{FILE}\nUsage: ruby benchmark/file_load.rb [path]"
end

size_mb = File.size(FILE) / 1024.0 / 1024.0
puts "File Load Benchmark"
puts "=" * 60
puts "Ruby: #{RUBY_VERSION}"
puts "File: #{FILE}"
puts "Size: %.1f MB" % size_mb
puts

# ---------------------------------------------------------------------------
# 1. Raw IO read
# ---------------------------------------------------------------------------
puts "--- 1. Raw file read ---"
Benchmark.bm(25) do |x|
  x.report("File.binread") do
    data = File.binread(FILE)
    data.size  # force read
  end
end
puts

# ---------------------------------------------------------------------------
# 2. decode_text (encoding detection)
# ---------------------------------------------------------------------------
puts "--- 2. decode_text ---"
raw = File.binread(FILE)
Benchmark.bm(25) do |x|
  x.report("decode_text") do
    RuVim::Buffer.decode_text(raw)
  end
end
puts

# ---------------------------------------------------------------------------
# 3. split_lines (String#split)
# ---------------------------------------------------------------------------
puts "--- 3. split_lines ---"
decoded = RuVim::Buffer.decode_text(raw)
Benchmark.bm(25) do |x|
  x.report("split(\"\\n\", -1)") do
    decoded.split("\n", -1)
  end
end
puts

# ---------------------------------------------------------------------------
# 4. Full Buffer.from_file
# ---------------------------------------------------------------------------
puts "--- 4. Full Buffer.from_file ---"
Benchmark.bm(25) do |x|
  x.report("Buffer.from_file") do
    RuVim::Buffer.from_file(id: 1, path: FILE)
  end
end
puts

# ---------------------------------------------------------------------------
# 5. Chunked read (simulating Stream::FileLoad)
# ---------------------------------------------------------------------------
puts "--- 5. Chunked read (4MB flush, simulating async load) ---"
CHUNK = 1 * 1024 * 1024
FLUSH = 4 * 1024 * 1024
Benchmark.bm(25) do |x|
  x.report("chunked read+split") do
    io = File.open(FILE, "rb")
    lines = [""]
    pending = "".b
    begin
      loop do
        chunk = io.readpartial(CHUNK)
        pending << chunk
        next if pending.bytesize < FLUSH

        last_nl = pending.rindex("\n".b)
        if last_nl
          send_bytes = pending[0..last_nl]
          pending = pending[(last_nl + 1)..] || "".b
        else
          send_bytes = pending
          pending = "".b
        end
        decoded = RuVim::Buffer.decode_text(send_bytes)
        parts = decoded.split("\n", -1)
        head = parts.shift || ""
        lines[-1] = lines[-1] + head unless head.empty?
        lines.concat(parts) unless parts.empty?
      end
    rescue EOFError
      unless pending.empty?
        decoded = RuVim::Buffer.decode_text(pending)
        parts = decoded.split("\n", -1)
        head = parts.shift || ""
        lines[-1] = lines[-1] + head unless head.empty?
        lines.concat(parts) unless parts.empty?
      end
    ensure
      io.close
    end
    puts "    lines loaded: #{lines.size}"
  end
end
puts

# ---------------------------------------------------------------------------
# 6. Memory profile
# ---------------------------------------------------------------------------
puts "--- 6. Memory usage ---"
GC.start
before = GC.stat[:malloc_increase_bytes_limit]
mem_before = `ps -o rss= -p #{$$}`.strip.to_i
buf = RuVim::Buffer.from_file(id: 2, path: FILE)
GC.start
mem_after = `ps -o rss= -p #{$$}`.strip.to_i
puts "  Lines: #{buf.line_count}"
puts "  RSS before: #{mem_before / 1024} MB"
puts "  RSS after:  #{mem_after / 1024} MB"
puts "  RSS delta:  #{(mem_after - mem_before) / 1024} MB"

puts
puts "=" * 60
puts "Done."
