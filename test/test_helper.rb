# Suppress "system temporary path is not writable" warnings in sandboxed environments
unless ENV["TMPDIR"] && File.writable?(ENV["TMPDIR"])
  candidates = ["/tmp", "/var/tmp"]
  # Claude Code sandbox uses /tmp/claude-<uid>
  candidates.unshift("/tmp/claude-#{Process.uid}") if Dir.exist?("/tmp/claude-#{Process.uid}")
  found = candidates.find { |d| File.writable?(d) }
  ENV["TMPDIR"] = found if found
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "minitest/autorun"
require "ruvim"

module RuVimTestHelpers
  def fresh_editor
    editor = RuVim::Editor.new
    editor.ensure_bootstrap_buffer!
    editor
  end
end

class Minitest::Test
  include RuVimTestHelpers
end
