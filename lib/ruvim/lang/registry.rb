# frozen_string_literal: true

module RuVim
  module Lang
    # Central registry for language modules.
    # Detection metadata is stored eagerly; actual modules are resolved lazily via autoload.
    module Registry
      @entries = {}
      @instances = {}

      class << self
        # Register a language module.
        #
        # @param filetype [String] primary filetype name (e.g. "ruby")
        # @param mod [Module, Symbol] the lang module, or a Symbol for lazy resolution via Lang.const_get.
        #   When a Symbol is given and the constant is not yet defined, autoload is set up automatically.
        # @param extensions [Array<String>] file extensions including dot (e.g. [".rb", ".rake"])
        # @param basenames [Array<String>] exact basenames (e.g. ["Makefile"])
        # @param basename_prefix [String, nil] prefix match for basename (e.g. "Dockerfile")
        # @param shebangs [Array<String, Regexp>] shebang command matchers
        # @param aliases [Array<String>] additional filetype names that map to the same module
        def register(filetype, mod:, extensions: [], basenames: [], basename_prefix: nil,
                     shebangs: [], aliases: [])
          setup_autoload(mod) if mod.is_a?(Symbol)
          entry = {
            filetype: filetype,
            mod: mod,
            extensions: extensions,
            basenames: basenames,
            basename_prefix: basename_prefix,
            shebangs: shebangs,
            aliases: aliases
          }.freeze
          @entries[filetype] = entry
          aliases.each { |a| @entries[a] = entry }
        end

        # Look up a lang instance by filetype string.
        # Returns a cached instance, or a Lang::Base instance if not found.
        def resolve_module(ft)
          entry = @entries[ft]
          return default_instance unless entry
          klass = resolve_mod(entry[:mod])
          @instances[klass] ||= klass.new
        end

        # Look up buffer defaults by filetype string.
        # Reads BUFFER_DEFAULTS from the lang class. Returns {} if not defined.
        def buffer_defaults_for(ft)
          inst = resolve_module(ft)
          klass = inst.class
          klass.const_defined?(:BUFFER_DEFAULTS, false) ? klass::BUFFER_DEFAULTS : {}
        end

        def default_instance
          @instances[Lang::Base] ||= Lang::Base.new
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

        # Look up entry by filetype. Returns nil if not found.
        def [](ft)
          @entries[ft]
        end

        private

        def resolve_mod(mod)
          mod.is_a?(Symbol) ? Lang.const_get(mod) : mod
        end

        def setup_autoload(mod_name)
          return if Lang.const_defined?(mod_name, false) || Lang.autoload?(mod_name)

          file = File.expand_path(mod_name.to_s.downcase, __dir__)
          Lang.autoload(mod_name, file)
        end
      end

      # Built-in filetype registrations.
      # Detection metadata only — buffer_defaults are in each lang module's BUFFER_DEFAULTS constant.
      register("text",    mod: :Base, extensions: %w[.txt])
      register("css",     mod: :Base, extensions: %w[.css])
      register("erlang",  mod: :Base, extensions: %w[.erl])
      register("markdown", mod: :Markdown, extensions: %w[.md])
      register("ruby",    mod: :Ruby, extensions: %w[.rb .rake .ru],
               basenames: %w[Gemfile Rakefile Guardfile Vagrantfile],
               shebangs: [/\Aruby(?:\d+(?:\.\d+)*)?\z/])
      register("json",    mod: :Json, extensions: %w[.json], aliases: %w[jsonl])
      register("jsonl",   mod: :Json, extensions: %w[.jsonl])
      register("scheme",  mod: :Scheme, extensions: %w[.scm .ss .sld], shebangs: %w[gosh])
      register("c",       mod: :C, extensions: %w[.c .h])
      register("cpp",     mod: :Cpp, extensions: %w[.cpp .cc .cxx .hpp])
      register("diff",    mod: :Diff)
      register("yaml",    mod: :Yaml, extensions: %w[.yml .yaml])
      register("sh",      mod: :Sh, extensions: %w[.sh .bash .zsh],
               shebangs: %w[bash sh zsh ksh dash])
      register("python",  mod: :Python, extensions: %w[.py],
               shebangs: [/\Apython(?:\d+(?:\.\d+)*)?\z/])
      register("javascript", mod: :Javascript, extensions: %w[.js .mjs .cjs],
               aliases: %w[javascriptreact], shebangs: %w[node nodejs deno])
      register("javascriptreact", mod: :Javascript, extensions: %w[.jsx])
      register("typescript", mod: :Typescript, extensions: %w[.ts],
               aliases: %w[typescriptreact])
      register("typescriptreact", mod: :Typescript, extensions: %w[.tsx])
      register("html",    mod: :Html, extensions: %w[.html .htm .xml])
      register("toml",    mod: :Toml, extensions: %w[.toml])
      register("go",      mod: :Go, extensions: %w[.go])
      register("rust",    mod: :Rust, extensions: %w[.rs])
      register("make",    mod: :Makefile, basenames: %w[Makefile GNUmakefile makefile Justfile])
      register("dockerfile", mod: :Dockerfile, basenames: %w[Dockerfile], basename_prefix: "Dockerfile")
      register("sql",     mod: :Sql, extensions: %w[.sql])
      register("elixir",  mod: :Elixir, extensions: %w[.ex .exs], shebangs: %w[elixir iex])
      register("perl",    mod: :Perl, extensions: %w[.pl .pm .t],
               shebangs: [/\Aperl(?:\d+(?:\.\d+)*)?\z/])
      register("lua",     mod: :Lua, extensions: %w[.lua],
               shebangs: ["lua", /\Alua\d*\z/])
      register("ocaml",   mod: :Ocaml, extensions: %w[.ml .mli], shebangs: %w[ocaml])
      register("erb",     mod: :Erb, extensions: %w[.erb])
      register("gitcommit", mod: :Gitcommit)
      register("tsv",     mod: :Base, extensions: %w[.tsv])
      register("csv",     mod: :Base, extensions: %w[.csv])
    end
  end
end
