# frozen_string_literal: true

require "io/console"

module RuVim
  class Terminal
    def initialize(stdin: STDIN, stdout: STDOUT)
      @stdin = stdin
      @stdout = stdout
      @sixel_capable = nil
    end

    # Query terminal for sixel support via DA1 response.
    # Returns true if the terminal advertises sixel capability (attribute 4).
    def sixel_capable?
      return @sixel_capable unless @sixel_capable.nil?

      @sixel_capable = detect_sixel
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

    # Query cell size in pixels via mode 16 (xterminal cell size).
    # Returns [cell_width, cell_height] or [8, 16] as fallback.
    def cell_size
      @cell_size ||= [8, 16]
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

    private

    def detect_sixel
      return false unless @stdin.respond_to?(:raw) && @stdout.respond_to?(:write)

      # Send DA1 query
      @stdout.write("\e[c")
      @stdout.flush

      # Read response with timeout
      response = +""
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        if IO.select([@stdin], nil, nil, 0.05)
          ch = @stdin.read_nonblock(64, exception: false)
          break if ch == :wait_readable || ch.nil?
          response << ch
          break if response.include?("c")
        end
      end

      # DA1 response: ESC [ ? <attrs> c
      # Sixel is indicated by attribute 4
      if (m = response.match(/\e\[\?([0-9;]+)c/))
        attrs = m[1].split(";").map(&:to_i)
        return attrs.include?(4)
      end

      false
    rescue StandardError
      false
    end
  end
end
