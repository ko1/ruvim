module RuVim
  class CLI
    Options = Struct.new(
      :files,
      :startup_actions,
      :clean,
      :skip_user_config,
      :config_path,
      :readonly,
      :no_swap,
      :show_help,
      :show_version,
      keyword_init: true
    )

    class ParseError < RuVim::Error; end

    def self.run(argv = ARGV, stdin: STDIN, stdout: STDOUT, stderr: STDERR)
      opts = parse(argv)

      if opts.show_help
        stdout.write(help_text)
        return 0
      end

      if opts.show_version
        stdout.puts("RuVim #{RuVim::VERSION}")
        return 0
      end

      if opts.files.length > 1
        raise ParseError, "multiple files are not supported yet"
      end

      if opts.config_path && !File.file?(opts.config_path)
        raise ParseError, "config file not found: #{opts.config_path}"
      end

      app = RuVim::App.new(
        path: opts.files.first,
        stdin: stdin,
        stdout: stdout,
        startup_actions: opts.startup_actions,
        clean: opts.clean,
        skip_user_config: opts.skip_user_config,
        config_path: opts.config_path,
        readonly: opts.readonly
      )
      app.run
      0
    rescue ParseError => e
      stderr.puts("ruvim: #{e.message}")
      stderr.puts("Try 'ruvim --help'.")
      2
    end

    def self.parse(argv)
      args = Array(argv).dup
      opts = Options.new(
        files: [],
        startup_actions: [],
        clean: false,
        skip_user_config: false,
        config_path: nil,
        readonly: false,
        no_swap: false,
        show_help: false,
        show_version: false
      )

      i = 0
      stop_options = false
      while i < args.length
        arg = args[i]
        if stop_options
          opts.files << arg
          i += 1
          next
        end

        case arg
        when "--"
          stop_options = true
        when "--help", "-h"
          opts.show_help = true
        when "--version", "-v"
          opts.show_version = true
        when "--clean"
          opts.clean = true
        when "-R"
          opts.readonly = true
        when "-n"
          opts.no_swap = true
        when "-u"
          i += 1
          raise ParseError, "-u requires an argument" if i >= args.length
          apply_u_option(opts, args[i])
        when /\A-u(.+)\z/
          apply_u_option(opts, Regexp.last_match(1))
        when "-c"
          i += 1
          raise ParseError, "-c requires an argument" if i >= args.length
          opts.startup_actions << { type: :ex, value: args[i] }
        when /\A\+/
          apply_plus_option(opts, arg)
        else
          if arg.start_with?("-")
            raise ParseError, "unknown option: #{arg}"
          end
          opts.files << arg
        end
        i += 1
      end

      opts
    end

    def self.apply_u_option(opts, value)
      if value == "NONE"
        opts.skip_user_config = true
        opts.config_path = nil
      else
        opts.skip_user_config = false
        opts.config_path = value
      end
    end
    private_class_method :apply_u_option

    def self.apply_plus_option(opts, arg)
      rest = arg[1..].to_s
      if rest.empty?
        opts.startup_actions << { type: :line_end }
      elsif rest.match?(/\A\d+\z/)
        opts.startup_actions << { type: :line, value: rest.to_i }
      else
        opts.startup_actions << { type: :ex, value: rest }
      end
    end
    private_class_method :apply_plus_option

    def self.help_text
      <<~TXT
        Usage: ruvim [options] [file]

        Options:
          -h, --help        Show this help
          -v, --version     Show version
          --clean           Start without user config and ftplugin
          -R                Open file readonly (disallow :w on current buffer)
          -n                No-op (reserved for swap/persistent features compatibility)
          -u {path|NONE}    Use config file path, or disable user config with NONE
          -c {cmd}          Execute Ex command after startup
          +{cmd}            Execute Ex command after startup
          +{line}           Move cursor to line after startup
          +                 Move cursor to last line after startup

        Examples:
          ruvim file.txt
          ruvim +10 file.txt
          ruvim -c 'set number' file.txt
          ruvim --clean -u NONE
      TXT
    end
  end
end
