# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Commands
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

      # Run git status.
      # Returns [lines, error_message].
      def status(file_path)
        root, err = repo_root(file_path)
        return [nil, err] unless root

        out, err, status = Open3.capture3("git", "status", chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Run git diff with optional extra args.
      # Returns [lines, error_message].
      def diff(file_path, args: [])
        root, err = repo_root(file_path)
        return [nil, err] unless root

        cmd = ["git", "diff", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Run git log with optional extra args.
      # Returns [lines, error_message].
      def log(file_path, args: [])
        root, err = repo_root(file_path)
        return [nil, err] unless root

        cmd = ["git", "log", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Command handler methods (included via Git::Handler)
      module HandlerMethods
        def git_status(ctx, **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, err = Commands.status(file_path)
          unless lines
            ctx.editor.echo_error("git status: #{err}")
            return
          end

          buf = ctx.editor.add_virtual_buffer(
            kind: :git_status,
            name: "[Git Status]",
            lines: lines,
            readonly: true,
            modifiable: false
          )
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Status]")
        end

        def git_diff(ctx, argv: [], **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, err = Commands.diff(file_path, args: argv)
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

        def git_log(ctx, argv: [], **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, err = Commands.log(file_path, args: argv)
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
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Log]")
        end
      end
    end
  end
end
