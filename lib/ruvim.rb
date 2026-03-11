# frozen_string_literal: true

require "singleton"

module RuVim
  class Error < StandardError; end
  class CommandError < Error; end
end

require_relative "ruvim/version"
require_relative "ruvim/app"
require_relative "ruvim/cli"
