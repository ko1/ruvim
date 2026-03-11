# frozen_string_literal: true

require "open3"

module RuVim
  module Commands
    module Git
      module Grep
        module_function

        # Run git grep -n with extra args.
        # Returns [lines, root, error_message].
        def run(file_path, args: [])
          root, err = Git.repo_root(file_path)
          return [nil, nil, err] unless root

          cmd = ["git", "grep", "-n", *args]
          out, err, status = Open3.capture3(*cmd, chdir: root)
          # git grep exits 1 when no matches found (not an error)
          unless status.success? || status.exitstatus == 1
            return [nil, nil, err.strip]
          end
          [out.lines(chomp: true), root, nil]
        end

        # Parse a git grep output line (file:line:content).
        # Returns [filename, line_number] or nil.
        def parse_location(line)
          return nil if line.empty? || line == "--"

          m = line.match(/\A(.+?):(\d+):/)
          return nil unless m

          [m[1], m[2].to_i]
        end

        module HandlerMethods
          def git_grep(ctx, argv: [], **)
            if argv.empty?
              ctx.editor.echo_error("Usage: :git grep <pattern> [<args>...]")
              return
            end

            file_path = git_resolve_path(ctx)
            unless file_path
              ctx.editor.echo_error("No file or directory to resolve git repo")
              return
            end

            lines, root, err = Grep.run(file_path, args: argv)
            unless lines
              ctx.editor.echo_error("git grep: #{err}")
              return
            end

            if lines.empty?
              ctx.editor.echo("No matches found")
              return
            end

            buf = ctx.editor.add_virtual_buffer(
              kind: :git_grep,
              name: "[Git Grep]",
              lines: lines,
              readonly: true,
              modifiable: false
            )
            buf.options["git_repo_root"] = root
            ctx.editor.switch_to_buffer(buf.id)
            bind_git_buffer_keys(ctx.editor, buf.id)
            ctx.editor.echo("[Git Grep] #{lines.length} match(es)")
          end

          def git_grep_open_file(ctx, **)
            buf = ctx.buffer
            unless buf.kind == :git_grep
              ctx.editor.echo_error("Not a git grep buffer")
              return
            end

            line = buf.lines[ctx.window.cursor_y]
            location = Grep.parse_location(line)
            unless location
              ctx.editor.echo_error("No file on this line")
              return
            end

            filename, line_num = location
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
