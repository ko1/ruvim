# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Branch
      module_function

      # Run git branch listing sorted by most recent commit.
      # Returns [lines, root, error_message].
      def run(file_path)
        root, err = Git.repo_root(file_path)
        return [nil, nil, err] unless root

        out, err, status = Open3.capture3(
          "git", "branch", "-a",
          "--sort=-committerdate",
          "--format=%(if)%(HEAD)%(then)* %(else)  %(end)%(refname:short)\t%(committerdate:short)\t%(subject)",
          chdir: root
        )
        unless status.success?
          return [nil, nil, err.strip]
        end
        [out.lines(chomp: true), root, nil]
      end

      # Parse branch name from a branch list line.
      # Returns branch name or nil.
      def parse_branch_name(line)
        stripped = line.to_s.strip
        return nil if stripped.empty?

        # Remove leading "* " marker for current branch
        name = stripped.sub(/\A\*\s*/, "")
        # Branch name is everything before the first tab
        name = name.split("\t", 2).first
        name&.strip
      end

      # Command handler methods
      module HandlerMethods
        def git_branch(ctx, **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, root, err = Branch.run(file_path)
          unless lines
            ctx.editor.echo_error("git branch: #{err}")
            return
          end

          buf = ctx.editor.add_virtual_buffer(
            kind: :git_branch,
            name: "[Git Branch]",
            lines: lines,
            readonly: true,
            modifiable: false
          )
          buf.options["git_repo_root"] = root
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Branch]")
        end

        def git_branch_checkout(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :git_branch
            ctx.editor.echo_error("Not a git branch buffer")
            return
          end

          line = buf.line_at(ctx.window.cursor_y)
          branch = Branch.parse_branch_name(line)
          unless branch
            ctx.editor.echo_error("No branch on this line")
            return
          end

          ctx.editor.enter_command_line_mode(":")
          ctx.editor.command_line.replace_text("git checkout #{branch}")
        end

        def git_branch_execute_checkout(ctx, argv: [], **)
          branch = argv.first.to_s.strip
          raise RuVim::CommandError, "Usage: :git checkout <branch>" if branch.empty?

          root = ctx.buffer.kind == :git_branch ? ctx.buffer.options["git_repo_root"] : nil
          unless root
            file_path = git_resolve_path(ctx)
            root, err = Git.repo_root(file_path) if file_path
            raise RuVim::CommandError, "Not in a git repository" unless root
          end

          _out, err, status = Open3.capture3("git", "checkout", branch, chdir: root)
          unless status.success?
            raise RuVim::CommandError, "git checkout: #{err.strip}"
          end

          # Close git branch buffer if we're in one
          if ctx.buffer.kind == :git_branch
            ctx.editor.delete_buffer(ctx.buffer.id)
          end
          ctx.editor.echo("Switched to branch '#{branch}'")
        end
      end
    end
  end
end
