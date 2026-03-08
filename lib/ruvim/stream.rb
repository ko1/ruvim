# frozen_string_literal: true

module RuVim
  class Stream
    attr_accessor :state
    attr_reader :stop_handler

    def initialize(stop_handler: nil)
      @state = nil
      @stop_handler = stop_handler
    end

    def live?
      @state == :live
    end

    def status
      nil
    end

    def command
      nil
    end

    def stop!
      # subclasses override
    end
  end
end

require_relative "stream/stdin"
require_relative "stream/run"
require_relative "stream/follow"
require_relative "stream/file_load"
require_relative "stream/git"
