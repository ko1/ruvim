require_relative "test_helper"
require "fileutils"
require "tmpdir"

class ConfigLoaderTest < Minitest::Test
  def setup
    @loader = RuVim::ConfigLoader.new(
      command_registry: RuVim::CommandRegistry.instance,
      ex_registry: RuVim::ExCommandRegistry.instance,
      keymaps: RuVim::KeymapManager.new,
      command_host: RuVim::GlobalCommands.instance
    )
  end

  def test_load_ftplugin_rejects_path_traversal_filetype
    Dir.mktmpdir("ruvim-ftplugin") do |dir|
      xdg = File.join(dir, "xdg")
      FileUtils.mkdir_p(File.join(xdg, "ruvim", "ftplugin"))
      evil = File.join(xdg, "ruvim", "evil.rb")
      File.write(evil, "raise 'should not load'\n")

      editor = RuVim::Editor.new
      buffer = editor.add_empty_buffer
      editor.add_window(buffer_id: buffer.id)
      buffer.options["filetype"] = "../evil"

      old = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = xdg
      begin
        assert_nil @loader.load_ftplugin!(editor, buffer)
        refute_equal "../evil", buffer.options["__ftplugin_loaded__"]
      ensure
        ENV["XDG_CONFIG_HOME"] = old
      end
    end
  end
end
