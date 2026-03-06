# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Log
      module_function

      # Run git log with optional extra args.
      # Returns [lines, root, error_message].
      def run(file_path, args: [])
        root, err = Git.repo_root(file_path)
        return [nil, nil, err] unless root

        cmd = ["git", "log", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, nil, err.strip]
        end
        [out.lines(chomp: true), root, nil]
      end

      # Command handler methods
      module HandlerMethods
        def git_log(ctx, argv: [], **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, root, err = Log.run(file_path, args: argv)
          unless lines
            ctx.editor.echo_error("git log: #{err}")
            return
          end

          filetype = argv.include?("-p") ? "diff" : nil
          buf = ctx.editor.add_virtual_buffer(
            kind: :git_log,
            name: "[Git Log]",
            lines: lines,
            filetype: filetype,
            readonly: true,
            modifiable: false
          )
          buf.options["git_repo_root"] = root
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Log]")
        end
      end
    end
  end
end
