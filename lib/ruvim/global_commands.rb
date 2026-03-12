# frozen_string_literal: true

require "tempfile"
require "open3"

require_relative "commands/motion"
require_relative "commands/edit"
require_relative "commands/register"
require_relative "commands/search"
require_relative "commands/window"
require_relative "commands/buffer"
require_relative "commands/meta"

module RuVim
  module Commands
    autoload :Git, File.expand_path("commands/git/handler", __dir__)
    autoload :Gh, File.expand_path("commands/gh", __dir__)
  end

  class GlobalCommands
    include Singleton
    include Commands::Motion
    include Commands::Edit
    include Commands::Register
    include Commands::Search
    include Commands::Window
    include Commands::Buffer
    include Commands::Meta
    def call(spec_call, ctx, argv: [], kwargs: {}, bang: false, count: nil)
      case spec_call
      when Symbol, String
        public_send(spec_call.to_sym, ctx, argv: argv, kwargs: kwargs, bang: bang, count: count)
      else
        spec_call.call(ctx, argv: argv, kwargs: kwargs, bang: bang, count: count)
      end
    end

    def self.parse_path_with_location(str)
      raw = str.to_s.sub(/:\s*\z/, "")
      # Try path:line:col
      if (m = /\A(.+):(\d+):(\d+)\z/.match(raw))
        path = m[1]
        return { path: path, line: m[2].to_i, col: m[3].to_i } if !path.end_with?(":") && File.exist?(path)
      end
      # Try path:line
      if (m = /\A(.+):(\d+)\z/.match(raw))
        path = m[1]
        return { path: path, line: m[2].to_i, col: nil } if !path.end_with?(":") && File.exist?(path)
      end
      { path: raw, line: nil, col: nil }
    end

    private

    def normalized_count(count, default: 1)
      n = count.nil? ? default : count.to_i
      n = default if n <= 0
      n
    end

    def record_jump(ctx)
      ctx.editor.push_jump_location(ctx.editor.current_location)
    end

    def materialize_intro_buffer_if_needed(ctx)
      ctx.editor.materialize_intro_buffer!
      nil
    end

    def ensure_modifiable_for_insert!(ctx)
      raise RuVim::CommandError, "Buffer is not modifiable" unless ctx.buffer.modifiable?
    end

    def maybe_autowrite_before_switch(ctx)
      return false unless ctx.editor.effective_option("autowrite", window: ctx.window, buffer: ctx.buffer)
      return false unless ctx.buffer.file_buffer?
      return false unless ctx.buffer.path && !ctx.buffer.path.empty?

      ctx.buffer.write_to(ctx.buffer.path)
      true
    rescue StandardError
      false
    end

    GIT_METHOD_PREFIX = /\Agit_|enter_git_/
    GH_METHOD_PREFIX = /\Agh_/

    def self.load_git_handler!
      return if @git_handler_loaded
      @git_handler_loaded = true
      require_relative "commands/git/handler"
      include Commands::Git::Handler
    end

    def self.load_gh_handler!
      return if @gh_handler_loaded
      @gh_handler_loaded = true
      require_relative "commands/gh"
      include Commands::Gh::Handler
    end

    def method_missing(name, *args, **kw, &block)
      case name
      when GIT_METHOD_PREFIX
        self.class.load_git_handler!
        return send(name, *args, **kw, &block) if respond_to?(name)
      when GH_METHOD_PREFIX
        self.class.load_gh_handler!
        return send(name, *args, **kw, &block) if respond_to?(name)
      end
      super
    end

    def respond_to_missing?(name, include_private = false)
      case name
      when GIT_METHOD_PREFIX, GH_METHOD_PREFIX
        true
      else
        super
      end
    end
  end
end
