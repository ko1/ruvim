# frozen_string_literal: true

module RuVim
  module Commands
    module Git
      module Log
        # Command handler methods
        module HandlerMethods
          def git_log(ctx, argv: [], **)
            file_path = git_resolve_path(ctx)
            unless file_path
              ctx.editor.echo_error("No file or directory to resolve git repo")
              return
            end

            root, err = Git.repo_root(file_path)
            unless root
              ctx.editor.echo_error("git log: #{err}")
              return
            end

            filetype = argv.include?("-p") ? "diff" : nil
            buf = ctx.editor.add_virtual_buffer(
              kind: :git_log,
              name: "[Git Log]",
              lines: [""],
              filetype: filetype,
              readonly: true,
              modifiable: false
            )
            buf.options["git_repo_root"] = root
            ctx.editor.switch_to_buffer(buf.id)
            bind_git_buffer_keys(ctx.editor, buf.id)
            ctx.editor.echo("[Git Log] loading...")

            cmd = ["git", "log", *argv]
            ctx.editor.start_stream!(buf, cmd, chdir: root)
          end
        end
      end
    end
  end
end
