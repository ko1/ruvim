module RuVim
  class CLI
    Options = Struct.new(
      :files,
      :pre_config_actions,
      :startup_actions,
      :clean,
      :skip_user_config,
      :config_path,
      :readonly,
      :diff_mode,
      :quickfix_errorfile,
      :session_file,
      :no_swap,
      :nomodifiable,
      :restricted_mode,
      :verbose_level,
      :startup_time_path,
      :startup_open_layout,
      :startup_open_count,
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

      if opts.files.length > 1 && opts.startup_open_layout.nil?
        raise ParseError, "multiple files are not supported yet"
      end

      if opts.config_path && !File.file?(opts.config_path)
        raise ParseError, "config file not found: #{opts.config_path}"
      end

      ui_stdin = stdin
      stdin_stream_mode = false
      if stdin.respond_to?(:tty?) && !stdin.tty?
        ui_stdin = IO.console
        raise ParseError, "no controlling terminal available for interactive UI" unless ui_stdin
        stdin_stream_mode = opts.files.empty?
      end

      app = RuVim::App.new(
        path: opts.files.first,
        paths: opts.files,
        stdin: stdin,
        ui_stdin: ui_stdin,
        stdin_stream_mode: stdin_stream_mode,
        stdout: stdout,
        pre_config_actions: opts.pre_config_actions,
        startup_actions: opts.startup_actions,
        clean: opts.clean,
        skip_user_config: opts.skip_user_config,
        config_path: opts.config_path,
        readonly: opts.readonly,
        diff_mode: opts.diff_mode,
        quickfix_errorfile: opts.quickfix_errorfile,
        session_file: opts.session_file,
        nomodifiable: opts.nomodifiable,
        restricted: opts.restricted_mode,
        verbose_level: opts.verbose_level,
        verbose_io: stderr,
        startup_time_path: opts.startup_time_path,
        startup_open_layout: opts.startup_open_layout,
        startup_open_count: opts.startup_open_count
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
        pre_config_actions: [],
        startup_actions: [],
        clean: false,
        skip_user_config: false,
        config_path: nil,
        readonly: false,
        diff_mode: false,
        quickfix_errorfile: nil,
        session_file: nil,
        no_swap: false,
        nomodifiable: false,
        restricted_mode: false,
        verbose_level: 0,
        startup_time_path: nil,
        startup_open_layout: nil,
        startup_open_count: nil,
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
        when "--verbose"
          opts.verbose_level = [opts.verbose_level.to_i, 1].max
        when /\A--verbose=(\d+)\z/
          opts.verbose_level = Regexp.last_match(1).to_i
        when "--startuptime"
          i += 1
          raise ParseError, "--startuptime requires a file path" if i >= args.length
          opts.startup_time_path = args[i]
        when "--cmd"
          i += 1
          raise ParseError, "--cmd requires an argument" if i >= args.length
          opts.pre_config_actions << { type: :ex, value: args[i] }
        when /\A--cmd=(.+)\z/
          opts.pre_config_actions << { type: :ex, value: Regexp.last_match(1) }
        when "--clean"
          opts.clean = true
        when "-R"
          opts.readonly = true
        when "-d"
          opts.diff_mode = true
        when "-q"
          i += 1
          raise ParseError, "-q requires an errorfile path" if i >= args.length
          opts.quickfix_errorfile = args[i]
        when "-S"
          if i + 1 < args.length && !args[i + 1].start_with?("-")
            i += 1
            opts.session_file = args[i]
          else
            opts.session_file = "Session.vim"
          end
        when "-n"
          opts.no_swap = true
        when "-M"
          opts.nomodifiable = true
        when "-Z"
          opts.restricted_mode = true
        when "-V"
          opts.verbose_level = [opts.verbose_level.to_i, 1].max
        when /\A-V(\d+)\z/
          opts.verbose_level = Regexp.last_match(1).to_i
        when "-o", "-O", "-p"
          apply_layout_option(opts, arg, nil)
        when /\A-(o|O|p)(\d+)\z/
          apply_layout_option(opts, Regexp.last_match(1), Regexp.last_match(2).to_i)
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

    def self.apply_layout_option(opts, token, count)
      layout =
        case token
        when "-o", "o" then :horizontal
        when "-O", "O" then :vertical
        when "-p", "p" then :tab
        else
          raise ParseError, "unknown layout option: #{token}"
        end
      opts.startup_open_layout = layout
      opts.startup_open_count = count
    end
    private_class_method :apply_layout_option

    def self.help_text
      <<~TXT
        Usage: ruvim [options] [file]

        Options:
          -h, --help        Show this help
          -v, --version     Show version
          --clean           Start without user config and ftplugin
          -R                Open file readonly (disallow :w on current buffer)
          -d                Diff mode requested (compat placeholder; not implemented yet)
          -q {errorfile}    Quickfix startup placeholder (not implemented yet)
          -S [session]      Session startup placeholder (not implemented yet)
          -M                Open file unmodifiable (disallow editing; also readonly)
          -Z                Restricted mode (skip config/ftplugin, disable :ruby)
          -V[N], --verbose[=N]
                            Verbose startup/config/command logs to stderr
          --startuptime FILE
                            Write startup timing log
          --cmd {cmd}       Execute Ex command before loading user config
          -n                No-op (reserved for swap/persistent features compatibility)
          -o[N]             Open files in horizontal splits
          -O[N]             Open files in vertical splits
          -p[N]             Open files in tabs
          -u {path|NONE}    Use config file path, or disable user config with NONE
          -c {cmd}          Execute Ex command after startup
          +{cmd}            Execute Ex command after startup
          +{line}           Move cursor to line after startup
          +                 Move cursor to last line after startup

        Examples:
          ruvim file.txt
          ruvim +10 file.txt
          ruvim --cmd 'set number' file.txt
          ruvim -c 'set number' file.txt
          ruvim --clean -u NONE
      TXT
    end
  end
end
