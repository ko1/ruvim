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
      return :ctrl_b if ch == "\u0002"
      return :ctrl_c if ch == "\u0003"
      return :ctrl_d if ch == "\u0004"
      return :ctrl_e if ch == "\u0005"
      return :ctrl_f if ch == "\u0006"
      return :ctrl_i if ch == "\u0009"
      return :ctrl_l if ch == "\u000c"
      return :ctrl_n if ch == "\u000e"
      return :ctrl_o if ch == "\u000f"
      return :ctrl_p if ch == "\u0010"
      return :ctrl_r if ch == "\u0012"
      return :ctrl_u if ch == "\u0015"
      return :ctrl_v if ch == "\u0016"
      return :ctrl_w if ch == "\u0017"
      return :ctrl_y if ch == "\u0019"
      return :ctrl_z if ch == "\u001a"
      return :enter if ch == "\r" || ch == "\n"
      return :backspace if ch == "\u007f" || ch == "\b"

      return read_escape_sequence(timeout: esc_timeout) if ch == "\e"

      ch
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
