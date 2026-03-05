# frozen_string_literal: true

require "fiddle/import"

module RuVim
  module FileWatcher
    def self.create(path, &on_change)
      if InotifyWatcher.available? && File.exist?(path)
        InotifyWatcher.new(path, &on_change)
      else
        PollingWatcher.new(path, &on_change)
      end
    end

    class PollingWatcher
      MIN_INTERVAL = 0.1
      MAX_INTERVAL = 3.0
      BACKOFF_FACTOR = 1.5

      attr_reader :current_interval

      def initialize(path, &on_change)
        @path = path
        @on_change = on_change
        @offset = File.exist?(path) ? File.size(path) : 0
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
        unless File.exist?(@path)
          @current_interval = [@current_interval * BACKOFF_FACTOR, MAX_INTERVAL].min
          return
        end

        current_size = File.size(@path)
        if current_size > @offset
          data = File.binread(@path, current_size - @offset, @offset)
          @offset = current_size
          @current_interval = MIN_INTERVAL
          @on_change.call(RuVim::Buffer.decode_text(data)) if data && !data.empty?
        elsif current_size < @offset
          @offset = current_size
          @current_interval = MIN_INTERVAL
        else
          @current_interval = [@current_interval * BACKOFF_FACTOR, MAX_INTERVAL].min
        end
      end
    end

    class InotifyWatcher
      IN_MODIFY = 0x00000002

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

      def initialize(path, &on_change)
        raise ArgumentError, "File does not exist: #{path}" unless File.exist?(path)

        @path = path
        @on_change = on_change
        @offset = File.size(path)
        @thread = nil
        @stop = false
        @inotify_io = nil
        @watch_descriptor = nil
      end

      def start
        @stop = false
        mod = self.class.inotify_module
        fd = mod.inotify_init
        raise "inotify_init failed" if fd < 0

        @inotify_io = IO.new(fd)
        @watch_descriptor = mod.inotify_add_watch(fd, @path, IN_MODIFY)
        raise "inotify_add_watch failed" if @watch_descriptor < 0

        @thread = Thread.new { watch_loop }
      end

      def stop
        @stop = true
        if @watch_descriptor && @inotify_io && !@inotify_io.closed?
          begin
            self.class.inotify_module.inotify_rm_watch(@inotify_io.fileno, @watch_descriptor)
          rescue StandardError
            nil
          end
        end
        begin
          @inotify_io&.close unless @inotify_io&.closed?
        rescue StandardError
          nil
        end
        @thread&.join(0.5)
        @thread = nil
      end

      def alive?
        @thread&.alive? || false
      end

      private

      def watch_loop
        until @stop
          ready = IO.select([@inotify_io], nil, nil, 1.0)
          next unless ready

          begin
            @inotify_io.read_nonblock(4096)
          rescue IO::WaitReadable
            next
          end

          read_new_data
        end
      rescue IOError, Errno::EBADF
        nil
      end

      def read_new_data
        return unless File.exist?(@path)

        current_size = File.size(@path)
        if current_size > @offset
          data = File.binread(@path, current_size - @offset, @offset)
          @offset = current_size
          @on_change.call(RuVim::Buffer.decode_text(data)) if data && !data.empty?
        elsif current_size < @offset
          @offset = current_size
        end
      end
    end
  end
end
