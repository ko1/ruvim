# frozen_string_literal: true

module RuVim
  class Stream::FileLoad < Stream
    CHUNK_BYTES = 1 * 1024 * 1024
    FLUSH_BYTES = 4 * 1024 * 1024

    attr_accessor :thread, :io

    def initialize(io:, file_size:, buffer_id:, queue:, stop_handler: nil, &notify)
      super(stop_handler: stop_handler)
      @io = io
      @state = :live
      @thread = Thread.new do
        pending_bytes = "".b
        ended_with_newline = false
        loaded_bytes = io.pos
        loop do
          chunk = io.readpartial(CHUNK_BYTES)
          next if chunk.nil? || chunk.empty?

          loaded_bytes += chunk.bytesize
          ended_with_newline = chunk.end_with?("\n")
          pending_bytes << chunk
          next if pending_bytes.bytesize < FLUSH_BYTES

          last_nl = pending_bytes.rindex("\n".b)
          if last_nl
            send_bytes = pending_bytes[0..last_nl]
            pending_bytes = pending_bytes[(last_nl + 1)..] || "".b
          else
            send_bytes = pending_bytes
            pending_bytes = "".b
          end
          decoded = Buffer.decode_text(send_bytes)
          parts = decoded.split("\n", -1)
          head = parts.shift || ""
          queue << { type: :file_lines, buffer_id: buffer_id, head: head, lines: parts, loaded_bytes: loaded_bytes, file_size: file_size }
          notify.call
        end
      rescue EOFError
        unless pending_bytes.empty?
          decoded = Buffer.decode_text(pending_bytes)
          parts = decoded.split("\n", -1)
          head = parts.shift || ""
          queue << { type: :file_lines, buffer_id: buffer_id, head: head, lines: parts }
          notify.call
        end
        queue << { type: :file_eof, buffer_id: buffer_id, ended_with_newline: ended_with_newline }
        notify.call
      rescue StandardError => e
        queue << { type: :file_error, buffer_id: buffer_id, error: e.message.to_s }
        notify.call
      ensure
        begin
          io.close unless io.closed?
        rescue StandardError
          nil
        end
      end
    end

    def status
      case @state
      when :live then "load"
      when :error then "load/error"
      end
    end

    def stop!
      io = @io; @io = nil
      begin
        io&.close unless io&.closed?
      rescue StandardError
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
