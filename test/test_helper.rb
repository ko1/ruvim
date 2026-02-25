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
