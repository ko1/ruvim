# frozen_string_literal: true

require "pty"

module RuVim
  class Stream::Run < Stream
    attr_accessor :io, :pid, :thread, :command, :exit_status

    def initialize(command:, buffer_id:, queue:, stop_handler: nil, &notify)
      super(stop_handler: stop_handler)
      @command = command
      @io = nil
      @pid = nil
      @exit_status = nil
      @state = :live
      stream = self
      @thread = Thread.new do
        shell = ENV["SHELL"].to_s
        shell = "/bin/sh" if shell.empty?
        PTY.spawn(shell, "-c", command) do |r, _w, pid|
          stream.io = r
          stream.pid = pid
          begin
            while (chunk = r.readpartial(4096))
              text = Buffer.decode_text(chunk).delete("\r")
              queue << { type: :stream_data, buffer_id: buffer_id, data: text }
              notify.call
            end
          rescue EOFError, Errno::EIO
            # expected: PTY raises EIO when child process exits
          end
          _status = Process.waitpid2(pid)[1] rescue nil
          stream.io = nil
          queue << { type: :stream_eof, buffer_id: buffer_id, status: _status }
          notify.call
        end
      rescue StandardError => e
        stream.io = nil
        queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
        notify.call
      end
    end

    def status
      case @state
      when :live then "run"
      when :closed
        code = @exit_status&.exitstatus
        code ? "run/exit #{code}" : "run/EOF"
      when :error then "run/error"
      end
    end

    def stop!
      pid = @pid; @pid = nil
      if pid
        Process.kill(:TERM, pid) rescue nil
        Process.waitpid(pid) rescue nil
      end
      io = @io; @io = nil
      begin
        io&.close unless io&.closed?
      rescue IOError
        nil
      end
      thread = @thread; @thread = nil
      if thread&.alive?
        thread.kill
        thread.join(0.05)
      end
      @state = :closed
    end
  end
end
