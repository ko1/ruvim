# frozen_string_literal: true

module RuVim
  class Stream
    attr_accessor :state, :exit_status, :command, :stop_handler,
                  :thread, :io, :pid, :watcher, :follow_backend

    def initialize
      @state = nil
    end

    def status(kind)
      return nil unless @state

      source = case kind
               when :stream then "stdin"
               when :run_output then "run"
               else @follow_backend == :inotify ? "follow/i" : "follow"
               end

      case @state
      when :live
        source
      when :closed
        suffix = case kind
                 when :stream then "EOF"
                 when :run_output
                   code = @exit_status&.exitstatus
                   code ? "exit #{code}" : "EOF"
                 end
        suffix ? "#{source}/#{suffix}" : nil
      when :error
        "#{source}/error"
      end
    end

    def live?
      @state == :live
    end

    def reset!
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
