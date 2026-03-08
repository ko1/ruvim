# frozen_string_literal: true

require "pty"

module RuVim
  class StreamHandler
      LARGE_FILE_ASYNC_THRESHOLD_BYTES = 64 * 1024 * 1024
      LARGE_FILE_STAGED_PREFIX_BYTES = 8 * 1024 * 1024
      ASYNC_FILE_READ_CHUNK_BYTES = 1 * 1024 * 1024
      ASYNC_FILE_EVENT_FLUSH_BYTES = 4 * 1024 * 1024

      def initialize(editor:, signal_w:)
        @editor = editor
        @signal_w = signal_w
        @stream_event_queue = nil
        @async_file_loads = {}
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
        buf.stream_state = :live
        buf.stream_io = io
        buf.stream_stop_handler = -> { stop_buffer_stream!(buf) }
        buf.options["filetype"] = "text"
        ensure_event_queue!
        move_window_to_stream_end!(@editor.current_window, buf)
        @editor.echo("[stdin] follow")
        buf
      end

      def start_stdin_stream_reader!(buf)
        return unless buf.stream_io
        ensure_event_queue!
        return if buf.stream_thread&.alive?

        io = buf.stream_io
        buffer_id = buf.id
        queue = @stream_event_queue
        buf.stream_thread = Thread.new do
          loop do
            chunk = io.readpartial(4096)
            next if chunk.nil? || chunk.empty?

            queue << { type: :stream_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
            notify_signal_wakeup
          end
        rescue EOFError
          unless buf.stream_state == :closed
            queue << { type: :stream_eof, buffer_id: buffer_id }
            notify_signal_wakeup
          end
        rescue IOError, StandardError => e
          unless buf.stream_state == :closed
            queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
            notify_signal_wakeup
          end
        end
      end

      def start_command_stream!(buf, command)
        ensure_event_queue!
        shell = ENV["SHELL"].to_s
        shell = "/bin/sh" if shell.empty?
        buffer_id = buf.id
        queue = @stream_event_queue
        buf.stream_stop_handler = -> { stop_buffer_stream!(buf) }
        buf.stream_thread = Thread.new do
          PTY.spawn(shell, "-c", command) do |r, _w, pid|
            buf.stream_io = r
            buf.stream_pid = pid
            begin
              while (chunk = r.readpartial(4096))
                text = Buffer.decode_text(chunk).delete("\r")
                queue << { type: :stream_data, buffer_id: buffer_id, data: text }
                notify_signal_wakeup
              end
            rescue EOFError
              # expected
            end
            _status = Process.waitpid2(pid)[1] rescue nil
            buf.stream_io = nil
            queue << { type: :stream_eof, buffer_id: buffer_id, status: _status }
            notify_signal_wakeup
          end
        rescue StandardError => e
          buf.stream_io = nil
          queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
          notify_signal_wakeup
        end
      end

      def start_git_stream_command(buffer_id, cmd, root)
        ensure_event_queue!
        buf = @editor.buffers[buffer_id]
        return unless buf

        queue = @stream_event_queue
        buf.stream_thread = Thread.new do
          IO.popen(cmd, chdir: root, err: [:child, :out]) do |io|
            buf.stream_io = io
            while (chunk = io.read(4096))
              queue << { type: :stream_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
              notify_signal_wakeup
            end
          end
          buf.stream_io = nil
          queue << { type: :stream_eof, buffer_id: buffer_id }
          notify_signal_wakeup
        rescue StandardError => e
          buf.stream_io = nil
          queue << { type: :stream_error, buffer_id: buffer_id, error: e.message.to_s }
          notify_signal_wakeup
        end
      end

      def stop_buffer_stream!(buf)
        return false unless buf
        return false unless buf.stream_state == :live

        pid = buf.stream_pid
        buf.stream_pid = nil
        if pid
          Process.kill(:TERM, pid) rescue nil
          Process.waitpid(pid) rescue nil
        end
        io = buf.stream_io
        buf.stream_io = nil
        if io
          begin
            io.close unless io.closed?
          rescue IOError
            nil
          end
        end
        thread = buf.stream_thread
        buf.stream_thread = nil
        if thread&.alive?
          thread.kill
          thread.join(0.05)
        end

        buf.stream_state = :closed
        @editor.echo("#{buf.display_name} stopped")
        notify_signal_wakeup
        true
      end

      def stop_git_stream!(buffer_id)
        buf = @editor.buffers[buffer_id]
        return unless buf

        io = buf.stream_io
        buf.stream_io = nil
        io&.close
      rescue IOError
        # already closed
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

      def ex_follow_toggle
        buf = @editor.current_buffer
        raise RuVim::CommandError, "No file associated with buffer" unless buf.path

        if buf.stream_watcher
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
        buffer_id = buf.id
        watcher = FileWatcher.create(buf.path) do |type, data|
          case type
          when :data
            @stream_event_queue << { type: :follow_data, buffer_id: buffer_id, data: data }
          when :truncated
            @stream_event_queue << { type: :follow_truncated, buffer_id: buffer_id }
          when :deleted
            @stream_event_queue << { type: :follow_deleted, buffer_id: buffer_id }
          end
          notify_signal_wakeup
        end
        watcher.start
        buf.stream_watcher = watcher
        buf.stream_state = :live
        buf.follow_backend = watcher.backend
        @editor.echo("[follow] #{buf.display_name}")
      end

      def stop_follow!(buf)
        watcher = buf.stream_watcher
        buf.stream_watcher = nil
        watcher&.stop
        # Remove trailing empty line added as sentinel by start_follow!
        if buf.line_count > 1 && buf.lines.last.to_s == ""
          buf.lines.pop
          last = buf.line_count - 1
          @editor.windows.each_value do |win|
            next unless win.buffer_id == buf.id
            win.cursor_y = last if win.cursor_y > last
          end
        end
        buf.stream_state = nil
        buf.follow_backend = nil
        @editor.echo("[follow] stopped")
      end

      def follow_active?(buf)
        !!buf.stream_watcher
      end

      def open_path_with_large_file_support(path)
        return @editor.open_path_sync(path) unless should_open_path_async?(path)
        return @editor.open_path_sync(path) unless can_start_async_file_load?

        open_path_asynchronously!(path)
      end

      def shutdown!
        shutdown_buffer_streams!
        shutdown_follow_watchers!
        shutdown_async_file_loaders!
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
        return false unless buf

        buf.stream_thread = nil
        buf.stream_io = nil

        # Remove trailing empty line if present
        if buf.lines.length > 1 && buf.lines[-1] == ""
          buf.lines.pop
        end
        buf.stream_state = :closed

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
        return false unless buf

        # Ignore errors from intentionally closed streams
        if buf.stream_state == :closed
          msg = error.to_s.downcase
          return false if msg.include?("stream closed") || msg.include?("closed in another thread")
        end

        buf.stream_thread = nil
        buf.stream_io = nil
        buf.stream_state = :error
        @editor.echo_error("#{buf.display_name} stream error: #{error}")
        true
      end

      def apply_async_file_lines!(buffer_id, head, lines, loaded_bytes: nil, file_size: nil)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        # If follow mode is active, track windows at the end before appending
        following_win_ids = if buf.stream_watcher
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
        @async_file_loads.delete(buffer_id)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        buf.finalize_async_file_load!(ended_with_newline: !!ended_with_newline)
        buf.loading_state = :closed
        @editor.echo(format("\"%s\" %dL", buf.display_name, buf.line_count))
        true
      end

      def fail_async_file_load!(buffer_id, error)
        state = @async_file_loads.delete(buffer_id)
        buf = @editor.buffers[buffer_id]
        if buf
          buf.loading_state = :error
        end
        @editor.echo_error("\"#{(state && state[:path]) || (buf && buf.display_name) || buffer_id}\" load error: #{error}")
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
        @async_file_loads.empty?
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
        buf.loading_state = :live
        buf.modified = false

        ensure_event_queue!
        io = File.open(path, "rb")
        state = { path: path, io: io, thread: nil, ended_with_newline: false }
        staged_prefix_bytes = async_file_staged_prefix_bytes
        staged_mode = file_size > staged_prefix_bytes
        if staged_mode
          prefix = io.read(staged_prefix_bytes) || "".b
          unless prefix.empty?
            # Split at last newline to avoid displaying a partial line
            last_nl = prefix.rindex("\n".b)
            if last_nl && last_nl < prefix.bytesize - 1
              remainder = prefix.bytesize - last_nl - 1
              prefix = prefix[0..last_nl]
              io.seek(-remainder, IO::SEEK_CUR)
            end
            buf.append_stream_text!(Buffer.decode_text(prefix))
            state[:ended_with_newline] = prefix.end_with?("\n")
          end
        end

        if io.eof?
          buf.finalize_async_file_load!(ended_with_newline: state[:ended_with_newline])
          buf.loading_state = :closed
          io.close unless io.closed?
          return buf
        end

        state[:file_size] = file_size
        @async_file_loads[buf.id] = state
        state[:thread] = start_async_file_loader_thread(buf.id, io, file_size: file_size)

        size_mb = file_size.fdiv(1024 * 1024)
        if staged_mode
          @editor.echo(format("\"%s\" loading... (showing first %.0fMB of %.1fMB)", path, staged_prefix_bytes.fdiv(1024 * 1024), size_mb))
        else
          @editor.echo(format("\"%s\" loading... (%.1fMB)", path, size_mb))
        end
        buf
      rescue StandardError
        @async_file_loads.delete(buf.id) if buf
        raise
      end

      def async_file_staged_prefix_bytes
        raw = ENV["RUVIM_ASYNC_FILE_PREFIX_BYTES"]
        n = raw.to_i if raw
        return n if n && n.positive?

        LARGE_FILE_STAGED_PREFIX_BYTES
      end

      def start_async_file_loader_thread(buffer_id, io, file_size: nil)
        Thread.new do
          pending_bytes = "".b
          ended_with_newline = false
          loaded_bytes = io.pos
          loop do
            chunk = io.readpartial(ASYNC_FILE_READ_CHUNK_BYTES)
            next if chunk.nil? || chunk.empty?

            loaded_bytes += chunk.bytesize
            ended_with_newline = chunk.end_with?("\n")
            pending_bytes << chunk
            next if pending_bytes.bytesize < ASYNC_FILE_EVENT_FLUSH_BYTES

            # Split at last newline in raw bytes
            last_nl = pending_bytes.rindex("\n".b)
            if last_nl
              send_bytes = pending_bytes[0..last_nl]
              pending_bytes = pending_bytes[(last_nl + 1)..] || "".b
            else
              send_bytes = pending_bytes
              pending_bytes = "".b
            end
            # Decode and split in this thread to avoid blocking the main thread
            decoded = Buffer.decode_text(send_bytes)
            parts = decoded.split("\n", -1)
            head = parts.shift || ""
            @stream_event_queue << { type: :file_lines, buffer_id: buffer_id, head: head, lines: parts, loaded_bytes: loaded_bytes, file_size: file_size }
            notify_signal_wakeup
          end
        rescue EOFError
          unless pending_bytes.empty?
            decoded = Buffer.decode_text(pending_bytes)
            parts = decoded.split("\n", -1)
            head = parts.shift || ""
            @stream_event_queue << { type: :file_lines, buffer_id: buffer_id, head: head, lines: parts }
            notify_signal_wakeup
          end
          @stream_event_queue << { type: :file_eof, buffer_id: buffer_id, ended_with_newline: ended_with_newline }
          notify_signal_wakeup
        rescue StandardError => e
          @stream_event_queue << { type: :file_error, buffer_id: buffer_id, error: e.message.to_s }
          notify_signal_wakeup
        ensure
          begin
            io.close unless io.closed?
          rescue StandardError
            nil
          end
        end
      end

      def shutdown_buffer_streams!
        @editor.buffers.each_value do |buf|
          thread = buf.stream_thread
          buf.stream_thread = nil
          io = buf.stream_io
          buf.stream_io = nil
          begin
            io.close if io && !io.closed?
          rescue StandardError
            nil
          end
          next unless thread&.alive?
          thread.kill
          thread.join(0.05)
        rescue StandardError
          nil
        end
      end

      def shutdown_follow_watchers!
        @editor.buffers.each_value do |buf|
          watcher = buf.stream_watcher
          next unless watcher
          buf.stream_watcher = nil
          watcher.stop
        rescue StandardError
          nil
        end
      end

      def shutdown_async_file_loaders!
        loaders = @async_file_loads
        @async_file_loads = {}
        loaders.each_value do |state|
          io = state[:io]
          thread = state[:thread]
          begin
            io.close if io && !io.closed?
          rescue StandardError
            nil
          end
          next unless thread&.alive?

          thread.kill
          thread.join(0.05)
        rescue StandardError
          nil
        end
      end

      def notify_signal_wakeup
        @signal_w.write_nonblock(".")
      rescue IO::WaitWritable, Errno::EPIPE
        nil
      end
  end
end
