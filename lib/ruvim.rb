require "singleton"

module RuVim
  class Error < StandardError; end
  class CommandError < Error; end
end

require_relative "ruvim/version"
require_relative "ruvim/command_invocation"
require_relative "ruvim/display_width"
require_relative "ruvim/keyword_chars"
require_relative "ruvim/text_metrics"
require_relative "ruvim/clipboard"
require_relative "ruvim/highlighter"
require_relative "ruvim/context"
require_relative "ruvim/buffer"
require_relative "ruvim/window"
require_relative "ruvim/editor"
require_relative "ruvim/command_registry"
require_relative "ruvim/ex_command_registry"
require_relative "ruvim/global_commands"
require_relative "ruvim/dispatcher"
require_relative "ruvim/keymap_manager"
require_relative "ruvim/command_line"
require_relative "ruvim/input"
require_relative "ruvim/terminal"
require_relative "ruvim/screen"
require_relative "ruvim/config_dsl"
require_relative "ruvim/config_loader"
require_relative "ruvim/app"
require_relative "ruvim/cli"
