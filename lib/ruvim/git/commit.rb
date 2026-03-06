# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Commit
      module_function

      # Build the initial content for the commit message buffer.
      # Returns [lines, root, error_message].
      def prepare(file_path)
        root, err = Git.repo_root(file_path)
        return [nil, nil, err] unless root

        status_out, err, status = Open3.capture3("git", "status", chdir: root)
        unless status.success?
          return [nil, nil, err.strip]
        end

        lines = [""]
        lines << "# Enter commit message above. Lines starting with '#' are ignored."
        lines << "# Close with :wq to commit, :q! to cancel."
        lines << "#"
        status_out.each_line(chomp: true) { |l| lines << "# #{l}" }
        [lines, root, nil]
      end

      # Extract commit message from buffer lines (skip # comment lines and trim).
      def extract_message(lines)
        msg_lines = lines.reject { |l| l.start_with?("#") }
        # Strip trailing blank lines
        msg_lines.pop while msg_lines.last&.empty?
        msg_lines.join("\n")
      end

      # Execute git commit with the given message.
      # Returns [success, output_or_error].
      def execute(root, message)
        out, err, status = Open3.capture3("git", "commit", "-m", message, chdir: root)
        if status.success?
          [true, out.strip]
        else
          [false, err.strip]
        end
      end

      # Command handler methods
      module HandlerMethods
        def git_commit(ctx, **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, root, err = Commit.prepare(file_path)
          unless lines
            ctx.editor.echo_error("git commit: #{err}")
            return
          end

          buf = ctx.editor.add_virtual_buffer(
            kind: :git_commit,
            name: "[Commit Message]",
            lines: lines,
            readonly: false,
            modifiable: true
          )
          buf.options["git_repo_root"] = root
          ctx.editor.switch_to_buffer(buf.id)
          ctx.editor.enter_insert_mode
          ctx.editor.echo("[Commit Message] :wq to commit, :q! to cancel")
        end

        def git_commit_execute(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :git_commit
            ctx.editor.echo_error("Not a git commit buffer")
            return
          end

          message = Commit.extract_message(buf.lines)
          if message.empty?
            ctx.editor.echo_error("Empty commit message, aborting")
            return
          end

          root = buf.options["git_repo_root"]
          success, output = Commit.execute(root, message)
          ctx.editor.delete_buffer(buf.id)

          if success
            ctx.editor.echo(output)
          else
            ctx.editor.echo_error("git commit: #{output}")
          end
        end
      end
    end
  end
end
