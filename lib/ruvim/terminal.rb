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

    # Query cell size in pixels.
    # Returns [cell_width, cell_height] or estimated fallback.
    def cell_size
      @cell_size ||= detect_cell_size
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

    def detect_cell_size
      return [8, 16] unless @stdin.respond_to?(:raw) && @stdout.respond_to?(:write)

      # Query cell size: ESC[16t → ESC[6;height;width t
      @stdout.write("\e[16t")
      @stdout.flush

      response = read_terminal_response("t", timeout: 0.3)
      if (m = response.match(/\e\[6;(\d+);(\d+)t/))
        h = m[1].to_i
        w = m[2].to_i
        return [w, h] if w > 0 && h > 0
      end

      # Fallback: estimate from window pixel size and character grid
      # ESC[14t → ESC[4;height;width t (window pixel size)
      @stdout.write("\e[14t")
      @stdout.flush
      response = read_terminal_response("t", timeout: 0.3)
      if (m = response.match(/\e\[4;(\d+);(\d+)t/))
        px_h = m[1].to_i
        px_w = m[2].to_i
        rows, cols = winsize
        if rows > 0 && cols > 0 && px_w > 0 && px_h > 0
          return [px_w / cols, px_h / rows]
        end
      end

      [8, 16]
    rescue StandardError
      [8, 16]
    end

    def read_terminal_response(terminator, timeout: 0.3)
      response = +""
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        if IO.select([@stdin], nil, nil, 0.05)
          ch = @stdin.read_nonblock(64, exception: false)
          break if ch == :wait_readable || ch.nil?
          response << ch
          break if response.include?(terminator)
        end
      end
      response
    rescue StandardError
      response || ""
    end

    def detect_sixel
      return false unless @stdin.respond_to?(:raw) && @stdout.respond_to?(:write)

      @stdout.write("\e[c")
      @stdout.flush
      response = read_terminal_response("c", timeout: 0.5)

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
