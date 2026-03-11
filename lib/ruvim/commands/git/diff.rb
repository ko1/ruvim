# frozen_string_literal: true

require "open3"

module RuVim
  module Commands
    module Git
      module Diff
        module_function

        # Run git diff with optional extra args.
        # Returns [lines, root, error_message].
        def run(file_path, args: [])
          root, err = Git.repo_root(file_path)
          return [nil, nil, err] unless root

          cmd = ["git", "diff", *args]
          out, err, status = Open3.capture3(*cmd, chdir: root)
          unless status.success?
            return [nil, nil, err.strip]
          end
          [out.lines(chomp: true), root, nil]
        end

        # Parse diff output to find file and line number at cursor_y.
        # Returns [filename, line_number] or nil.
        def parse_location(lines, cursor_y)
          return nil if lines.empty? || cursor_y < 0 || cursor_y >= lines.length

          current_file = nil
          new_line = nil

          (0..cursor_y).each do |i|
            l = lines[i]
            case l
            when /\Adiff --git a\/.+ b\/(.+)/
              current_file = $1
            when /\A\+\+\+ b\/(.+)/
              current_file = $1
            when /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/
              new_line = $1.to_i
            when /\A[ +]/
              # Context or added line: current new_line is this line's number
              new_line += 1 if new_line && i < cursor_y
            end
            # Deleted lines ("-") don't advance new_line
          end

          return nil unless current_file

          l = lines[cursor_y]
          case l
          when /\A@@ /
            # On hunk header: new_line already set
          when /\Adiff --git /, /\A---/, /\A\+\+\+/, /\Aindex /
            new_line ||= 1
          when /\A-/
            # Deleted line: point to current new-side position
          end

          [current_file, new_line || 1]
        end

        # Command handler methods
        module HandlerMethods
          def git_diff(ctx, argv: [], **)
            file_path = git_resolve_path(ctx)
            unless file_path
              ctx.editor.echo_error("No file or directory to resolve git repo")
              return
            end

            lines, root, err = Diff.run(file_path, args: argv)
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
            buf.options["git_repo_root"] = root
            ctx.editor.switch_to_buffer(buf.id)
            bind_git_buffer_keys(ctx.editor, buf.id)
            ctx.editor.echo("[Git Diff]")
          end

          def git_diff_open_file(ctx, **)
            buf = ctx.buffer
            unless buf.kind == :git_diff || buf.kind == :git_log
              ctx.editor.echo_error("Not a git diff buffer")
              return
            end

            filename, line_num = Diff.parse_location(buf.lines, ctx.window.cursor_y)
            unless filename
              ctx.editor.echo_error("No file on this line")
              return
            end

            root = buf.options["git_repo_root"]
            full_path = File.join(root, filename)
            unless File.exist?(full_path)
              ctx.editor.echo_error("File not found: #{filename}")
              return
            end

            existing = ctx.editor.buffers.values.find { |b| b.path == full_path }
            if existing
              ctx.editor.switch_to_buffer(existing.id)
            else
              new_buf = ctx.editor.add_buffer_from_file(full_path)
              ctx.editor.switch_to_buffer(new_buf.id)
            end
            ctx.editor.current_window.cursor_y = [line_num - 1, 0].max
          end
        end
      end
    end
  end
end
