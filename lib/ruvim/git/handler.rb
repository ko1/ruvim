# frozen_string_literal: true

module RuVim
  module Git
    module Handler
      GIT_SUBCOMMANDS = {
        "blame"       => :git_blame,
        "blameprev"   => :git_blame_prev,
        "blameback"   => :git_blame_back,
        "blamecommit" => :git_blame_commit,
        "status"      => :git_status,
        "diff"        => :git_diff,
        "log"         => :git_log,
      }.freeze

      include Blame::HandlerMethods
      include Commands::HandlerMethods

      def enter_git_command_mode(ctx, **)
        ctx.editor.enter_command_line_mode(":")
        ctx.editor.command_line.replace_text("git ")
        ctx.editor.clear_message
      end

      def ex_git(ctx, argv: [], **)
        sub = argv.first.to_s.downcase
        if sub.empty?
          ctx.editor.echo("Git subcommands: #{GIT_SUBCOMMANDS.keys.join(', ')}")
          return
        end

        method = GIT_SUBCOMMANDS[sub]
        unless method
          ctx.editor.echo_error("Unknown Git subcommand: #{sub}")
          return
        end

        public_send(method, ctx, argv: argv[1..], kwargs: {}, bang: false, count: 1)
      end

      def git_close_buffer(ctx, **)
        ctx.editor.delete_buffer(ctx.buffer.id)
      end

      private

      def git_resolve_path(ctx)
        path = ctx.buffer.path
        return path if path && File.exist?(path)
        dir = Dir.pwd
        File.directory?(dir) ? dir : nil
      end

      def bind_git_buffer_keys(editor, buffer_id)
        km = editor.keymap_manager
        km.bind_buffer(buffer_id, "\e", "git.close_buffer")
        km.bind_buffer(buffer_id, "<C-c>", "git.close_buffer")
      end
    end
  end
end
