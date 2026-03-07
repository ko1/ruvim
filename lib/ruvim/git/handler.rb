# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module_function

    # Find git repository root from a file path.
    # Returns [root_path, error_message].
    def repo_root(file_path)
      dir = File.directory?(file_path) ? file_path : File.dirname(file_path)
      out, err, status = Open3.capture3("git", "rev-parse", "--show-toplevel", chdir: dir)
      unless status.success?
        return [nil, err.strip]
      end
      [out.strip, nil]
    end

    module Handler
      GIT_SUBCOMMANDS = {
        "blame"       => :git_blame,
        "blameprev"   => :git_blame_prev,
        "blameback"   => :git_blame_back,
        "blamecommit" => :git_blame_commit,
        "status"      => :git_status,
        "diff"        => :git_diff,
        "log"         => :git_log,
        "branch"      => :git_branch,
        "commit"      => :git_commit,
      }.freeze

      include Blame::HandlerMethods
      include Status::HandlerMethods
      include Diff::HandlerMethods
      include Log::HandlerMethods
      include Branch::HandlerMethods
      include Commit::HandlerMethods
      include Gh::Link::HandlerMethods

      GH_SUBCOMMANDS = {
        "link"   => :gh_link,
        "browse" => :gh_browse,
        "pr"     => :gh_pr,
      }.freeze

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

      def ex_gh(ctx, argv: [], kwargs: {}, **)
        sub = argv.first.to_s.downcase
        if sub.empty?
          ctx.editor.echo("GitHub subcommands: #{GH_SUBCOMMANDS.keys.join(', ')}")
          return
        end

        method = GH_SUBCOMMANDS[sub]
        unless method
          ctx.editor.echo_error("Unknown GitHub subcommand: #{sub}")
          return
        end

        public_send(method, ctx, argv: argv[1..], kwargs: kwargs, bang: false, count: 1)
      end

      def git_close_buffer(ctx, **)
        buf_id = ctx.buffer.id
        ctx.editor.git_stream_stop_handler&.call(buf_id)
        ctx.editor.delete_buffer(buf_id)
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
