# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Blame
      module_function

      # Parse `git blame --porcelain` output into an array of entry hashes.
      # Each entry: { hash:, short_hash:, author:, date:, summary:, text:, orig_line: }
      def parse_porcelain(output)
        entries = []
        commit_cache = {}
        current = nil

        output.each_line(chomp: true) do |line|
          if line.start_with?("\t")
            current[:text] = line[1..]
            entries << current
            current = nil
          elsif current.nil?
            parts = line.split(" ")
            hash = parts[0]
            orig_line = parts[1].to_i

            if commit_cache.key?(hash)
              current = commit_cache[hash].dup
              current[:orig_line] = orig_line
            else
              current = { hash: hash, short_hash: hash[0, 8], orig_line: orig_line }
            end
          else
            case line
            when /\Aauthor (.+)/
              current[:author] = $1
            when /\Aauthor-time (\d+)/
              current[:date] = Time.at($1.to_i).strftime("%Y-%m-%d")
            when /\Asummary (.+)/
              current[:summary] = $1
            when /\Afilename (.+)/
              commit_cache[current[:hash]] ||= current.dup
            end
          end
        end

        entries
      end

      # Format entries into display lines for the blame buffer.
      def format_lines(entries)
        max_author = entries.map { |e| e[:author].to_s.length }.max || 0
        max_author = [max_author, 20].min

        entries.map do |e|
          author = (e[:author] || "").ljust(max_author)[0, max_author]
          "#{e[:short_hash]} #{author} #{e[:date]} #{e[:text]}"
        end
      end

      # Run git blame for a file at a given revision.
      # Returns [entries, error_message].
      def run(file_path, rev: nil)
        dir = File.dirname(file_path)
        basename = File.basename(file_path)

        cmd = ["git", "blame", "--porcelain"]
        if rev
          cmd << rev << "--" << basename
        else
          cmd << "--" << basename
        end

        out, err, status = Open3.capture3(*cmd, chdir: dir)
        unless status.success?
          return [nil, err.strip]
        end

        entries = parse_porcelain(out)
        [entries, nil]
      end

      # Run git show for a commit.
      # Returns [lines, error_message].
      def show_commit(file_path, commit_hash)
        dir = File.dirname(file_path)
        out, err, status = Open3.capture3("git", "show", commit_hash, chdir: dir)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Command handler methods (included via Git::Handler)
      module HandlerMethods
        def git_blame(ctx, **)
          source_buf = ctx.buffer
          unless source_buf.path && File.exist?(source_buf.path)
            ctx.editor.echo_error("No file to blame")
            return
          end

          entries, err = Blame.run(source_buf.path)
          unless entries
            ctx.editor.echo_error("git blame: #{err}")
            return
          end

          lines = Blame.format_lines(entries)
          cursor_y = ctx.window.cursor_y

          blame_buf = ctx.editor.add_virtual_buffer(
            kind: :blame,
            name: "[Blame] #{File.basename(source_buf.path)}",
            lines: lines,
            readonly: true,
            modifiable: false
          )
          blame_buf.options["blame_entries"] = entries
          blame_buf.options["blame_source_path"] = source_buf.path
          blame_buf.options["blame_history"] = []

          ctx.editor.switch_to_buffer(blame_buf.id)
          ctx.window.cursor_y = [cursor_y, lines.length - 1].min

          bind_git_buffer_keys(ctx.editor, blame_buf.id)
          bind_blame_keys(ctx.editor, blame_buf.id)
          ctx.editor.echo("[Blame] #{File.basename(source_buf.path)}")
        end

        def git_blame_prev(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :blame
            ctx.editor.echo_error("Not a blame buffer")
            return
          end

          entries = buf.options["blame_entries"]
          source_path = buf.options["blame_source_path"]
          history = buf.options["blame_history"]
          cursor_y = ctx.window.cursor_y
          entry = entries[cursor_y]

          unless entry
            ctx.editor.echo_error("No blame entry on this line")
            return
          end

          commit_hash = entry[:hash]
          if commit_hash.start_with?("0000000")
            ctx.editor.echo_error("Uncommitted changes — cannot go further back")
            return
          end

          new_entries, err = Blame.run(source_path, rev: "#{commit_hash}^")
          unless new_entries
            ctx.editor.echo_error("git blame: #{err}")
            return
          end

          history.push({ entries: entries, cursor_y: cursor_y })

          new_lines = Blame.format_lines(new_entries)
          buf.instance_variable_set(:@lines, new_lines)
          buf.options["blame_entries"] = new_entries
          ctx.window.cursor_y = [cursor_y, new_lines.length - 1].min
          ctx.window.cursor_x = 0
          ctx.editor.echo("[Blame] #{commit_hash[0, 8]}^")
        end

        def git_blame_back(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :blame
            ctx.editor.echo_error("Not a blame buffer")
            return
          end

          history = buf.options["blame_history"]
          if history.nil? || history.empty?
            ctx.editor.echo_error("No blame history to go back to")
            return
          end

          state = history.pop
          lines = Blame.format_lines(state[:entries])
          buf.instance_variable_set(:@lines, lines)
          buf.options["blame_entries"] = state[:entries]
          ctx.window.cursor_y = [state[:cursor_y], lines.length - 1].min
          ctx.window.cursor_x = 0
          ctx.editor.echo("[Blame] restored")
        end

        def git_blame_commit(ctx, **)
          buf = ctx.buffer
          unless buf.kind == :blame
            ctx.editor.echo_error("Not a blame buffer")
            return
          end

          entries = buf.options["blame_entries"]
          source_path = buf.options["blame_source_path"]
          entry = entries[ctx.window.cursor_y]

          unless entry
            ctx.editor.echo_error("No blame entry on this line")
            return
          end

          commit_hash = entry[:hash]
          if commit_hash.start_with?("0000000")
            ctx.editor.echo_error("Uncommitted changes — no commit to show")
            return
          end

          lines, err = Blame.show_commit(source_path, commit_hash)
          unless lines
            ctx.editor.echo_error("git show: #{err}")
            return
          end

          show_buf = ctx.editor.add_virtual_buffer(
            kind: :git_show,
            name: "[Commit] #{commit_hash[0, 8]}",
            lines: lines,
            filetype: "diff",
            readonly: true,
            modifiable: false
          )
          ctx.editor.switch_to_buffer(show_buf.id)
          bind_git_buffer_keys(ctx.editor, show_buf.id)
          ctx.editor.echo("[Commit] #{commit_hash[0, 8]}")
        end

        private

        def bind_blame_keys(editor, buffer_id)
          km = editor.keymap_manager
          km.bind_buffer(buffer_id, "p", "git.blame.prev")
          km.bind_buffer(buffer_id, "P", "git.blame.back")
          km.bind_buffer(buffer_id, "c", "git.blame.commit")
        end
      end
    end
  end
end
