# frozen_string_literal: true

module RuVim
  module Commands
    # Buffer management, file I/O, quit, marks, jumps, arglist, rich view
    module BufferFile
      def mark_set(ctx, kwargs:, **)
        mark = (kwargs[:mark] || kwargs["mark"]).to_s
        raise RuVim::CommandError, "Invalid mark" unless ctx.editor.set_mark(mark)

        ctx.editor.echo("mark #{mark}")
      end

      def mark_jump(ctx, kwargs:, **)
        mark = (kwargs[:mark] || kwargs["mark"]).to_s
        linewise = !!(kwargs[:linewise] || kwargs["linewise"])
        record_jump(ctx)
        loc = ctx.editor.jump_to_mark(mark, linewise:)
        if loc
          ctx.editor.echo("#{linewise ? "'" : '`'}#{mark}")
        else
          ctx.editor.echo("Mark not set: #{mark}")
        end
      end

      def jump_older(ctx, kwargs: {}, **)
        linewise = !!(kwargs[:linewise] || kwargs["linewise"])
        loc = ctx.editor.jump_older(linewise:)
        ctx.editor.echo(loc ? (linewise ? "''" : "``") : "Jump list empty")
      end

      def jump_newer(ctx, kwargs: {}, **)
        linewise = !!(kwargs[:linewise] || kwargs["linewise"])
        loc = ctx.editor.jump_newer(linewise:)
        ctx.editor.echo(loc ? "<C-i>" : "At newest jump")
      end

      def clear_message(ctx, **)
        ctx.editor.clear_message
      end

      def file_write(ctx, argv:, bang:, kwargs: {}, **)
        if ctx.buffer.kind == :git_commit
          git_commit_execute(ctx)
          return
        end

        arg = argv.join(" ")
        if arg.start_with?("!")
          file_write_to_shell(ctx, command: arg[1..].strip, kwargs: kwargs)
          return
        end

        path = argv[0]
        target = ctx.buffer.write_to(path)
        size = File.exist?(target) ? File.size(target) : 0
        suffix = bang ? " (force accepted)" : ""
        ctx.editor.echo("\"#{target}\" #{ctx.buffer.line_count}L, #{size}B written#{suffix}")
        ctx.editor.save_undo_file_for(ctx.buffer)
        if ctx.editor.get_option("onsavehook")
          ctx.buffer.lang_module.on_save(ctx, target)
        end
      end

      def app_quit(ctx, bang:, **)
        if ctx.buffer.kind == :filter
          saved_y = ctx.buffer.options["filter_source_cursor_y"]
          saved_x = ctx.buffer.options["filter_source_cursor_x"]
          saved_row_offset = ctx.buffer.options["filter_source_row_offset"]
          saved_col_offset = ctx.buffer.options["filter_source_col_offset"]
          ctx.editor.delete_buffer(ctx.buffer.id)
          if saved_y
            win = ctx.editor.current_window
            win.cursor_y = saved_y
            win.cursor_x = saved_x || 0
            win.row_offset = saved_row_offset || 0
            win.col_offset = saved_col_offset || 0
          end
          return
        end

        if ctx.editor.window_count > 1
          ctx.editor.close_current_window
          ctx.editor.echo("closed window")
          return
        end

        if ctx.editor.tabpage_count > 1
          ctx.editor.close_current_tabpage
          ctx.editor.echo("closed tab")
          return
        end

        if ctx.buffer.modified? && !bang
          ctx.editor.echo_error("No write since last change (add ! to override)")
          return
        end

        ctx.editor.request_quit!
      end

      def app_quit_all(ctx, bang:, **)
        unless bang
          modified = ctx.editor.buffers.values.select { |b| b.file_buffer? && b.modified? }
          unless modified.empty?
            ctx.editor.echo_error("#{modified.size} buffer(s) have unsaved changes (add ! to override)")
            return
          end
        end
        ctx.editor.request_quit!
      end

      def file_write_quit_all(ctx, bang:, **)
        ctx.editor.buffers.each_value do |buf|
          next unless buf.file_buffer? && buf.modified? && buf.path
          buf.write_to(buf.path)
        end
        app_quit_all(ctx, bang: true)
      end

      def file_write_quit(ctx, argv:, bang:, **)
        file_write(ctx, argv:, bang:)
        return unless ctx.editor.running?
        app_quit(ctx, bang: true)
      end

      def file_edit(ctx, argv:, bang:, **)
        path = argv[0]
        if path.nil? || path.empty?
          current_path = ctx.buffer.path
          raise RuVim::CommandError, "Argument required" if current_path.nil? || current_path.empty?

          if ctx.buffer.modified? && !bang
            ctx.editor.echo_error("Unsaved changes (use :e! to discard)")
            return
          end

          target = ctx.buffer.reload_from_file!(current_path)
          ctx.window.clamp_to_buffer(ctx.buffer)
          ctx.editor.echo("\"#{target}\" reloaded")
          return
        end

        if ctx.buffer.modified? && !bang
          if ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
            # hidden permits abandoning a modified buffer without forcing write.
          elsif maybe_autowrite_before_switch(ctx)
            # autowrite handled
          else
            ctx.editor.echo_error("Unsaved changes (use :e! to discard and open)")
            return
          end
        end

        ctx.editor.open_path(path)
      end

      def file_goto_under_cursor(ctx, **)
        token = file_token_under_cursor(ctx.buffer, ctx.window)
        if token.nil? || token.empty?
          ctx.editor.echo_error("No file under cursor")
          return
        end

        target = parse_gf_target(token)
        path = resolve_gf_path(ctx, target[:path])
        unless path
          ctx.editor.echo_error("File not found: #{target[:path]}")
          return
        end

        if ctx.buffer.modified? && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
          unless maybe_autowrite_before_switch(ctx)
            ctx.editor.echo_error("Unsaved changes (set hidden or :w)")
            return
          end
        end

        ctx.editor.open_path(path)
        move_cursor_to_gf_line(ctx, target[:line], target[:col]) if target[:line]
      end

      def buffer_list(ctx, **)
        current_id = ctx.buffer.id
        alt_id = ctx.editor.alternate_buffer_id
        items = ctx.editor.buffer_ids.map do |id|
          b = ctx.editor.buffers.fetch(id)
          indicator = id == current_id ? "%a" : "  "
          indicator = "# " if id == alt_id && id != current_id
          mod = b.modified? ? "+" : " "
          name = b.path ? "\"#{b.path}\"" : "[No Name]"
          # Find the window showing this buffer to get cursor line
          win = ctx.editor.windows.values.find { |w| w.buffer_id == id }
          line_info = "line #{win ? win.cursor_y + 1 : 0}"
          "%3d %s %s %-30s %s" % [id, indicator, mod, name, line_info]
        end
        ctx.editor.echo_multiline(items)
      end

      def buffer_next(ctx, count:, bang:, **)
        count = normalized_count(count)
        target = ctx.editor.current_buffer.id
        count.times { target = ctx.editor.next_buffer_id_from(target, 1) }
        switch_buffer_id(ctx, target, bang:)
      end

      def buffer_prev(ctx, count:, bang:, **)
        count = normalized_count(count)
        target = ctx.editor.current_buffer.id
        count.times { target = ctx.editor.next_buffer_id_from(target, -1) }
        switch_buffer_id(ctx, target, bang:)
      end

      def buffer_switch(ctx, argv:, bang:, **)
        arg = argv[0]
        raise RuVim::CommandError, "Usage: :buffer <id|#>" if arg.nil? || arg.empty?

        target_id =
          if arg == "#"
            ctx.editor.alternate_buffer_id || raise(RuVim::CommandError, "No alternate buffer")
          elsif arg.match?(/\A\d+\z/)
            arg.to_i
          else
            find_buffer_by_name(ctx.editor, arg)&.id || raise(RuVim::CommandError, "No such buffer: #{arg}")
          end

        switch_buffer_id(ctx, target_id, bang:)
      end

      def buffer_delete(ctx, argv:, bang:, **)
        arg = argv[0]
        target_id =
          if arg.nil? || arg.empty?
            ctx.buffer.id
          elsif arg == "#"
            ctx.editor.alternate_buffer_id || raise(RuVim::CommandError, "No alternate buffer")
          elsif arg.match?(/\A\d+\z/)
            arg.to_i
          else
            find_buffer_by_name(ctx.editor, arg)&.id || raise(RuVim::CommandError, "No such buffer: #{arg}")
          end

        target = ctx.editor.buffers[target_id] || raise(RuVim::CommandError, "No such buffer: #{target_id}")
        if target.modified? && !bang
          raise RuVim::CommandError, "No write since last change (use :bdelete! to discard)"
        end

        ctx.editor.delete_buffer(target_id)
        ctx.editor.echo("buffer #{target_id} deleted")
      end

      def ex_rich(ctx, argv: [], **)
        format = argv.first
        RuVim::RichView.toggle!(ctx.editor, format: format)
      end

      def rich_toggle(ctx, **)
        RuVim::RichView.toggle!(ctx.editor)
      end

      def rich_view_close_buffer(ctx, **)
        ctx.editor.delete_buffer(ctx.buffer.id)
      end

      def arglist_show(ctx, **)
        arglist = ctx.editor.arglist
        if arglist.empty?
          ctx.editor.echo("No arguments")
          return
        end

        current_index = ctx.editor.arglist_index
        items = arglist.map.with_index do |path, i|
          if i == current_index
            "[#{path}]"
          else
            " #{path}"
          end
        end
        ctx.editor.echo_multiline(items)
      end

      def arglist_next(ctx, count:, **)
        count = normalized_count(count)
        path = ctx.editor.arglist_next(count)
        switch_to_file(ctx, path)
        ctx.editor.echo("Argument #{ctx.editor.arglist_index + 1} of #{ctx.editor.arglist.length}: #{path}")
      end

      def arglist_prev(ctx, count:, **)
        count = normalized_count(count)
        path = ctx.editor.arglist_prev(count)
        switch_to_file(ctx, path)
        ctx.editor.echo("Argument #{ctx.editor.arglist_index + 1} of #{ctx.editor.arglist.length}: #{path}")
      end

      def arglist_first(ctx, **)
        path = ctx.editor.arglist_first
        return ctx.editor.error("No arguments") unless path
        switch_to_file(ctx, path)
        ctx.editor.echo("Argument 1 of #{ctx.editor.arglist.length}: #{path}")
      end

      def arglist_last(ctx, **)
        path = ctx.editor.arglist_last
        return ctx.editor.error("No arguments") unless path
        switch_to_file(ctx, path)
        ctx.editor.echo("Argument #{ctx.editor.arglist.length} of #{ctx.editor.arglist.length}: #{path}")
      end

      private

      def file_write_to_shell(ctx, command:, kwargs: {})
        raise RuVim::CommandError, "Usage: :w !<command>" if command.empty?

        r_start = kwargs[:range_start] || 0
        r_end = kwargs[:range_end] || (ctx.buffer.line_count - 1)
        lines = (r_start..r_end).map { |i| ctx.buffer.lines[i] }
        input = lines.join("\n") + "\n"

        shell = ENV["SHELL"].to_s
        shell = "/bin/sh" if shell.empty?
        _stdout, stderr_text, status = Open3.capture3(shell, "-c", command, stdin_data: input)
        unless stderr_text.empty?
          ctx.editor.echo_error(stderr_text.lines(chomp: true).first)
          return
        end
        ctx.editor.echo("#{lines.length} line(s) written to !#{command}, exit #{status.exitstatus}")
      end

      def switch_buffer_id(ctx, buffer_id, bang: false)
        unless ctx.editor.buffers.key?(buffer_id)
          raise RuVim::CommandError, "No such buffer: #{buffer_id}"
        end

        if ctx.buffer.modified? && ctx.buffer.id != buffer_id && !bang && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
          unless maybe_autowrite_before_switch(ctx)
            ctx.editor.echo_error("Unsaved changes (use :w or :buffer! / :bnext! / :bprev!)")
            return
          end
        end

        record_jump(ctx)
        ctx.editor.switch_to_buffer(buffer_id)
        b = ctx.editor.current_buffer
        ctx.editor.echo("#{b.id} #{b.path || '[No Name]'}")
      end

      def find_buffer_by_name(editor, token)
        editor.buffers.values.find do |b|
          path = b.path.to_s
          path == token || File.basename(path) == token
        end
      end

      def file_token_under_cursor(buffer, window)
        line = buffer.line_at(window.cursor_y)
        return nil if line.empty?

        x = [[window.cursor_x, 0].max, [line.length - 1, 0].max].min
        file_char = /[[:alnum:]_\.\/~:-]/
        if line[x] !~ file_char
          left = x - 1
          right = x + 1
          if left >= 0 && line[left] =~ file_char
            x = left
          elsif right < line.length && line[right] =~ file_char
            x = right
          else
            return nil
          end
        end

        s = x
        e = x + 1
        s -= 1 while s.positive? && line[s - 1] =~ file_char
        e += 1 while e < line.length && line[e] =~ file_char
        line[s...e]
      end

      def parse_gf_target(token)
        raw = token.to_s.sub(/:\s*\z/, "")
        if (m = /\A(.+):(\d+):(\d+)\z/.match(raw))
          return { path: m[1], line: m[2].to_i, col: m[3].to_i } unless m[1].end_with?(":")
        end
        if (m = /\A(.+):(\d+)\z/.match(raw))
          return { path: m[1], line: m[2].to_i, col: nil } unless m[1].end_with?(":")
        end
        { path: raw, line: nil, col: nil }
      end

      def move_cursor_to_gf_line(ctx, line_no, col_no = nil)
        line = line_no.to_i
        return if line <= 0

        w = ctx.editor.current_window
        b = ctx.editor.current_buffer
        w.cursor_y = [line - 1, b.line_count - 1].min
        w.cursor_x = col_no.to_i if col_no
        w.cursor_x = 0 unless col_no
        w.clamp_to_buffer(b)
      end

      def resolve_gf_path(ctx, token)
        candidates = gf_candidate_paths(ctx, token.to_s)
        candidates.find { |p| File.file?(p) || File.directory?(p) }
      end

      def gf_candidate_paths(ctx, token)
        suffixes = gf_suffixes(ctx)
        names = [token]
        if File.extname(token).empty?
          suffixes.each { |suf| names << "#{token}#{suf}" }
        end
        names.uniq!

        if token.start_with?("/", "~/")
          return names.map { |n| File.expand_path(n) }.uniq
        end

        base_dirs = gf_search_dirs(ctx)
        base_dirs.product(names).map { |dir, name| File.expand_path(name, dir) }.uniq
      end

      def gf_search_dirs(ctx)
        current_dir = if ctx.buffer.path && !ctx.buffer.path.empty?
                        File.dirname(File.expand_path(ctx.buffer.path))
                      else
                        Dir.pwd
                      end
        raw = ctx.editor.effective_option("path", window: ctx.window, buffer: ctx.buffer).to_s
        dirs = raw.split(",").map(&:strip).reject(&:empty?)
        dirs = ["."] if dirs.empty?
        dirs.flat_map do |dir|
          expand_gf_path_entry(dir, current_dir)
        end.uniq
      rescue StandardError
        [Dir.pwd]
      end

      def gf_suffixes(ctx)
        raw = ctx.editor.effective_option("suffixesadd", window: ctx.window, buffer: ctx.buffer).to_s
        raw.split(",").map(&:strip).reject(&:empty?).map do |s|
          s.start_with?(".") ? s : ".#{s}"
        end
      end

      def expand_gf_path_entry(entry, current_dir)
        dir = entry.to_s
        return [current_dir] if dir.empty? || dir == "."

        expanded = File.expand_path(dir, current_dir)
        if expanded.end_with?("/**")
          base = expanded[0...-3]
          [base, *Dir.glob(File.join(base, "**", "*"))].select { |p| File.directory?(p) }
        elsif expanded.end_with?("**")
          base = expanded.sub(/\*\*\z/, "")
          base = base.sub(%r{/+\z}, "")
          [base, *Dir.glob(File.join(base, "**", "*"))].select { |p| File.directory?(p) }
        elsif expanded.match?(/[*?\[]/)
          Dir.glob(expanded).select { |p| File.directory?(p) }
        else
          [expanded]
        end
      rescue StandardError
        [expanded || File.expand_path(dir, current_dir)]
      end

      def switch_to_file(ctx, path)
        existing_buffer = ctx.editor.buffers.values.find { |buf| buf.path == path }
        if existing_buffer
          ctx.editor.set_alternate_buffer_id(ctx.editor.current_buffer.id)
          ctx.editor.activate_buffer(existing_buffer.id)
          existing_buffer.id
        else
          ctx.editor.set_alternate_buffer_id(ctx.editor.current_buffer.id)
          buffer = ctx.editor.add_buffer_from_file(path)
          ctx.editor.current_window.buffer_id = buffer.id
          buffer.id
        end
      end
    end
  end
end
