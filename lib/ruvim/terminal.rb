# frozen_string_literal: true

require "io/console"

module RuVim
  class Terminal
    def initialize(stdin: STDIN, stdout: STDOUT)
      @stdin = stdin
      @stdout = stdout
    end

    def winsize
      IO.console.winsize
    rescue StandardError
      [24, 80]
    end

    def write(str)
      @stdout.write(str)
      @stdout.flush
    end

    def with_ui
      @stdin.raw do
        write("\e]112\a\e[2 q\e[?1049h\e[?25l")
        yield
      ensure
        write("\e[0 q\e[?25h\e[?1049l")
      end
    end

    def suspend_for_shell(command)
      shell = ENV["SHELL"].to_s
      shell = "/bin/sh" if shell.empty?
      @stdin.cooked do
        write("\e[0 q\e[?25h\e[?1049l")
        system(shell, "-c", command)
        status = $?
        write("\r\nPress ENTER or type command to continue")
        @stdin.raw { @stdin.getc }
        write("\e[2 q\e[?1049h\e[?25l")
        status
      end
    end

    def suspend_for_tstp
      prev_tstp = Signal.trap("TSTP", "DEFAULT")
      @stdin.cooked do
        write("\e[0 q\e[?25h\e[?1049l")
        Process.kill("TSTP", 0)
      end
    ensure
      begin
        Signal.trap("TSTP", prev_tstp) if defined?(prev_tstp)
      rescue StandardError
        nil
      end
      write("\e[2 q\e[?1049h\e[?25l")
    end
  end
end
