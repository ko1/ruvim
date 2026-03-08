# frozen_string_literal: true

module RuVim
  class Stream
    attr_accessor :source, :state, :exit_status, :command, :stop_handler,
                  :thread, :io, :pid, :watcher, :follow_backend

    def initialize
      @source = nil
      @state = nil
    end

    def status
      return nil unless @state

      label = case @source
              when :stdin then "stdin"
              when :run then "run"
              when :follow
                @follow_backend == :inotify ? "follow/i" : "follow"
              when :file_load then "load"
              end
      return nil unless label

      case @state
      when :live
        label
      when :closed
        suffix = case @source
                 when :stdin then "EOF"
                 when :run
                   code = @exit_status&.exitstatus
                   code ? "exit #{code}" : "EOF"
                 end
        suffix ? "#{label}/#{suffix}" : nil
      when :error
        "#{label}/error"
      end
    end

    def live?
      @state == :live
    end

    def reset!
      @source = nil
      @state = nil
      @exit_status = nil
      @command = nil
      @stop_handler = nil
      @thread = nil
      @io = nil
      @pid = nil
      @watcher = nil
      @follow_backend = nil
    end
  end
end
