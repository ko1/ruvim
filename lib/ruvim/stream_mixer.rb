# frozen_string_literal: true

module RuVim
  class StreamMixer
      LARGE_FILE_ASYNC_THRESHOLD_BYTES = 64 * 1024 * 1024
      LARGE_FILE_STAGED_PREFIX_BYTES = 8 * 1024 * 1024

      def initialize(editor:, signal_w:)
        @editor = editor
        @signal_w = signal_w
        @stream_event_queue = nil
      end

      def prepare_stdin_stream_buffer!(io)
        buf = @editor.current_buffer
        if buf.intro_buffer?
          @editor.materialize_intro_buffer!
          buf = @editor.current_buffer
        end

        buf.replace_all_lines!([""])
        buf.configure_special!(kind: :stream, name: "[stdin]", readonly: true, modifiable: false)
        buf.modified = false
        buf.options["filetype"] = "text"
        ensure_event_queue!
        move_window_to_stream_end!(@editor.current_window, buf)
        @editor.echo("[stdin] follow")
        @pending_stdin = { buf: buf, io: io }
        buf
      end

      def start_pending_stdin!
        return unless @pending_stdin

        ps = @pending_stdin
        @pending_stdin = nil
        buf = ps[:buf]
        ensure_event_queue!
        buf.stream = Stream::Stdin.new(
          io: ps[:io], buffer_id: buf.id, queue: @stream_event_queue,
          stop_handler: -> { stop_buffer_stream!(buf) }, &method(:notify_signal_wakeup)
        )
      end

      def start_command_stream!(buf, command, chdir: nil)
        ensure_event_queue!
        stop = -> { stop_buffer_stream!(buf) }
        buf.stream = if chdir
          Stream::Git.new(cmd: command, root: chdir, buffer_id: buf.id, queue: @stream_event_queue,
            stop_handler: stop, &method(:notify_signal_wakeup))
        else
          Stream::Run.new(command: command, buffer_id: buf.id, queue: @stream_event_queue,
            stop_handler: stop, &method(:notify_signal_wakeup))
        end
      end

      def stop_buffer_stream!(buf)
        return false unless buf&.stream&.live?

        buf.stream.stop!
        @editor.echo("#{buf.display_name} stopped")
        notify_signal_wakeup
        true
      end

      def drain_events!
        return false unless @stream_event_queue

        changed = false
        loop do
          event = @stream_event_queue.pop(true)
          case event[:type]
          when :stream_data
            changed = apply_stream_chunk!(event[:buffer_id], event[:data]) || changed
          when :stream_eof
            changed = finish_stream!(event[:buffer_id], status: event[:status]) || changed
          when :stream_error
            changed = fail_stream!(event[:buffer_id], event[:error]) || changed
          when :follow_data
            changed = apply_stream_chunk!(event[:buffer_id], event[:data]) || changed
          when :follow_truncated
            if (buf = @editor.buffers[event[:buffer_id]])
              @editor.echo("[follow] file truncated: #{buf.display_name}")
              changed = true
            end
          when :follow_deleted
            if (buf = @editor.buffers[event[:buffer_id]])
              @editor.echo("[follow] file deleted, waiting for re-creation: #{buf.display_name}")
              changed = true
            end
          when :file_lines
            changed = apply_async_file_lines!(event[:buffer_id], event[:head], event[:lines], loaded_bytes: event[:loaded_bytes], file_size: event[:file_size]) || changed
          when :file_eof
            changed = finish_async_file_load!(event[:buffer_id], ended_with_newline: event[:ended_with_newline]) || changed
          when :file_error
            changed = fail_async_file_load!(event[:buffer_id], event[:error]) || changed
          end
        end
      rescue ThreadError
        changed
      end

      def follow_toggle
        buf = @editor.current_buffer
        raise RuVim::CommandError, "No file associated with buffer" unless buf.path

        if buf.stream.is_a?(Stream::Follow)
          stop_follow!(buf)
        else
          raise RuVim::CommandError, "Buffer has unsaved changes" if buf.modified?
          start_follow!(buf)
        end
      end

      def start_follow!(buf)
        ensure_event_queue!
        Buffer.ensure_regular_file!(buf.path) if buf.path

        if buf.path && File.file?(buf.path)
          data = File.binread(buf.path)
          if data.end_with?("\n") && buf.lines.last.to_s != ""
            following_wins = @editor.windows.values.select do |w|
              w.buffer_id == buf.id && stream_window_following_end?(w, buf)
            end
            buf.append_stream_text!("\n")
            following_wins.each { |w| move_window_to_stream_end!(w, buf) }
          end
        end

        buf.stream = Stream::Follow.new(
          path: buf.path, buffer_id: buf.id, queue: @stream_event_queue,
          stop_handler: -> { stop_follow!(buf) }, &method(:notify_signal_wakeup)
        )
        @editor.echo("[follow] #{buf.display_name}")
      end

      def stop_follow!(buf)
        buf.stream&.stop!
        # Remove trailing empty line added as sentinel by start_follow!
        if buf.line_count > 1 && buf.lines.last.to_s == ""
          buf.lines.pop
          last = buf.line_count - 1
          @editor.windows.each_value do |win|
            next unless win.buffer_id == buf.id
            win.cursor_y = last if win.cursor_y > last
          end
        end
        buf.stream = nil
        @editor.echo("[follow] stopped")
        true
      end

      def follow_active?(buf)
        buf.stream.is_a?(Stream::Follow)
      end

      def open_path_with_large_file_support(path)
        return @editor.open_path_sync(path) unless should_open_path_async?(path)
        return @editor.open_path_sync(path) unless can_start_async_file_load?

        open_path_asynchronously!(path)
      end

      def shutdown!
        @editor.buffers.each_value do |buf|
          buf.stream&.stop!
        rescue StandardError
          nil
        end
      end

      def ensure_event_queue!
        @stream_event_queue ||= Queue.new
      end

      private

      def apply_stream_chunk!(buffer_id, text)
        return false if text.to_s.empty?

        buf = @editor.buffers[buffer_id]
        return false unless buf

        following_win_ids = @editor.windows.values.filter_map do |win|
          next unless win.buffer_id == buf.id
          next unless stream_window_following_end?(win, buf)
          win.id
        end

        buf.append_stream_text!(text)

        following_win_ids.each do |win_id|
          win = @editor.windows[win_id]
          move_window_to_stream_end!(win, buf) if win
        end

        true
      end

      def finish_stream!(buffer_id, status: nil)
        buf = @editor.buffers[buffer_id]
        return false unless buf&.stream

        stream = buf.stream
        stream.thread = nil if stream.respond_to?(:thread=)
        stream.io = nil if stream.respond_to?(:io=)

        # Remove trailing empty line if present
        if buf.lines.length > 1 && buf.lines[-1] == ""
          buf.lines.pop
        end
        stream.state = :closed
        stream.exit_status = status if stream.respond_to?(:exit_status=)

        if status
          @editor.echo("#{buf.display_name} exit #{status.exitstatus}")
        elsif buf.kind == :stream
          @editor.echo("[stdin] EOF")
        else
          @editor.echo("#{buf.display_name} #{buf.line_count} lines")
        end
        true
      end

      def fail_stream!(buffer_id, error)
        buf = @editor.buffers[buffer_id]
        return false unless buf&.stream

        # Ignore errors from intentionally closed streams
        if buf.stream.state == :closed
          msg = error.to_s.downcase
          return false if msg.include?("stream closed") || msg.include?("closed in another thread")
        end

        stream = buf.stream
        stream.thread = nil if stream.respond_to?(:thread=)
        stream.io = nil if stream.respond_to?(:io=)
        stream.state = :error
        @editor.echo_error("#{buf.display_name} stream error: #{error}")
        true
      end

      def apply_async_file_lines!(buffer_id, head, lines, loaded_bytes: nil, file_size: nil)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        following_win_ids = if buf.stream.is_a?(Stream::Follow)
          @editor.windows.values.filter_map do |win|
            next unless win.buffer_id == buffer_id
            next unless stream_window_following_end?(win, buf)
            win.id
          end
        end

        buf.append_stream_lines!(head, lines)

        following_win_ids&.each do |win_id|
          win = @editor.windows[win_id]
          move_window_to_stream_end!(win, buf) if win
        end

        if loaded_bytes && file_size && file_size > 0
          pct = (loaded_bytes * 100.0 / file_size).clamp(0, 100)
          @editor.echo(format("\"%s\" loading... %d%%", buf.display_name, pct))
        end

        true
      end

      def finish_async_file_load!(buffer_id, ended_with_newline:)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        buf.finalize_async_file_load!(ended_with_newline: !!ended_with_newline)
        buf.stream.state = :closed if buf.stream
        @editor.echo(format("\"%s\" %dL", buf.display_name, buf.line_count))
        true
      end

      def fail_async_file_load!(buffer_id, error)
        buf = @editor.buffers[buffer_id]
        if buf&.stream
          buf.stream.state = :error
        end
        @editor.echo_error("\"#{(buf && buf.display_name) || buffer_id}\" load error: #{error}")
        true
      end

      def stream_window_following_end?(win, buf)
        return false unless win

        last_row = buf.line_count - 1
        win.cursor_y >= last_row
      end

      def move_window_to_stream_end!(win, buf)
        return unless win && buf

        last_row = buf.line_count - 1
        win.cursor_y = last_row
        win.cursor_x = buf.line_length(last_row)
        win.clamp_to_buffer(buf)
      end

      def should_open_path_async?(path)
        p = path.to_s
        return false if p.empty?
        return false unless File.file?(p)

        File.size(p) >= large_file_async_threshold_bytes
      rescue StandardError
        false
      end

      def can_start_async_file_load?
        @editor.buffers.none? { |_, buf| buf.stream.is_a?(Stream::FileLoad) && buf.stream.live? }
      end

      def large_file_async_threshold_bytes
        raw = ENV["RUVIM_ASYNC_FILE_THRESHOLD_BYTES"]
        n = raw.to_i if raw
        return n if n && n.positive?

        LARGE_FILE_ASYNC_THRESHOLD_BYTES
      end

      def open_path_asynchronously!(path)
        file_size = File.size(path)
        buf = @editor.add_empty_buffer(path: path)
        @editor.switch_to_buffer(buf.id)
        buf.modified = false

        ensure_event_queue!
        io = File.open(path, "rb")
        staged_prefix_bytes = async_file_staged_prefix_bytes
        staged_mode = file_size > staged_prefix_bytes
        if staged_mode
          prefix = io.read(staged_prefix_bytes) || "".b
          unless prefix.empty?
            last_nl = prefix.rindex("\n".b)
            if last_nl && last_nl < prefix.bytesize - 1
              remainder = prefix.bytesize - last_nl - 1
              prefix = prefix[0..last_nl]
              io.seek(-remainder, IO::SEEK_CUR)
            end
            buf.append_stream_text!(Buffer.decode_text(prefix))
          end
        end

        if io.eof?
          buf.finalize_async_file_load!(ended_with_newline: prefix&.end_with?("\n") || false)
          io.close unless io.closed?
          return buf
        end

        # Create FileLoad stream after prefix reading; starts background thread immediately
        buf.stream = Stream::FileLoad.new(io: io, file_size: file_size, buffer_id: buf.id, queue: @stream_event_queue, &method(:notify_signal_wakeup))

        size_mb = file_size.fdiv(1024 * 1024)
        if staged_mode
          @editor.echo(format("\"%s\" loading... (showing first %.0fMB of %.1fMB)", path, staged_prefix_bytes.fdiv(1024 * 1024), size_mb))
        else
          @editor.echo(format("\"%s\" loading... (%.1fMB)", path, size_mb))
        end
        buf
      rescue StandardError
        buf.stream = nil if buf
        raise
      end

      def async_file_staged_prefix_bytes
        raw = ENV["RUVIM_ASYNC_FILE_PREFIX_BYTES"]
        n = raw.to_i if raw
        return n if n && n.positive?

        LARGE_FILE_STAGED_PREFIX_BYTES
      end

      def notify_signal_wakeup
        @signal_w.write_nonblock(".")
      rescue IO::WaitWritable, Errno::EPIPE
        nil
      end
  end
end
