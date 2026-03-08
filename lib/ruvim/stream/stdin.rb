# frozen_string_literal: true

module RuVim
  class Stream::Stdin < Stream
    attr_accessor :io, :thread

    def initialize(io:)
      super()
      @io = io
      @thread = nil
    end

    def status
      case @state
      when :live then "stdin"
      when :closed then "stdin/EOF"
      when :error then "stdin/error"
      end
    end

    def start!(buffer_id:, queue:, &notify)
      return if @thread&.alive?

      @state = :live
      io = @io
      stream = self
      @thread = Thread.new do
        loop do
          chunk = io.readpartial(4096)
          next if chunk.nil? || chunk.empty?

          queue << { type: :stream_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
          notify.call
        end
      rescue EOFError
        unless stream.state == :closed
          queue << { type: :stream_eof, buffer_id: buffer_id }
          notify.call
        end
      rescue IOError, StandardError => e
        unless stream.state == :closed
          queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
          notify.call
        end
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
      @state = :closed
    end
  end
end
