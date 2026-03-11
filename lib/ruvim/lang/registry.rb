# frozen_string_literal: true

module RuVim
  module Lang
    # Central registry for language modules.
    # Each lang module registers itself at load time via Lang.register.
    module Registry
      @entries = {}

      class << self
        # Register a language module.
        #
        # @param filetype [String] primary filetype name (e.g. "ruby")
        # @param mod [Module] the lang module (must respond to :color_columns)
        # @param extensions [Array<String>] file extensions including dot (e.g. [".rb", ".rake"])
        # @param basenames [Array<String>] exact basenames (e.g. ["Makefile"])
        # @param basename_prefix [String, nil] prefix match for basename (e.g. "Dockerfile")
        # @param shebangs [Array<String, Regexp>] shebang command matchers
        # @param aliases [Array<String>] additional filetype names that map to the same module
        def register(filetype, mod:, extensions: [], basenames: [], basename_prefix: nil,
                     shebangs: [], aliases: [], buffer_defaults: {})
          entry = {
            filetype: filetype,
            mod: mod,
            extensions: extensions,
            basenames: basenames,
            basename_prefix: basename_prefix,
            shebangs: shebangs,
            aliases: aliases,
            buffer_defaults: buffer_defaults
          }.freeze
          @entries[filetype] = entry
          aliases.each { |a| @entries[a] = entry }
        end

        # Look up a lang module by filetype string.
        # Returns the module or Lang::Base if not found.
        def resolve_module(ft)
          entry = @entries[ft]
          entry ? entry[:mod] : Lang::Base
        end

        # Look up buffer defaults by filetype string. Returns {} if not registered.
        def buffer_defaults_for(ft)
          entry = @entries[ft]
          entry&.[](:buffer_defaults) || {}
        end

        # Detect filetype from file extension.
        # Returns filetype string or nil.
        def detect_by_extension(ext)
          ext = ext.downcase
          @entries.each_value do |entry|
            return entry[:filetype] if entry[:extensions].include?(ext)
          end
          nil
        end

        # Detect filetype from exact basename.
        # Returns filetype string or nil.
        def detect_by_basename(basename)
          @entries.each_value do |entry|
            return entry[:filetype] if entry[:basenames].include?(basename)
          end
          # Prefix match
          @entries.each_value do |entry|
            prefix = entry[:basename_prefix]
            return entry[:filetype] if prefix && basename.start_with?(prefix)
          end
          nil
        end

        # Detect filetype from shebang command name.
        # Returns filetype string or nil.
        def detect_by_shebang(cmd)
          @entries.each_value do |entry|
            entry[:shebangs].each do |matcher|
              if matcher.is_a?(Regexp)
                return entry[:filetype] if matcher.match?(cmd)
              elsif matcher.to_s == cmd
                return entry[:filetype]
              end
            end
          end
          nil
        end

        # Returns true if the filetype has a color_columns method.
        def highlight?(ft)
          entry = @entries[ft]
          entry && entry[:mod].respond_to?(:color_columns)
        end

        # Look up entry by filetype. Returns nil if not found.
        def [](ft)
          @entries[ft]
        end
      end
    end
  end
end
