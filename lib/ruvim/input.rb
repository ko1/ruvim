module RuVim
  class Input
    def initialize(stdin: STDIN)
      @stdin = stdin
    end

    def read_key(timeout: nil, wakeup_ios: [])
      ios = [@stdin, *wakeup_ios].compact
      readable = IO.select(ios, nil, nil, timeout)
      return nil unless readable

      ready = readable[0]
      wakeups = ready - [@stdin]
      wakeups.each { |io| drain_io(io) }
      return nil unless ready.include?(@stdin)

      ch = @stdin.getch
      return :ctrl_c if ch == "\u0003"
      return :ctrl_i if ch == "\u0009"
      return :ctrl_n if ch == "\u000e"
      return :ctrl_o if ch == "\u000f"
      return :ctrl_p if ch == "\u0010"
      return :ctrl_r if ch == "\u0012"
      return :ctrl_w if ch == "\u0017"
      return :enter if ch == "\r" || ch == "\n"
      return :backspace if ch == "\u007f" || ch == "\b"

      return read_escape_sequence if ch == "\e"

      ch
    end

    private

    def drain_io(io)
      loop do
        io.read_nonblock(1024)
      end
    rescue IO::WaitReadable, EOFError
      nil
    end

    def read_escape_sequence
      extra = +""
      begin
        while IO.select([@stdin], nil, nil, 0.005)
          extra << @stdin.read_nonblock(1)
        end
      rescue IO::WaitReadable, EOFError
      end

      case extra
      when "" then :escape
      when "[A" then :up
      when "[B" then :down
      when "[C" then :right
      when "[D" then :left
      when "[5~" then :pageup
      when "[6~" then :pagedown
      else
        [:escape_sequence, extra]
      end
    end
  end
end
