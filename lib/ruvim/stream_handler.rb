# frozen_string_literal: true

module RuVim
  class StreamHandler
      LARGE_FILE_ASYNC_THRESHOLD_BYTES = 64 * 1024 * 1024
      LARGE_FILE_STAGED_PREFIX_BYTES = 8 * 1024 * 1024
      ASYNC_FILE_READ_CHUNK_BYTES = 1 * 1024 * 1024
      ASYNC_FILE_EVENT_FLUSH_BYTES = 4 * 1024 * 1024

      attr_reader :follow_watchers

      def initialize(editor:, signal_w:)
        @editor = editor
        @signal_w = signal_w
        @stream_event_queue = nil
        @stream_reader_thread = nil
        @stream_buffer_id = nil
        @stream_stop_requested = false
        @async_file_loads = {}
        @follow_watchers = {}
        @git_stream_ios = nil
        @git_stream_threads = nil
        @stdin_stream_source = nil
      end

      def stdin_stream_source=(io)
        @stdin_stream_source = io
      end

      def stream_buffer_id
        @stream_buffer_id
      end

      def prepare_stdin_stream_buffer!
        buf = @editor.current_buffer
        if buf.intro_buffer?
          @editor.materialize_intro_buffer!
          buf = @editor.current_buffer
        end

        buf.replace_all_lines!([""])
        buf.configure_special!(kind: :stream, name: "[stdin]", readonly: true, modifiable: false)
        buf.modified = false
        buf.stream_state = :live
        buf.options["filetype"] = "text"
        @stream_stop_requested = false
        ensure_event_queue!
        @stream_buffer_id = buf.id
        move_window_to_stream_end!(@editor.current_window, buf)
        @editor.echo("[stdin] follow")
      end

      def start_stdin_stream_reader!
        return unless @stdin_stream_source
        ensure_event_queue!
        return if @stream_reader_thread&.alive?

        @stream_stop_requested = false
        io = @stdin_stream_source
        @stream_reader_thread = Thread.new do
          loop do
            chunk = io.readpartial(4096)
            next if chunk.nil? || chunk.empty?

            @stream_event_queue << { type: :data, data: Buffer.decode_text(chunk) }
            notify_signal_wakeup
          end
        rescue EOFError
          unless @stream_stop_requested
            @stream_event_queue << { type: :eof }
            notify_signal_wakeup
          end
        rescue IOError => e
          unless @stream_stop_requested
            @stream_event_queue << { type: :error, error: e.message.to_s }
            notify_signal_wakeup
          end
        rescue StandardError => e
          unless @stream_stop_requested
            @stream_event_queue << { type: :error, error: e.message.to_s }
            notify_signal_wakeup
          end
        end
      end

      def stop_stdin_stream!
        buf = @editor.buffers[@stream_buffer_id]
        return false unless buf&.kind == :stream
        return false unless (buf.stream_state || :live) == :live

        @stream_stop_requested = true
        io = @stdin_stream_source
        @stdin_stream_source = nil
        begin
          io.close if io && io.respond_to?(:close) && !(io.respond_to?(:closed?) && io.closed?)
        rescue StandardError
          nil
        end
        if @stream_reader_thread&.alive?
          @stream_reader_thread.kill
          @stream_reader_thread.join(0.05)
        end
        @stream_reader_thread = nil

        buf.stream_state = :closed
        @editor.echo("[stdin] closed")
        notify_signal_wakeup
        true
      end

      def drain_events!
        return false unless @stream_event_queue

        changed = false
        loop do
          event = @stream_event_queue.pop(true)
          case event[:type]
          when :data
            changed = apply_stream_chunk!(event[:data]) || changed
          when :eof
            if (buf = @editor.buffers[@stream_buffer_id])
              buf.stream_state = :closed
            end
            @editor.echo("[stdin] EOF")
            changed = true
          when :error
            next if ignore_stream_shutdown_error?(event[:error])
            if (buf = @editor.buffers[@stream_buffer_id])
              buf.stream_state = :error
            end
            @editor.echo_error("[stdin] stream error: #{event[:error]}")
            changed = true
          when :follow_data
            changed = apply_follow_chunk!(event[:buffer_id], event[:data]) || changed
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
          when :git_cmd_data
            changed = apply_git_stream_chunk!(event[:buffer_id], event[:data]) || changed
          when :git_cmd_eof
            changed = finish_git_stream!(event[:buffer_id]) || changed
          when :git_cmd_error
            changed = fail_git_stream!(event[:buffer_id], event[:error]) || changed
          when :run_cmd_data
            changed = apply_run_stream_chunk!(event[:buffer_id], event[:data]) || changed
          when :run_cmd_eof
            changed = finish_run_stream!(event[:buffer_id], event[:status]) || changed
          when :run_cmd_error
            changed = fail_run_stream!(event[:buffer_id], event[:error]) || changed
          end
        end
      rescue ThreadError
        changed
      end

      def ex_follow_toggle
        buf = @editor.current_buffer
        raise RuVim::CommandError, "No file associated with buffer" unless buf.path

        if @follow_watchers[buf.id]
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
        @follow_watchers[buf.id] = watcher
        buf.stream_state = :live
        buf.follow_backend = watcher.backend
        @editor.echo("[follow] #{buf.display_name}")
      end

      def stop_follow!(buf)
        watcher = @follow_watchers.delete(buf.id)
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

      def open_path_with_large_file_support(path)
        return @editor.open_path_sync(path) unless should_open_path_async?(path)
        return @editor.open_path_sync(path) unless can_start_async_file_load?

        open_path_asynchronously!(path)
      end

      def start_run_stream_command(buffer_id, command)
        ensure_event_queue!
        shell = ENV["SHELL"].to_s
        shell = "/bin/sh" if shell.empty?
        queue = @stream_event_queue
        @run_stream_thread = Thread.new do
          IO.popen([shell, "-c", command], err: [:child, :out]) do |io|
            @run_stream_io = io
            while (chunk = io.read(4096))
              queue << { type: :run_cmd_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
              notify_signal_wakeup
            end
          end
          @run_stream_io = nil
          queue << { type: :run_cmd_eof, buffer_id: buffer_id, status: $? }
          notify_signal_wakeup
        rescue StandardError => e
          @run_stream_io = nil
          queue << { type: :run_cmd_error, buffer_id: buffer_id, error: e.message.to_s }
          notify_signal_wakeup
        end
      end

      def stop_run_stream!
        io = @run_stream_io
        @run_stream_io = nil
        if io
          begin
            io.close unless io.closed?
          rescue IOError
            nil
          end
        end
        thread = @run_stream_thread
        @run_stream_thread = nil
        if thread&.alive?
          thread.kill
          thread.join(0.05)
        end
        buf_id = @editor.run_output_buffer_id
        buf = @editor.buffers[buf_id] if buf_id
        if buf && buf.stream_state == :live
          buf.stream_state = :closed
          @editor.echo("[Shell Output] stopped")
          return true
        end
        false
      end

      def run_stream_active?
        @run_stream_thread&.alive? || false
      end

      def start_git_stream_command(buffer_id, cmd, root)
        ensure_event_queue!
        @git_stream_ios ||= {}
        @git_stream_threads ||= {}
        queue = @stream_event_queue
        ios = @git_stream_ios
        @git_stream_threads[buffer_id] = Thread.new do
          IO.popen(cmd, chdir: root, err: [:child, :out]) do |io|
            ios[buffer_id] = io
            while (chunk = io.read(4096))
              queue << { type: :git_cmd_data, buffer_id: buffer_id, data: Buffer.decode_text(chunk) }
              notify_signal_wakeup
            end
          end
          ios.delete(buffer_id)
          queue << { type: :git_cmd_eof, buffer_id: buffer_id }
          notify_signal_wakeup
        rescue StandardError => e
          ios.delete(buffer_id)
          queue << { type: :git_cmd_error, buffer_id: buffer_id, error: e.message.to_s }
          notify_signal_wakeup
        end
      end

      def stop_git_stream!(buffer_id)
        io = @git_stream_ios&.delete(buffer_id)
        io&.close
      rescue IOError
        # already closed
      end

      def shutdown!
        shutdown_stream_reader!
        shutdown_follow_watchers!
        shutdown_async_file_loaders!
      end

      def ensure_event_queue!
        @stream_event_queue ||= Queue.new
      end

      private

      def apply_stream_chunk!(text)
        return false if text.to_s.empty?

        buf = @editor.buffers[@stream_buffer_id]
        return false unless buf

        follow_window_ids = @editor.windows.values.filter_map do |win|
          next unless win.buffer_id == buf.id
          next unless stream_window_following_end?(win, buf)

          win.id
        end

        buf.append_stream_text!(text)

        follow_window_ids.each do |win_id|
          win = @editor.windows[win_id]
          move_window_to_stream_end!(win, buf) if win
        end

        true
      end

      def apply_async_file_lines!(buffer_id, head, lines, loaded_bytes: nil, file_size: nil)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        # If follow mode is active, track windows at the end before appending
        following_win_ids = if @follow_watchers[buffer_id]
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

      def apply_follow_chunk!(buffer_id, text)
        return false if text.to_s.empty?

        buf = @editor.buffers[buffer_id]
        return false unless buf

        follow_window_ids = @editor.windows.values.filter_map do |win|
          next unless win.buffer_id == buf.id
          next unless stream_window_following_end?(win, buf)

          win.id
        end

        buf.append_stream_text!(text)

        follow_window_ids.each do |win_id|
          win = @editor.windows[win_id]
          move_window_to_stream_end!(win, buf) if win
        end

        true
      end

      def apply_run_stream_chunk!(buffer_id, text)
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

      def finish_run_stream!(buffer_id, status)
        @run_stream_thread = nil
        @run_stream_io = nil
        buf = @editor.buffers[buffer_id]
        return false unless buf

        # Remove trailing empty line if present
        if buf.lines.length > 1 && buf.lines[-1] == ""
          buf.lines.pop
        end
        buf.stream_state = :closed
        exitstatus = status&.exitstatus
        @editor.echo("[Shell Output] exit #{exitstatus}")
        true
      end

      def fail_run_stream!(buffer_id, error)
        @run_stream_thread = nil
        @run_stream_io = nil
        buf = @editor.buffers[buffer_id]
        @editor.echo_error("[Shell Output] error: #{error}") if buf
        buf&.stream_state = :closed if buf
        true
      end

      def apply_git_stream_chunk!(buffer_id, text)
        return false if text.to_s.empty?

        buf = @editor.buffers[buffer_id]
        return false unless buf

        buf.append_stream_text!(text)
        true
      end

      def finish_git_stream!(buffer_id)
        @git_stream_ios&.delete(buffer_id)
        @git_stream_threads&.delete(buffer_id)
        buf = @editor.buffers[buffer_id]
        return false unless buf

        # Remove trailing empty line if present
        if buf.lines.length > 1 && buf.lines[-1] == ""
          buf.lines.pop
        end
        line_count = buf.line_count
        @editor.echo("#{buf.name} #{line_count} lines")
        true
      end

      def fail_git_stream!(buffer_id, error)
        @git_stream_ios&.delete(buffer_id)
        @git_stream_threads&.delete(buffer_id)
        buf = @editor.buffers[buffer_id]
        @editor.echo_error("git stream error: #{error}") if buf
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

      def ignore_stream_shutdown_error?(message)
        buf = @editor.buffers[@stream_buffer_id]
        return false unless buf&.kind == :stream
        return false unless (buf.stream_state || :live) == :closed

        msg = message.to_s.downcase
        msg.include?("stream closed") || msg.include?("closed in another thread")
      end

      def shutdown_stream_reader!
        thread = @stream_reader_thread
        @stream_reader_thread = nil
        @stream_stop_requested = true
        return unless thread
        return unless thread.alive?

        thread.kill
        thread.join(0.05)
      rescue StandardError
        nil
      end

      def shutdown_follow_watchers!
        watchers = @follow_watchers
        @follow_watchers = {}
        watchers.each_value do |watcher|
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
