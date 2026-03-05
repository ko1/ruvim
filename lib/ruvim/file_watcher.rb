# frozen_string_literal: true

require "fiddle/import"

module RuVim
  module FileWatcher
    def self.create(path, &on_event)
      if InotifyWatcher.available? && File.exist?(path)
        InotifyWatcher.new(path, &on_event)
      else
        PollingWatcher.new(path, &on_event)
      end
    end

    class PollingWatcher
      MIN_INTERVAL = 0.1
      MAX_INTERVAL = 3.0
      BACKOFF_FACTOR = 1.5

      attr_reader :current_interval

      def backend = :polling

      def initialize(path, &on_event)
        @path = path
        @on_event = on_event
        @offset = File.exist?(path) ? File.size(path) : 0
        @file_existed = File.exist?(path)
        @current_interval = MIN_INTERVAL
        @thread = nil
        @stop = false
      end

      def start
        @stop = false
        @thread = Thread.new { poll_loop }
      end

      def stop
        @stop = true
        @thread&.kill
        @thread&.join(0.5)
        @thread = nil
      end

      def alive?
        @thread&.alive? || false
      end

      private

      def poll_loop
        until @stop
          sleep @current_interval
          check_file
        end
      rescue StandardError
        nil
      end

      def check_file
        exists = File.exist?(@path)

        if !exists
          if @file_existed
            @file_existed = false
            @offset = 0
            @on_event.call(:deleted, nil)
          end
          @current_interval = [@current_interval * BACKOFF_FACTOR, MAX_INTERVAL].min
          return
        end

        @file_existed = true
        current_size = File.size(@path)
        if current_size > @offset
          data = File.binread(@path, current_size - @offset, @offset)
          @offset = current_size
          @current_interval = MIN_INTERVAL
          @on_event.call(:data, RuVim::Buffer.decode_text(data)) if data && !data.empty?
        elsif current_size < @offset
          @offset = current_size
          @current_interval = MIN_INTERVAL
          @on_event.call(:truncated, nil)
        else
          @current_interval = [@current_interval * BACKOFF_FACTOR, MAX_INTERVAL].min
        end
      end
    end

    class InotifyWatcher
      IN_MODIFY = 0x00000002
      IN_DELETE_SELF = 0x00000400

      def backend = :inotify

      def self.available?
        return @available unless @available.nil?
        @available = begin
          require "fiddle/import"
          _mod = inotify_module
          true
        rescue LoadError, Fiddle::DLError, StandardError
          false
        end
      end

      def self.inotify_module
        @inotify_module ||= begin
          mod = Module.new do
            extend Fiddle::Importer
            dlload "libc.so.6"
            extern "int inotify_init()"
            extern "int inotify_add_watch(int, const char*, unsigned int)"
            extern "int inotify_rm_watch(int, int)"
          end
          mod
        end
      end

      def initialize(path, &on_event)
        raise ArgumentError, "File does not exist: #{path}" unless File.exist?(path)

        @path = path
        @on_event = on_event
        @offset = File.size(path)
        @thread = nil
        @stop = false
        @inotify_io = nil
        @watch_descriptor = nil
      end

      def start
        @stop = false
        setup_inotify!
        @thread = Thread.new { watch_loop }
      end

      def stop
        @stop = true
        cleanup_inotify!
        @thread&.join(0.5)
        @thread = nil
      end

      def alive?
        @thread&.alive? || false
      end

      private

      def setup_inotify!
        cleanup_inotify!
        mod = self.class.inotify_module
        fd = mod.inotify_init
        raise "inotify_init failed" if fd < 0

        @inotify_io = IO.new(fd)
        @watch_descriptor = mod.inotify_add_watch(fd, @path, IN_MODIFY | IN_DELETE_SELF)
        raise "inotify_add_watch failed" if @watch_descriptor < 0
      end

      def cleanup_inotify!
        if @watch_descriptor && @inotify_io && !@inotify_io.closed?
          begin
            self.class.inotify_module.inotify_rm_watch(@inotify_io.fileno, @watch_descriptor)
          rescue StandardError
            nil
          end
        end
        @watch_descriptor = nil
        begin
          @inotify_io&.close unless @inotify_io&.closed?
        rescue StandardError
          nil
        end
        @inotify_io = nil
      end

      def watch_loop
        until @stop
          ready = IO.select([@inotify_io], nil, nil, 1.0)
          next unless ready

          begin
            event_data = @inotify_io.read_nonblock(4096)
          rescue IO::WaitReadable
            next
          end

          if file_deleted_event?(event_data)
            @offset = 0
            @on_event.call(:deleted, nil)
            wait_for_file_and_rewatch!
            next
          end

          read_new_data
        end
      rescue IOError, Errno::EBADF
        nil
      end

      def file_deleted_event?(event_data)
        return false unless event_data && event_data.bytesize >= 8

        # inotify_event struct: int wd, uint32_t mask, uint32_t cookie, uint32_t len, char name[]
        # mask is at offset 4, 4 bytes little-endian
        mask = event_data.byteslice(4, 4).unpack1("V")
        (mask & IN_DELETE_SELF) != 0
      end

      def wait_for_file_and_rewatch!
        cleanup_inotify!
        interval = PollingWatcher::MIN_INTERVAL
        until @stop
          sleep interval
          if File.exist?(@path)
            @offset = 0
            setup_inotify!
            return
          end
          interval = [interval * PollingWatcher::BACKOFF_FACTOR, PollingWatcher::MAX_INTERVAL].min
        end
      rescue StandardError
        nil
      end

      def read_new_data
        return unless File.exist?(@path)

        current_size = File.size(@path)
        if current_size > @offset
          data = File.binread(@path, current_size - @offset, @offset)
          @offset = current_size
          @on_event.call(:data, RuVim::Buffer.decode_text(data)) if data && !data.empty?
        elsif current_size < @offset
          @offset = current_size
          @on_event.call(:truncated, nil)
        end
      end
    end
  end
end
