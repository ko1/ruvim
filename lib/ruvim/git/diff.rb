# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Diff
      module_function

      # Run git diff with optional extra args.
      # Returns [lines, error_message].
      def run(file_path, args: [])
        root, err = Git.repo_root(file_path)
        return [nil, err] unless root

        cmd = ["git", "diff", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Command handler methods
      module HandlerMethods
        def git_diff(ctx, argv: [], **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, err = Diff.run(file_path, args: argv)
          unless lines
            ctx.editor.echo_error("git diff: #{err}")
            return
          end

          if lines.empty?
            ctx.editor.echo("No diff output (working tree clean)")
            return
          end

          buf = ctx.editor.add_virtual_buffer(
            kind: :git_diff,
            name: "[Git Diff]",
            lines: lines,
            filetype: "diff",
            readonly: true,
            modifiable: false
          )
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Diff]")
        end
      end
    end
  end
end
