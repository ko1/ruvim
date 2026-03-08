#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark different chunked file loading strategies
#
# Usage: ruby benchmark/chunked_load.rb [path]

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruvim/buffer"
require "ruvim/lang/registry"
require "ruvim/lang/base"

FILE = ARGV[0] || File.expand_path("../huge_file", __dir__)
abort "File not found: #{FILE}" unless File.exist?(FILE)

size_mb = File.size(FILE) / 1024.0 / 1024.0
puts "Chunked Load Benchmark"
puts "=" * 60
puts "Ruby: #{RUBY_VERSION}"
puts "File: #{FILE} (%.1f MB)" % size_mb
puts

CHUNK = 1 * 1024 * 1024
FLUSH = 4 * 1024 * 1024

# Baseline: sync read
puts "--- 0. Baseline: sync Buffer.from_file ---"
Benchmark.bm(30) do |x|
  x.report("sync (binread + split)") do
    data = RuVim::Buffer.decode_text(File.binread(FILE))
    lines = RuVim::Buffer.split_lines(data)
    lines.size
  end
end
puts

# Strategy A: current async (concat per chunk)
puts "--- A. Current async (concat per 4MB chunk) ---"
Benchmark.bm(30) do |x|
  x.report("concat per chunk") do
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
    puts "    lines: #{lines.size}"
  end
end
puts

# Strategy B: larger flush size (32MB)
puts "--- B. Larger flush (32MB) ---"
FLUSH_LARGE = 32 * 1024 * 1024
Benchmark.bm(30) do |x|
  x.report("32MB flush") do
    io = File.open(FILE, "rb")
    lines = [""]
    pending = "".b
    begin
      loop do
        chunk = io.readpartial(CHUNK)
        pending << chunk
        next if pending.bytesize < FLUSH_LARGE

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
    puts "    lines: #{lines.size}"
  end
end
puts

# Strategy C: collect sub-arrays, flatten once at end
puts "--- C. Collect sub-arrays, flatten at end ---"
Benchmark.bm(30) do |x|
  x.report("collect + flatten") do
    io = File.open(FILE, "rb")
    segments = []       # array of arrays
    carry = ""          # partial line from previous chunk
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
        # Merge carry into first element
        unless carry.empty?
          parts[0] = carry + (parts[0] || "")
          carry = ""
        end
        # Last element is partial (no trailing newline guaranteed by rindex)
        carry = parts.pop || ""
        segments << parts unless parts.empty?
      end
    rescue EOFError
      unless pending.empty?
        decoded = RuVim::Buffer.decode_text(pending)
        parts = decoded.split("\n", -1)
        unless carry.empty?
          parts[0] = carry + (parts[0] || "")
          carry = ""
        end
        carry = parts.pop || ""
        segments << parts unless parts.empty?
      end
    ensure
      io.close
    end
    # Final flatten
    lines = segments.flatten(1)
    lines << carry unless carry.empty?
    lines = [""] if lines.empty?
    puts "    lines: #{lines.size}"
  end
end
puts

# Strategy D: single large read + split (like sync but via IO.read chunks)
puts "--- D. Read all into one string, split once ---"
Benchmark.bm(30) do |x|
  x.report("IO.read full + split") do
    data = "".b
    io = File.open(FILE, "rb")
    begin
      loop { data << io.readpartial(CHUNK) }
    rescue EOFError
    ensure
      io.close
    end
    decoded = RuVim::Buffer.decode_text(data)
    lines = RuVim::Buffer.split_lines(decoded)
    puts "    lines: #{lines.size}"
  end
end
puts

# Strategy E: larger read chunk (4MB) + larger flush (32MB) + collect
puts "--- E. 4MB read + 32MB flush + collect ---"
CHUNK_LARGE = 4 * 1024 * 1024
Benchmark.bm(30) do |x|
  x.report("4MB read + 32MB flush") do
    io = File.open(FILE, "rb")
    segments = []
    carry = ""
    pending = "".b
    begin
      loop do
        chunk = io.readpartial(CHUNK_LARGE)
        pending << chunk
        next if pending.bytesize < FLUSH_LARGE

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
        unless carry.empty?
          parts[0] = carry + (parts[0] || "")
          carry = ""
        end
        carry = parts.pop || ""
        segments << parts unless parts.empty?
      end
    rescue EOFError
      unless pending.empty?
        decoded = RuVim::Buffer.decode_text(pending)
        parts = decoded.split("\n", -1)
        unless carry.empty?
          parts[0] = carry + (parts[0] || "")
          carry = ""
        end
        carry = parts.pop || ""
        segments << parts unless parts.empty?
      end
    ensure
      io.close
    end
    lines = segments.flatten(1)
    lines << carry unless carry.empty?
    lines = [""] if lines.empty?
    puts "    lines: #{lines.size}"
  end
end
puts

puts "=" * 60
puts "Done."
