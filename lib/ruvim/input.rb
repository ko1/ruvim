# frozen_string_literal: true

module RuVim
  class Input
    def initialize(input)
      @input = input
    end

    def read_key(timeout: nil, wakeup_ios: [], esc_timeout: nil)
      ios = [@input, *wakeup_ios].compact
      readable = IO.select(ios, nil, nil, timeout)
      return nil unless readable

      ready = readable[0]
      wakeups = ready - [@input]
      wakeups.each { |io| drain_io(io) }
      return nil unless ready.include?(@input)

      ch = @input.getch
      case ch
      when "\u0002" then :ctrl_b
      when "\u0003" then :ctrl_c
      when "\u0004" then :ctrl_d
      when "\u0005" then :ctrl_e
      when "\u0006" then :ctrl_f
      when "\u0007" then :ctrl_g
      when "\u0009" then :ctrl_i
      when "\u000c" then :ctrl_l
      when "\u000e" then :ctrl_n
      when "\u000f" then :ctrl_o
      when "\u0010" then :ctrl_p
      when "\u0012" then :ctrl_r
      when "\u0015" then :ctrl_u
      when "\u0016" then :ctrl_v
      when "\u0017" then :ctrl_w
      when "\u0019" then :ctrl_y
      when "\u001a" then :ctrl_z
      when "\r", "\n" then :enter
      when "\u007f", "\b" then :backspace
      when "\e" then read_escape_sequence(timeout: esc_timeout)
      else ch
      end
    end

    def has_pending_input?
      IO.select([@input], nil, nil, 0) != nil
    end

    private

    def drain_io(io)
      loop do
        io.read_nonblock(1024)
      end
    rescue IO::WaitReadable, EOFError
      nil
    end

    def read_escape_sequence(timeout: nil)
      extra = +""
      recognized = {
        "[A" => :up,
        "[B" => :down,
        "[C" => :right,
        "[D" => :left,
        "[1;2A" => :shift_up,
        "[1;2B" => :shift_down,
        "[1;2C" => :shift_right,
        "[1;2D" => :shift_left,
        "[5~" => :pageup,
        "[6~" => :pagedown
      }
      wait = timeout.nil? ? 0.005 : [timeout.to_f, 0.0].max
      begin
        while IO.select([@input], nil, nil, wait)
          extra << @input.read_nonblock(1)
          key = recognized[extra]
          return key if key
        end
      rescue IO::WaitReadable, EOFError
      end

      case extra
      when "" then :escape
      else
        [:escape_sequence, extra]
      end
    end
  end
end
