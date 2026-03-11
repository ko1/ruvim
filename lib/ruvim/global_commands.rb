# frozen_string_literal: true

require "tempfile"
require "open3"

require_relative "commands/motion"
require_relative "commands/edit"
require_relative "commands/yank_paste"
require_relative "commands/search"
require_relative "commands/window"
require_relative "commands/buffer_file"
require_relative "commands/ex"

module RuVim
  class GlobalCommands
    include Singleton
    include Commands::Motion
    include Commands::Edit
    include Commands::YankPaste
    include Commands::Search
    include Commands::Window
    include Commands::BufferFile
    include Commands::Ex
    include RuVim::Git::Handler

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
  end
end
