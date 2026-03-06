# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Status
      module_function

      # Run git status.
      # Returns [lines, root, error_message].
      def run(file_path)
        root, err = Commands.repo_root(file_path)
        return [nil, nil, err] unless root

        out, err, status = Open3.capture3("git", "status", chdir: root)
        unless status.success?
          return [nil, nil, err.strip]
        end
        [out.lines(chomp: true), root, nil]
      end

      # Extract filename from a git status output line.
      # Returns relative path or nil.
      def parse_filename(line)
        stripped = line.to_s.strip
        case stripped
        when /\A(?:modified|new file|deleted|renamed|copied|typechange):\s+(.+)/
          $1.strip
        when /\A(\S.+)/
          # Untracked file lines (no prefix keyword)
          path = $1.strip
          # Skip section headers and hints
          return nil if path.start_with?("(")
          return nil if path.match?(/\A[A-Z]/)
          path
        else
          nil
        end
      end

      # Command handler methods
      module HandlerMethods
        def git_status(ctx, **)
          file_path = git_resolve_path(ctx)
          unless file_path
            ctx.editor.echo_error("No file or directory to resolve git repo")
            return
          end

          lines, root, err = Status.run(file_path)
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
          buf.options["git_repo_root"] = root
          ctx.editor.switch_to_buffer(buf.id)
          bind_git_buffer_keys(ctx.editor, buf.id)
          ctx.editor.echo("[Git Status]")
        end

        def git_status_open_file(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :git_status
            ctx.editor.echo_error("Not a git status buffer")
            return
          end

          line = buf.line_at(ctx.window.cursor_y)
          filename = Status.parse_filename(line)
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
        end

      end
    end
  end
end
