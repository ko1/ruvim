# frozen_string_literal: true

module RuVim
  module Git
    module Handler
      GIT_SUBCOMMANDS = {
        "blame"       => :git_blame,
        "blameprev"   => :git_blame_prev,
        "blameback"   => :git_blame_back,
        "blamecommit" => :git_blame_commit,
        "status"      => :git_status,
        "diff"        => :git_diff,
        "log"         => :git_log,
      }.freeze

      def enter_git_command_mode(ctx, **)
        ctx.editor.enter_command_line_mode(":")
        ctx.editor.command_line.replace_text("git ")
        ctx.editor.clear_message
      end

      def ex_git(ctx, argv: [], **)
        sub = argv.first.to_s.downcase
        if sub.empty?
          ctx.editor.echo("Git subcommands: #{GIT_SUBCOMMANDS.keys.join(', ')}")
          return
        end

        method = GIT_SUBCOMMANDS[sub]
        unless method
          ctx.editor.echo_error("Unknown Git subcommand: #{sub}")
          return
        end

        public_send(method, ctx, argv: argv[1..], kwargs: {}, bang: false, count: 1)
      end

      # ---- blame ----

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

      # ---- status / diff / log ----

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

      # ---- close ----

      def git_close_buffer(ctx, **)
        ctx.editor.delete_buffer(ctx.buffer.id)
      end

      private

      def git_resolve_path(ctx)
        path = ctx.buffer.path
        return path if path && File.exist?(path)
        dir = Dir.pwd
        File.directory?(dir) ? dir : nil
      end

      def bind_git_buffer_keys(editor, buffer_id)
        km = editor.keymap_manager
        km.bind_buffer(buffer_id, "\e", "git.close_buffer")
        km.bind_buffer(buffer_id, "<C-c>", "git.close_buffer")
      end

      def bind_blame_keys(editor, buffer_id)
        km = editor.keymap_manager
        km.bind_buffer(buffer_id, "p", "git.blame.prev")
        km.bind_buffer(buffer_id, "P", "git.blame.back")
        km.bind_buffer(buffer_id, "c", "git.blame.commit")
      end
    end
  end
end
