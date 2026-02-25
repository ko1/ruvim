module RuVim
  class ConfigLoader
    def initialize(command_registry:, ex_registry:, keymaps:, command_host:)
      @command_registry = command_registry
      @ex_registry = ex_registry
      @keymaps = keymaps
      @command_host = command_host
    end

    def load_default!
      path = xdg_config_path
      return nil unless File.file?(path)

      load_file(path)
    end

    def load_file(path, editor: nil, filetype: nil)
      dsl = ConfigDSL.new(
        command_registry: @command_registry,
        ex_registry: @ex_registry,
        keymaps: @keymaps,
        command_host: @command_host,
        editor: editor,
        filetype: filetype
      )
      code = File.read(path)
      dsl.instance_eval(code, path, 1)
      path
    end

    def load_ftplugin!(editor, buffer)
      filetype = buffer.options["filetype"].to_s
      return nil if filetype.empty?
      return nil if buffer.options["__ftplugin_loaded__"] == filetype

      path = ftplugin_path_for(filetype)
      return nil unless path && File.file?(path)

      load_file(path, editor:, filetype:)
      buffer.options["__ftplugin_loaded__"] = filetype
      path
    end

    private

    def xdg_config_path
      base = ::ENV["XDG_CONFIG_HOME"]
      if base && !base.empty?
        File.join(base, "ruvim", "init.rb")
      else
        File.expand_path("~/.config/ruvim/init.rb")
      end
    end

    def ftplugin_path_for(filetype)
      xdg_ftplugin_path(filetype)
    end

    def xdg_ftplugin_path(filetype)
      base = ::ENV["XDG_CONFIG_HOME"]
      if base && !base.empty?
        File.join(base, "ruvim", "ftplugin", "#{filetype}.rb")
      else
        File.expand_path("~/.config/ruvim/ftplugin/#{filetype}.rb")
      end
    end
  end
end
