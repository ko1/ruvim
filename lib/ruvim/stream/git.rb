# frozen_string_literal: true

module RuVim
  class Stream::Git < Stream
    attr_accessor :io, :thread

    def initialize
      super()
      @io = nil
      @thread = nil
    end

    def start!(buffer_id:, cmd:, root:, queue:, &notify)
      stream = self
      @thread = Thread.new do
        IO.popen(cmd, chdir: root, err: [:child, :out]) do |io|
          stream.io = io
          while (chunk = io.read(4096))
            queue << { type: :stream_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
            notify.call
          end
        end
        stream.io = nil
        queue << { type: :stream_eof, buffer_id: buffer_id }
        notify.call
      rescue StandardError => e
        stream.io = nil
        queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
        notify.call
      end
    end

    def stop!
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
    end
  end
end
