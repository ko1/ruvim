# frozen_string_literal: true

module RuVim
  class Stream::Follow < Stream
    attr_accessor :watcher, :backend

    def initialize
      super()
      @watcher = nil
      @backend = nil
    end

    def status
      case @state
      when :live
        @backend == :inotify ? "follow/i" : "follow"
      when :error then "follow/error"
      end
    end

    def start!(buffer_id:, path:, queue:, &notify)
      @state = :live
      @watcher = FileWatcher.create(path) do |type, data|
        case type
        when :data
          queue << { type: :follow_data, buffer_id: buffer_id, data: data }
        when :truncated
          queue << { type: :follow_truncated, buffer_id: buffer_id }
        when :deleted
          queue << { type: :follow_deleted, buffer_id: buffer_id }
        end
        notify.call
      end
      @backend = @watcher.backend
      @watcher.start
    end

    def stop!
      watcher = @watcher; @watcher = nil
      watcher&.stop
      @backend = nil
      @state = nil
    end
  end
end
