require "tempfile"
require "open3"

module RuVim
  class GlobalCommands
    include Singleton

    def call(spec_call, ctx, argv: [], kwargs: {}, bang: false, count: 1)
      case spec_call
      when Symbol, String
        public_send(spec_call.to_sym, ctx, argv: argv, kwargs: kwargs, bang: bang, count: count)
      else
        spec_call.call(ctx, argv: argv, kwargs: kwargs, bang: bang, count: count)
      end
    end

    def cursor_left(ctx, count:, **)
      move_cursor_horizontally(ctx, direction: :left, count:)
    end

    def cursor_right(ctx, count:, **)
      move_cursor_horizontally(ctx, direction: :right, count:)
    end

    def cursor_up(ctx, count:, **)
      ctx.window.move_up(ctx.buffer, count)
    end

    def cursor_down(ctx, count:, **)
      ctx.window.move_down(ctx.buffer, count)
    end

    def cursor_page_up(ctx, kwargs:, count:, **)
      page_lines = [(kwargs[:page_lines] || kwargs["page_lines"] || 1).to_i, 1].max
      ctx.window.move_up(ctx.buffer, page_lines * [count.to_i, 1].max)
    end

    def cursor_page_down(ctx, kwargs:, count:, **)
      page_lines = [(kwargs[:page_lines] || kwargs["page_lines"] || 1).to_i, 1].max
      ctx.window.move_down(ctx.buffer, page_lines * [count.to_i, 1].max)
    end

    def window_scroll_up(ctx, kwargs:, count:, **)
      scroll_window_vertically(ctx, direction: :up, lines: kwargs[:lines] || kwargs["lines"], view_height: kwargs[:view_height] || kwargs["view_height"], count:)
    end

    def window_scroll_down(ctx, kwargs:, count:, **)
      scroll_window_vertically(ctx, direction: :down, lines: kwargs[:lines] || kwargs["lines"], view_height: kwargs[:view_height] || kwargs["view_height"], count:)
    end

    def cursor_line_start(ctx, **)
      ctx.window.cursor_x = 0
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def cursor_line_end(ctx, **)
      ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def cursor_first_nonblank(ctx, **)
      line = ctx.buffer.line_at(ctx.window.cursor_y)
      idx = line.index(/\S/) || 0
      ctx.window.cursor_x = idx
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def cursor_buffer_start(ctx, count:, **)
      record_jump(ctx)
      target_row = [count.to_i - 1, 0].max
      target_row = [target_row, ctx.buffer.line_count - 1].min
      ctx.window.cursor_y = target_row
      cursor_first_nonblank(ctx)
    end

    def cursor_buffer_end(ctx, count:, **)
      record_jump(ctx)
      if count && count > 1
        target_row = [count - 1, ctx.buffer.line_count - 1].min
      else
        target_row = ctx.buffer.line_count - 1
      end
      ctx.window.cursor_y = target_row
      cursor_first_nonblank(ctx)
    end

    def cursor_word_forward(ctx, count:, **)
      move_cursor_word(ctx, count:, kind: :forward_start)
    end

    def cursor_word_backward(ctx, count:, **)
      move_cursor_word(ctx, count:, kind: :backward_start)
    end

    def cursor_word_end(ctx, count:, **)
      move_cursor_word(ctx, count:, kind: :forward_end)
    end

    def cursor_match_bracket(ctx, **)
      line = ctx.buffer.line_at(ctx.window.cursor_y)
      ch = line[ctx.window.cursor_x]
      unless ch
        ctx.editor.echo_error("No bracket under cursor")
        return
      end

      pair_map = {
        "(" => [")", :forward],
        "[" => ["]", :forward],
        "{" => ["}", :forward],
        ")" => ["(", :backward],
        "]" => ["[", :backward],
        "}" => ["{", :backward]
      }
      pair = pair_map[ch]
      unless pair
        ctx.editor.echo_error("No bracket under cursor")
        return
      end

      target_char, direction = pair
      record_jump(ctx)
      loc = find_matching_bracket(ctx.buffer, ctx.window.cursor_y, ctx.window.cursor_x, ch, target_char, direction)
      if loc
        ctx.window.cursor_y = loc[:row]
        ctx.window.cursor_x = loc[:col]
        ctx.window.clamp_to_buffer(ctx.buffer)
      else
        ctx.editor.echo_error("Match not found")
      end
    end

    def enter_insert_mode(ctx, **)
      materialize_intro_buffer_if_needed(ctx)
      ctx.buffer.begin_change_group
      ctx.editor.enter_insert_mode
      ctx.editor.echo("-- INSERT --")
    end

    def append_mode(ctx, **)
      x = ctx.window.cursor_x
      len = ctx.buffer.line_length(ctx.window.cursor_y)
      ctx.window.cursor_x = [x + 1, len].min
      enter_insert_mode(ctx)
    end

    def append_line_end_mode(ctx, **)
      ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
      enter_insert_mode(ctx)
    end

    def insert_line_start_nonblank_mode(ctx, **)
      cursor_first_nonblank(ctx)
      enter_insert_mode(ctx)
    end

    def open_line_below(ctx, **)
      materialize_intro_buffer_if_needed(ctx)
      y = ctx.window.cursor_y
      x = ctx.buffer.line_length(y)
      ctx.buffer.begin_change_group
      new_y, new_x = ctx.buffer.insert_newline(y, x)
      new_x = apply_autoindent_to_newline(ctx, row: new_y, previous_row: y, start_col: new_x)
      ctx.window.cursor_y = new_y
      ctx.window.cursor_x = new_x
      ctx.editor.enter_insert_mode
      ctx.editor.echo("-- INSERT --")
    end

    def open_line_above(ctx, **)
      materialize_intro_buffer_if_needed(ctx)
      y = ctx.window.cursor_y
      ctx.buffer.begin_change_group
      _new_y, new_x = ctx.buffer.insert_newline(y, 0)
      new_x = apply_autoindent_to_newline(ctx, row: y, previous_row: y + 1, start_col: 0)
      ctx.window.cursor_y = y
      ctx.window.cursor_x = new_x
      ctx.editor.enter_insert_mode
      ctx.editor.echo("-- INSERT --")
    end

    def enter_visual_char_mode(ctx, **)
      ctx.editor.enter_visual(:visual_char)
      ctx.editor.echo("-- VISUAL --")
    end

    def enter_visual_line_mode(ctx, **)
      ctx.editor.enter_visual(:visual_line)
      ctx.editor.echo("-- VISUAL LINE --")
    end

    def enter_visual_block_mode(ctx, **)
      ctx.editor.enter_visual(:visual_block)
      ctx.editor.echo("-- VISUAL BLOCK --")
    end

    def window_split(ctx, **)
      place = ctx.editor.effective_option("splitbelow", window: ctx.window, buffer: ctx.buffer) ? :after : :before
      ctx.editor.split_current_window(layout: :horizontal, place:)
      ctx.editor.echo("split")
    end

    def window_vsplit(ctx, **)
      place = ctx.editor.effective_option("splitright", window: ctx.window, buffer: ctx.buffer) ? :after : :before
      ctx.editor.split_current_window(layout: :vertical, place:)
      ctx.editor.echo("vsplit")
    end

    def window_focus_next(ctx, **)
      ctx.editor.focus_next_window
    end

    def window_focus_left(ctx, **)
      ctx.editor.focus_window_direction(:left)
    end

    def window_focus_right(ctx, **)
      ctx.editor.focus_window_direction(:right)
    end

    def window_focus_up(ctx, **)
      ctx.editor.focus_window_direction(:up)
    end

    def window_focus_down(ctx, **)
      ctx.editor.focus_window_direction(:down)
    end

    def tab_new(ctx, argv:, **)
      path = argv[0]
      if ctx.buffer.modified? && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
        unless maybe_autowrite_before_switch(ctx)
          ctx.editor.echo_error("Unsaved changes (use :w or :q!)")
          return
        end
      end
      tab = ctx.editor.tabnew(path: path)
      if path && !path.empty?
        b = ctx.editor.current_buffer
        ctx.editor.echo("tab #{ctx.editor.current_tabpage_number}/#{ctx.editor.tabpage_count}: #{b.path || '[No Name]'}")
      else
        ctx.editor.echo("tab #{ctx.editor.current_tabpage_number}/#{ctx.editor.tabpage_count}")
      end
      tab
    end

    def tab_next(ctx, count:, **)
      ctx.editor.tabnext(count)
      ctx.editor.echo("tab #{ctx.editor.current_tabpage_number}/#{ctx.editor.tabpage_count}")
    end

    def tab_prev(ctx, count:, **)
      ctx.editor.tabprev(count)
      ctx.editor.echo("tab #{ctx.editor.current_tabpage_number}/#{ctx.editor.tabpage_count}")
    end

    def enter_command_line_mode(ctx, **)
      ctx.editor.enter_command_line_mode(":")
      ctx.editor.clear_message
    end

    def enter_search_forward_mode(ctx, **)
      ctx.editor.enter_command_line_mode("/")
      ctx.editor.clear_message
    end

    def enter_search_backward_mode(ctx, **)
      ctx.editor.enter_command_line_mode("?")
      ctx.editor.clear_message
    end

    def delete_char(ctx, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      ctx.buffer.begin_change_group
      deleted = +""
      count.times do
        chunk = char_at_cursor_for_delete(ctx.buffer, ctx.window.cursor_y, ctx.window.cursor_x)
        ok = ctx.buffer.delete_char(ctx.window.cursor_y, ctx.window.cursor_x)
        break unless ok
        deleted << chunk.to_s
      end
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def delete_line(ctx, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      ctx.buffer.begin_change_group
      deleted_lines = []
      count.times { deleted_lines << ctx.buffer.delete_line(ctx.window.cursor_y) }
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted_lines.join("\n") + "\n", type: :linewise)
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def delete_motion(ctx, count:, kwargs:, **)
      materialize_intro_buffer_if_needed(ctx)
      motion = (kwargs[:motion] || kwargs["motion"]).to_s
      handled =
        case motion
        when "h" then delete_chars_left(ctx, count)
        when "l" then delete_chars_right(ctx, count)
        when "j" then delete_lines_down(ctx, count)
        when "k" then delete_lines_up(ctx, count)
        when "$" then delete_to_end_of_line(ctx)
        when "w" then delete_word_forward(ctx, count)
        when "iw" then delete_text_object_word(ctx, around: false)
        when "aw" then delete_text_object_word(ctx, around: true)
        else
          text_object_motion?(motion) ? delete_text_object(ctx, motion) : false
        end
      ctx.editor.echo("Unsupported motion for d: #{motion}") unless handled
      handled
    end

    def change_motion(ctx, count:, kwargs:, **)
      materialize_intro_buffer_if_needed(ctx)
      handled = delete_motion(ctx, count:, kwargs:)
      return unless handled

      enter_insert_mode(ctx)
    end

    def change_line(ctx, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      delete_line(ctx, count:)
      enter_insert_mode(ctx)
    end

    def buffer_undo(ctx, **)
      if ctx.buffer.undo!
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("Undo")
      else
        ctx.editor.echo("Already at oldest change")
      end
    end

    def buffer_redo(ctx, **)
      if ctx.buffer.redo!
        ctx.window.clamp_to_buffer(ctx.buffer)
        ctx.editor.echo("Redo")
      else
        ctx.editor.echo("Already at newest change")
      end
    end

    def search_next(ctx, count:, **)
      record_jump(ctx)
      repeat_search(ctx, forward: true, count:)
    end

    def search_prev(ctx, count:, **)
      record_jump(ctx)
      repeat_search(ctx, forward: false, count:)
    end

    def search_word_forward(ctx, **)
      record_jump(ctx)
      search_current_word(ctx, exact: true, direction: :forward)
    end

    def search_word_backward(ctx, **)
      record_jump(ctx)
      search_current_word(ctx, exact: true, direction: :backward)
    end

    def search_word_forward_partial(ctx, **)
      record_jump(ctx)
      search_current_word(ctx, exact: false, direction: :forward)
    end

    def search_word_backward_partial(ctx, **)
      record_jump(ctx)
      search_current_word(ctx, exact: false, direction: :backward)
    end

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

    def replace_char(ctx, argv:, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      ch = argv[0].to_s
      raise RuVim::CommandError, "replace requires a character" if ch.empty?

      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      line = ctx.buffer.line_at(y)
      return if x >= line.length

      ctx.buffer.begin_change_group
      count.times do |i|
        cx = x + i
        break if cx >= ctx.buffer.line_length(y)
        ctx.buffer.delete_span(y, cx, y, cx + 1)
        ctx.buffer.insert_char(y, cx, ch[0])
      end
      ctx.buffer.end_change_group
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def yank_line(ctx, count:, **)
      start = ctx.window.cursor_y
      text = ctx.buffer.line_block_text(start, count)
      store_yank_register(ctx, text:, type: :linewise)
      ctx.editor.echo("#{count} line(s) yanked")
    end

    def yank_motion(ctx, count:, kwargs:, **)
      motion = (kwargs[:motion] || kwargs["motion"]).to_s
      case motion
      when "w"
        y = ctx.window.cursor_y
        x = ctx.window.cursor_x
        target = advance_word_forward(ctx.buffer, y, x, count, editor: ctx.editor, window: ctx.window)
        target ||= { row: y, col: x }
        text = ctx.buffer.span_text(y, x, target[:row], target[:col])
        store_yank_register(ctx, text:, type: :charwise)
        ctx.editor.echo("yanked")
      when "iw"
        yank_text_object_word(ctx, around: false)
      when "aw"
        yank_text_object_word(ctx, around: true)
      when "y"
        yank_line(ctx, count:)
      else
        if text_object_motion?(motion)
          yank_text_object(ctx, motion)
        else
          ctx.editor.echo("Unsupported motion for y: #{motion}")
        end
      end
    end

    def paste_after(ctx, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      paste_register(ctx, before: false, count:)
    end

    def paste_before(ctx, count:, **)
      materialize_intro_buffer_if_needed(ctx)
      paste_register(ctx, before: true, count:)
    end

    def visual_yank(ctx, **)
      sel = ctx.editor.visual_selection
      return unless sel

      if sel[:mode] == :linewise
        count = sel[:end_row] - sel[:start_row] + 1
        text = ctx.buffer.line_block_text(sel[:start_row], count)
        store_yank_register(ctx, text:, type: :linewise)
      elsif sel[:mode] == :blockwise
        text = blockwise_selection_text(ctx.buffer, sel)
        # Blockwise register/paste semantics are not implemented yet; store text payload.
        store_yank_register(ctx, text:, type: :charwise)
      else
        text = ctx.buffer.span_text(sel[:start_row], sel[:start_col], sel[:end_row], sel[:end_col])
        store_yank_register(ctx, text:, type: :charwise)
      end
      ctx.editor.enter_normal_mode
      ctx.editor.echo("yanked")
    end

    def visual_delete(ctx, **)
      materialize_intro_buffer_if_needed(ctx)
      sel = ctx.editor.visual_selection
      return unless sel

      if sel[:mode] == :linewise
        count = sel[:end_row] - sel[:start_row] + 1
        text = ctx.buffer.line_block_text(sel[:start_row], count)
        ctx.buffer.begin_change_group
        count.times { ctx.buffer.delete_line(sel[:start_row]) }
        ctx.buffer.end_change_group
        store_delete_register(ctx, text:, type: :linewise)
        ctx.window.cursor_y = [sel[:start_row], ctx.buffer.line_count - 1].min
        ctx.window.cursor_x = 0
      elsif sel[:mode] == :blockwise
        text = blockwise_selection_text(ctx.buffer, sel)
        ctx.buffer.begin_change_group
        (sel[:start_row]..sel[:end_row]).each do |row|
          line = ctx.buffer.line_at(row)
          s_col = [sel[:start_col], line.length].min
          e_col = [sel[:end_col], line.length].min
          next if e_col <= s_col

          ctx.buffer.delete_span(row, s_col, row, e_col)
        end
        ctx.buffer.end_change_group
        store_delete_register(ctx, text:, type: :charwise)
        ctx.window.cursor_y = sel[:start_row]
        ctx.window.cursor_x = sel[:start_col]
      else
        text = ctx.buffer.span_text(sel[:start_row], sel[:start_col], sel[:end_row], sel[:end_col])
        ctx.buffer.begin_change_group
        ctx.buffer.delete_span(sel[:start_row], sel[:start_col], sel[:end_row], sel[:end_col])
        ctx.buffer.end_change_group
        store_delete_register(ctx, text:, type: :charwise)
        ctx.window.cursor_y = sel[:start_row]
        ctx.window.cursor_x = sel[:start_col]
      end
      ctx.window.clamp_to_buffer(ctx.buffer)
      ctx.editor.enter_normal_mode
    end

    def visual_select_text_object(ctx, kwargs:, **)
      motion = (kwargs[:motion] || kwargs["motion"]).to_s
      span = text_object_span(ctx.buffer, ctx.window, motion)
      return false unless span

      ctx.editor.enter_visual(:visual_char) unless ctx.editor.mode == :visual_char
      v = ctx.editor.visual_state
      v[:anchor_y] = span[:start_row]
      v[:anchor_x] = span[:start_col]
      ctx.window.cursor_y = span[:end_row]
      ctx.window.cursor_x = [span[:end_col] - 1, 0].max
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def clear_message(ctx, **)
      ctx.editor.clear_message
    end

    def file_write(ctx, argv:, bang:, **)
      path = argv[0]
      target = ctx.buffer.write_to(path)
      size = File.exist?(target) ? File.size(target) : 0
      suffix = bang ? " (force accepted)" : ""
      ctx.editor.echo("\"#{target}\" #{ctx.buffer.line_count}L, #{size}B written#{suffix}")
    end

    def app_quit(ctx, bang:, **)
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

      new_buffer = ctx.editor.add_buffer_from_file(path)
      ctx.editor.switch_to_buffer(new_buffer.id)
      ctx.editor.echo(File.exist?(path) ? "\"#{path}\" #{new_buffer.line_count}L" : "\"#{path}\" [New File]")
    end

    def file_goto_under_cursor(ctx, **)
      token = file_token_under_cursor(ctx.buffer, ctx.window)
      if token.nil? || token.empty?
        ctx.editor.echo_error("No file under cursor")
        return
      end

      path = resolve_gf_path(ctx, token)
      unless path
        ctx.editor.echo_error("File not found: #{token}")
        return
      end

      if ctx.buffer.modified? && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
        unless maybe_autowrite_before_switch(ctx)
          ctx.editor.echo_error("Unsaved changes (set hidden or :w)")
          return
        end
      end

      ctx.editor.open_path(path)
    end

    def buffer_list(ctx, **)
      current_id = ctx.buffer.id
      alt_id = ctx.editor.alternate_buffer_id
      items = ctx.editor.buffer_ids.map do |id|
        b = ctx.editor.buffers.fetch(id)
        flags = ""
        flags << "%" if id == current_id
        flags << "#" if id == alt_id
        flags << "+" if b.modified?
        path = b.path || "[No Name]"
        "#{id}#{flags} #{path}"
      end
      ctx.editor.echo(items.join(" | "))
    end

    def buffer_next(ctx, count:, bang:, **)
      target = ctx.editor.current_buffer.id
      count.times { target = ctx.editor.next_buffer_id_from(target, 1) }
      switch_buffer_id(ctx, target, bang:)
    end

    def buffer_prev(ctx, count:, bang:, **)
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

    def ex_help(ctx, argv: [], **)
      topic = argv.first.to_s
      registry = RuVim::ExCommandRegistry.instance

      if topic.empty?
        lines = [
          "RuVim help",
          "",
          "Topics:",
          "  :help commands",
          "  :help regex",
          "  :help options",
          "  :help config",
          "  :help bindings",
          "",
          "Ex command help:",
          "  :help w",
          "  :help set",
          "  :help buffer"
        ]
        ctx.editor.show_help_buffer!(title: "[Help] help", lines:)
        return
      end

      key = topic.downcase
      text =
      case key
      when "commands", "command"
        "Ex commands: use :commands (list), :help <name> (detail)"
      when "regex", "search"
        "Regex uses Ruby Regexp (not Vim regex). :%s/pat/rep/g is minimal parser + Ruby regex."
      when "options", "set"
        "Options: use :set/:setlocal/:setglobal. See :help number, :help relativenumber, :help ignorecase, :help smartcase, :help hlsearch"
      when "config"
        "Config: XDG Ruby DSL at ~/.config/ruvim/init.rb and ftplugin/<filetype>.rb"
      when "bindings", "keys", "keymap"
        "Bindings: see docs/binding.md. Ex complement: Tab, insert completion: Ctrl-n/Ctrl-p"
      when "number", "relativenumber", "ignorecase", "smartcase", "hlsearch", "tabstop", "filetype"
        option_help_line(key)
      else
        if (spec = registry.resolve(topic))
          ex_command_help_line(spec)
        else
          "No help for #{topic}. Try :help or :help commands"
        end
      end
      ctx.editor.show_help_buffer!(title: "[Help] #{topic}", lines: help_text_to_lines(topic, text))
    end

    def ex_define_command(ctx, argv:, bang:, **)
      registry = RuVim::ExCommandRegistry.instance
      if argv.empty?
        items = registry.all.select { |spec| spec.source == :user }.map(&:name)
        ctx.editor.echo(items.empty? ? "No user commands" : "User commands: #{items.join(', ')}")
        return
      end

      name = argv[0].to_s
      body_tokens = argv[1..] || []
      raise RuVim::CommandError, "Usage: :command Name ex_body" if body_tokens.empty?

      if registry.registered?(name)
        unless bang
          raise RuVim::CommandError, "Command exists: #{name} (use :command! to replace)"
        end
        registry.unregister(name)
      end

      body = body_tokens.join(" ")
      handler = lambda do |inner_ctx, argv:, **_k|
        expanded = [body, *argv].join(" ").strip
        Dispatcher.new.dispatch_ex(inner_ctx.editor, expanded)
      end

      registry.register(name, call: handler, desc: "user-defined", nargs: :any, bang: true, source: :user)
      ctx.editor.echo("Defined :#{name}")
    end

    def ex_ruby(ctx, argv:, **)
      raise RuVim::CommandError, "Restricted mode: :ruby is disabled" if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

      code = argv.join(" ")
      raise RuVim::CommandError, "Usage: :ruby <code>" if code.strip.empty?

      b = binding
      b.local_variable_set(:editor, ctx.editor)
      b.local_variable_set(:buffer, ctx.buffer)
      b.local_variable_set(:window, ctx.window)
      saved_stdout = STDOUT.dup
      saved_stderr = STDERR.dup
      original_g_stdout = $stdout
      original_g_stderr = $stderr
      result = nil
      stdout_text = ""
      stderr_text = ""
      Tempfile.create("ruvim-ruby-stdout") do |outf|
        Tempfile.create("ruvim-ruby-stderr") do |errf|
          STDOUT.reopen(outf)
          STDERR.reopen(errf)
          $stdout = STDOUT
          $stderr = STDERR
          result = eval(code, b) # rubocop:disable Security/Eval
          STDOUT.flush
          STDERR.flush
          outf.flush
          errf.flush
          outf.rewind
          errf.rewind
          stdout_text = outf.read.to_s
          stderr_text = errf.read.to_s
        end
      end
      if !stdout_text.empty? || !stderr_text.empty?
        lines = ["Ruby output", ""]
        unless stdout_text.empty?
          lines << "[stdout]"
          lines.concat(stdout_text.lines(chomp: true))
          lines << ""
        end
        unless stderr_text.empty?
          lines << "[stderr]"
          lines.concat(stderr_text.lines(chomp: true))
          lines << ""
        end
        lines << "[result]"
        lines << (result.nil? ? "nil" : result.inspect)
        ctx.editor.show_help_buffer!(title: "[Ruby Output]", lines:, filetype: "ruby")
      else
        ctx.editor.echo(result.nil? ? "ruby: nil" : "ruby: #{result.inspect}")
      end
    rescue StandardError => e
      raise RuVim::CommandError, "Ruby error: #{e.class}: #{e.message}"
    ensure
      if defined?(saved_stdout) && saved_stdout
        STDOUT.reopen(saved_stdout)
        saved_stdout.close unless saved_stdout.closed?
      end
      if defined?(saved_stderr) && saved_stderr
        STDERR.reopen(saved_stderr)
        saved_stderr.close unless saved_stderr.closed?
      end
      $stdout = (defined?(original_g_stdout) && original_g_stdout) ? original_g_stdout : STDOUT
      $stderr = (defined?(original_g_stderr) && original_g_stderr) ? original_g_stderr : STDERR
    end

    def ex_shell(ctx, command:, **)
      raise RuVim::CommandError, "Restricted mode: :! is disabled" if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

      cmd = command.to_s
      raise RuVim::CommandError, "Usage: :!<command>" if cmd.strip.empty?

      shell = ENV["SHELL"].to_s
      shell = "/bin/sh" if shell.empty?
      stdout_text, stderr_text, status = Open3.capture3(shell, "-c", cmd)

      if !stdout_text.to_s.empty? || !stderr_text.to_s.empty?
        lines = ["Shell output", "", "[command]", cmd, ""]
        unless stdout_text.to_s.empty?
          lines << "[stdout]"
          lines.concat(stdout_text.to_s.lines(chomp: true))
          lines << ""
        end
        unless stderr_text.to_s.empty?
          lines << "[stderr]"
          lines.concat(stderr_text.to_s.lines(chomp: true))
          lines << ""
        end
        lines << "[status]"
        lines << "exit #{status.exitstatus}"
        ctx.editor.show_help_buffer!(title: "[Shell Output]", lines:, filetype: "sh")
      else
        ctx.editor.echo("shell exit #{status.exitstatus}")
      end
    rescue Errno::ENOENT => e
      raise RuVim::CommandError, "Shell error: #{e.message}"
    end

    def ex_commands(ctx, **)
      items = RuVim::ExCommandRegistry.instance.all.map do |spec|
        alias_text = spec.aliases.empty? ? "" : " (#{spec.aliases.join(', ')})"
        source = spec.source == :user ? " [user]" : ""
        "#{spec.name}#{alias_text}#{source}"
      end
      ctx.editor.show_help_buffer!(title: "[Commands]", lines: ["Ex commands", "", *items])
    end

    def ex_set(ctx, argv:, **)
      ex_set_common(ctx, argv, scope: :auto)
    end

    def ex_setlocal(ctx, argv:, **)
      ex_set_common(ctx, argv, scope: :local)
    end

    def ex_setglobal(ctx, argv:, **)
      ex_set_common(ctx, argv, scope: :global)
    end

    def ex_vimgrep(ctx, argv:, **)
      pattern = parse_vimgrep_pattern(argv)
      regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
      items = grep_items_for_buffers(ctx.editor.buffers.values.select(&:file_buffer?), regex)
      if items.empty?
        ctx.editor.echo_error("Pattern not found: #{pattern}")
        return
      end

      ctx.editor.set_quickfix_list(items)
      ctx.editor.jump_to_location(ctx.editor.current_quickfix_item)
      ctx.editor.echo("quickfix: #{items.length} item(s)")
    end

    def ex_lvimgrep(ctx, argv:, **)
      pattern = parse_vimgrep_pattern(argv)
      regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
      items = grep_items_for_buffers([ctx.buffer], regex)
      if items.empty?
        ctx.editor.echo_error("Pattern not found: #{pattern}")
        return
      end

      ctx.editor.set_location_list(items, window_id: ctx.window.id)
      ctx.editor.jump_to_location(ctx.editor.current_location_list_item(ctx.window.id))
      ctx.editor.echo("location list: #{items.length} item(s)")
    end

    def ex_copen(ctx, **)
      open_list_window(ctx, kind: :quickfix, title: "[Quickfix]", lines: quickfix_buffer_lines(ctx.editor), source_window_id: ctx.window.id)
    end

    def ex_cclose(ctx, **)
      close_list_windows(ctx.editor, :quickfix)
    end

    def ex_cnext(ctx, **)
      item = ctx.editor.move_quickfix(+1)
      unless item
        ctx.editor.echo_error("quickfix list is empty")
        return
      end
      ctx.editor.jump_to_location(item)
      ctx.editor.echo(quickfix_item_echo(ctx.editor))
    end

    def ex_cprev(ctx, **)
      item = ctx.editor.move_quickfix(-1)
      unless item
        ctx.editor.echo_error("quickfix list is empty")
        return
      end
      ctx.editor.jump_to_location(item)
      ctx.editor.echo(quickfix_item_echo(ctx.editor))
    end

    def ex_lopen(ctx, **)
      open_list_window(ctx, kind: :location_list, title: "[Location List]", lines: location_list_buffer_lines(ctx.editor, ctx.window.id),
                       source_window_id: ctx.window.id)
    end

    def ex_lclose(ctx, **)
      close_list_windows(ctx.editor, :location_list)
    end

    def ex_lnext(ctx, **)
      item = ctx.editor.move_location_list(+1, window_id: ctx.window.id)
      unless item
        ctx.editor.echo_error("location list is empty")
        return
      end
      ctx.editor.jump_to_location(item)
      ctx.editor.echo(location_item_echo(ctx.editor, ctx.window.id))
    end

    def ex_lprev(ctx, **)
      item = ctx.editor.move_location_list(-1, window_id: ctx.window.id)
      unless item
        ctx.editor.echo_error("location list is empty")
        return
      end
      ctx.editor.jump_to_location(item)
      ctx.editor.echo(location_item_echo(ctx.editor, ctx.window.id))
    end

    def ex_substitute(ctx, pattern:, replacement:, global: false, **)
      materialize_intro_buffer_if_needed(ctx)
      regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
      changed = 0
      new_lines = ctx.buffer.lines.map do |line|
        if global
          line.scan(regex) { changed += 1 }
          line.gsub(regex, replacement)
        else
          if line.match?(regex)
            changed += 1
            line.sub(regex, replacement)
          else
            line
          end
        end
      end

      if changed.positive?
        ctx.buffer.begin_change_group
        ctx.buffer.replace_all_lines!(new_lines)
        ctx.buffer.end_change_group
        ctx.editor.echo("#{changed} substitution(s)")
      else
        ctx.editor.echo("Pattern not found: #{pattern}")
      end
    end

    def submit_search(ctx, pattern:, direction:)
      text = pattern.to_s
      if text.empty?
        prev = ctx.editor.last_search
        raise RuVim::CommandError, "No previous search" unless prev
        text = prev[:pattern]
      end
      compile_search_regex(text, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
      ctx.editor.set_last_search(pattern: text, direction:)
      record_jump(ctx)
      move_to_search(ctx, pattern: text, direction:, count: 1)
    end

    private

    def parse_vimgrep_pattern(argv)
      raw = Array(argv).join(" ").strip
      raise RuVim::CommandError, "Usage: :vimgrep /pattern/" if raw.empty?

      if raw.length >= 2 && raw[0] == raw[-1] && raw[0] !~ /[[:alnum:]\s]/
        raw[1...-1]
      else
        raw
      end
    end

    def grep_items_for_buffers(buffers, regex)
      Array(buffers).flat_map do |buffer|
        buffer.lines.each_with_index.flat_map do |line, row|
          line.to_enum(:scan, regex).map do
            m = Regexp.last_match
            next unless m
            { buffer_id: buffer.id, row: row, col: m.begin(0), text: line }
          end.compact
        end
      end
    end

    def quickfix_buffer_lines(editor)
      items = editor.quickfix_items
      return ["Quickfix", "", "(empty)"] if items.empty?

      idx = editor.quickfix_index || 0
      build_list_buffer_lines(editor, items, idx, title: "Quickfix")
    end

    def location_list_buffer_lines(editor, window_id)
      items = editor.location_items(window_id)
      idx = editor.location_list(window_id)[:index] || 0
      return ["Location List", "", "(empty)"] if items.empty?

      build_list_buffer_lines(editor, items, idx, title: "Location List")
    end

    def build_list_buffer_lines(editor, items, current_index, title:)
      [
        title,
        "",
        *items.each_with_index.map do |it, i|
          b = editor.buffers[it[:buffer_id]]
          path = b&.display_name || "(missing)"
          mark = i == current_index ? ">" : " "
          "#{mark} #{i + 1}: #{path}:#{it[:row] + 1}:#{it[:col] + 1}: #{it[:text]}"
        end
      ]
    end

    def open_list_window(ctx, kind:, title:, lines:, source_window_id:)
      editor = ctx.editor
      editor.split_current_window(layout: :horizontal)
      buffer = editor.add_virtual_buffer(kind:, name: title, lines:, filetype: "qf", readonly: true, modifiable: false)
      buffer.options["ruvim_list_source_window_id"] = source_window_id
      editor.switch_to_buffer(buffer.id)
      editor.echo(title)
      buffer
    end

    def close_list_windows(editor, kind)
      ids = editor.find_window_ids_by_buffer_kind(kind)
      if ids.empty?
        editor.echo_error("#{kind} window is not open")
        return
      end

      ids.each do |wid|
        break if editor.window_count <= 1
        editor.close_window(wid)
      end
      editor.echo("#{kind} closed")
    end

    def quickfix_item_echo(editor)
      item = editor.current_quickfix_item
      list_item_echo(editor, item, editor.quickfix_index, editor.quickfix_items.length, label: "qf")
    end

    def location_item_echo(editor, window_id)
      item = editor.current_location_list_item(window_id)
      list = editor.location_list(window_id)
      list_item_echo(editor, item, list[:index], list[:items].length, label: "ll")
    end

    def list_item_echo(editor, item, index, total, label:)
      return "#{label}: empty" unless item

      b = editor.buffers[item[:buffer_id]]
      "#{label} #{index.to_i + 1}/#{total}: #{b&.display_name || '(missing)'}:#{item[:row] + 1}:#{item[:col] + 1}"
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

    def char_at_cursor_for_delete(buffer, row, col)
      line = buffer.line_at(row)
      if col < line.length
        line[col]
      elsif row < buffer.line_count - 1
        "\n"
      else
        ""
      end
    end

    def find_buffer_by_name(editor, token)
      editor.buffers.values.find do |b|
        path = b.path.to_s
        path == token || File.basename(path) == token
      end
    end

    def blockwise_selection_text(buffer, sel)
      (sel[:start_row]..sel[:end_row]).map do |row|
        line = buffer.line_at(row)
        s_col = [sel[:start_col], line.length].min
        e_col = [sel[:end_col], line.length].min
        line[s_col...e_col].to_s
      end.join("\n")
    end

    def apply_autoindent_to_newline(ctx, row:, previous_row:, start_col: 0)
      return start_col unless ctx.editor.effective_option("autoindent", window: ctx.window, buffer: ctx.buffer)

      prev = ctx.buffer.line_at(previous_row)
      indent = prev[/\A[ \t]*/].to_s

      if ctx.editor.effective_option("smartindent", window: ctx.window, buffer: ctx.buffer)
        trimmed = prev.rstrip
        if trimmed.end_with?("{", "[", "(")
          sw = ctx.editor.effective_option("shiftwidth", window: ctx.window, buffer: ctx.buffer).to_i
          sw = 2 if sw <= 0
          indent += " " * sw
        end
      end

      return start_col if indent.empty?

      _y, x = ctx.buffer.insert_text(row, start_col, indent)
      x
    end

    def search_current_word(ctx, exact:, direction:)
      keyword_rx = keyword_char_regex(ctx.editor, ctx.buffer, ctx.window)
      word = current_word_under_cursor(ctx.buffer, ctx.window, keyword_rx:)
      if word.nil? || word.empty?
        ctx.editor.echo("No word under cursor")
        return
      end

      pattern =
        if exact
          "(?<!#{keyword_rx.source})#{Regexp.escape(word)}(?!#{keyword_rx.source})"
        else
          Regexp.escape(word)
        end
      ctx.editor.set_last_search(pattern:, direction:)
      move_to_search(ctx, pattern:, direction:, count: 1)
    end

    def current_word_under_cursor(buffer, window, keyword_rx: /[[:alnum:]_]/)
      line = buffer.line_at(window.cursor_y)
      return nil if line.empty?

      x = [window.cursor_x, line.length - 1].min
      return nil if x.negative?

      if !keyword_char?(line[x], keyword_rx)
        left = x - 1
        if left >= 0 && keyword_char?(line[left], keyword_rx)
          x = left
        else
          return nil
        end
      end

      s = x
      s -= 1 while s.positive? && keyword_char?(line[s - 1], keyword_rx)
      e = x + 1
      e += 1 while e < line.length && keyword_char?(line[e], keyword_rx)
      line[s...e]
    end

    def delete_chars_left(ctx, count)
      return true if count <= 0

      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      start_x = [x - count, 0].max
      return true if start_x == x

      deleted = ctx.buffer.span_text(y, start_x, y, x)
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(y, start_x, y, x)
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
      ctx.window.cursor_x = start_x
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_chars_right(ctx, count)
      return true if count <= 0

      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      line_len = ctx.buffer.line_length(y)
      end_x = [x + count, line_len].min
      return true if end_x == x

      deleted = ctx.buffer.span_text(y, x, y, end_x)
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(y, x, y, end_x)
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_lines_down(ctx, count)
      total = count + 1
      deleted = ctx.buffer.line_block_text(ctx.window.cursor_y, total)
      ctx.buffer.begin_change_group
      total.times { ctx.buffer.delete_line(ctx.window.cursor_y) }
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :linewise)
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_lines_up(ctx, count)
      y = ctx.window.cursor_y
      start = [y - count, 0].max
      total = y - start + 1
      deleted = ctx.buffer.line_block_text(start, total)
      ctx.buffer.begin_change_group
      total.times { ctx.buffer.delete_line(start) }
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :linewise)
      ctx.window.cursor_y = start
      ctx.window.cursor_x = 0 if ctx.window.cursor_x > ctx.buffer.line_length(ctx.window.cursor_y)
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_to_end_of_line(ctx)
      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      line_len = ctx.buffer.line_length(y)
      return true if x >= line_len

      deleted = ctx.buffer.span_text(y, x, y, line_len)
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(y, x, y, line_len)
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_word_forward(ctx, count)
      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      target = advance_word_forward(ctx.buffer, y, x, count, editor: ctx.editor, window: ctx.window)
      return true unless target

      deleted = ctx.buffer.span_text(y, x, target[:row], target[:col])
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(y, x, target[:row], target[:col])
      ctx.buffer.end_change_group
      store_delete_register(ctx, text: deleted, type: :charwise) unless deleted.empty?
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_text_object_word(ctx, around:)
      span = word_object_span(ctx.buffer, ctx.window, around:)
      return false unless span

      text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      ctx.buffer.end_change_group
      store_delete_register(ctx, text:, type: :charwise) unless text.empty?
      ctx.window.cursor_y = span[:start_row]
      ctx.window.cursor_x = span[:start_col]
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def delete_text_object(ctx, motion)
      span = text_object_span(ctx.buffer, ctx.window, motion)
      return false unless span

      text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      ctx.buffer.begin_change_group
      ctx.buffer.delete_span(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      ctx.buffer.end_change_group
      store_delete_register(ctx, text:, type: :charwise) unless text.empty?
      ctx.window.cursor_y = span[:start_row]
      ctx.window.cursor_x = span[:start_col]
      ctx.window.clamp_to_buffer(ctx.buffer)
      true
    end

    def yank_text_object_word(ctx, around:)
      span = word_object_span(ctx.buffer, ctx.window, around:)
      return false unless span

      text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      store_yank_register(ctx, text:, type: :charwise) unless text.empty?
      ctx.editor.echo("yanked")
      true
    end

    def yank_text_object(ctx, motion)
      span = text_object_span(ctx.buffer, ctx.window, motion)
      return false unless span

      text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
      store_yank_register(ctx, text:, type: :charwise) unless text.empty?
      ctx.editor.echo("yanked")
      true
    end

    def advance_word_forward(buffer, row, col, count, editor: nil, window: nil)
      text = buffer.lines.join("\n")
      flat = cursor_to_offset(buffer, row, col)
      idx = flat
      keyword_rx = keyword_char_regex(editor, buffer, window)
      count.times do
        idx = next_word_start_offset(text, idx, keyword_rx)
        return nil unless idx
      end
      offset_to_cursor(buffer, idx)
    end

    def move_cursor_word(ctx, count:, kind:)
      buffer = ctx.buffer
      row = ctx.window.cursor_y
      col = ctx.window.cursor_x
      count = 1 if count.to_i <= 0
      target = { row:, col: }
      count.times do
        target =
          case kind
          when :forward_start then advance_word_forward(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
          when :backward_start then advance_word_backward(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
          when :forward_end then advance_word_end(buffer, target[:row], target[:col], 1, editor: ctx.editor, window: ctx.window)
          end
        break unless target
      end
      return unless target

      ctx.window.cursor_y = target[:row]
      ctx.window.cursor_x = target[:col]
      ctx.window.clamp_to_buffer(buffer)
    end

    def advance_word_backward(buffer, row, col, _count, editor: nil, window: nil)
      text = buffer.lines.join("\n")
      idx = cursor_to_offset(buffer, row, col)
      idx = [idx - 1, 0].max
      keyword_rx = keyword_char_regex(editor, buffer, window)
      while idx > 0 && char_class(text[idx], keyword_rx) == :space
        idx -= 1
      end
      cls = char_class(text[idx], keyword_rx)
      while idx > 0 && char_class(text[idx - 1], keyword_rx) == cls && cls != :space
        idx -= 1
      end
      while idx > 0 && char_class(text[idx], keyword_rx) == :space
        idx += 1
      end
      offset_to_cursor(buffer, idx)
    end

    def advance_word_end(buffer, row, col, _count, editor: nil, window: nil)
      text = buffer.lines.join("\n")
      idx = cursor_to_offset(buffer, row, col)
      n = text.length
      keyword_rx = keyword_char_regex(editor, buffer, window)
      while idx < n && char_class(text[idx], keyword_rx) == :space
        idx += 1
      end
      return nil if idx >= n

      cls = char_class(text[idx], keyword_rx)
      idx += 1 while idx + 1 < n && char_class(text[idx + 1], keyword_rx) == cls && cls != :space
      offset_to_cursor(buffer, idx)
    end

    def next_word_start_offset(text, from_offset, keyword_rx = nil)
      i = [from_offset, 0].max
      n = text.length
      return nil if i >= n

      cls = char_class(text[i], keyword_rx)
      if cls == :word
        i += 1 while i < n && char_class(text[i], keyword_rx) == :word
      elsif cls == :space
        i += 1 while i < n && char_class(text[i], keyword_rx) == :space
      else
        i += 1
      end
      i += 1 while i < n && char_class(text[i], keyword_rx) == :space
      return n if i > n

      i <= n ? i : nil
    end

    def char_class(ch, keyword_rx = nil)
      return :space if ch == "\n"
      return :space if ch =~ /\s/
      return :word if keyword_char?(ch, keyword_rx)
      :punct
    end

    def word_object_span(buffer, window, around:)
      row = window.cursor_y
      line = buffer.line_at(row)
      return nil if line.empty?

      x = [window.cursor_x, line.length - 1].min
      x = 0 if x.negative?

      if x < line.length && line[x] =~ /\s/
        if around
          left = x
          left -= 1 while left.positive? && line[left - 1] =~ /\s/
          right = x
          right += 1 while right < line.length && line[right] =~ /\s/
          return { start_row: row, start_col: left, end_row: row, end_col: right }
        end

        nxt = line.index(/\S/, x)
        return nil unless nxt
        x = nxt
      end

      keyword_rx = keyword_char_regex(nil, buffer, window)
      cls = keyword_char?(line[x], keyword_rx) ? :word : :punct
      start_col = x
      start_col -= 1 while start_col.positive? && same_word_class?(line[start_col - 1], cls, keyword_rx)
      end_col = x + 1
      end_col += 1 while end_col < line.length && same_word_class?(line[end_col], cls, keyword_rx)

      if around
        while end_col < line.length && line[end_col] =~ /\s/
          end_col += 1
        end
      end

      { start_row: row, start_col:, end_row: row, end_col: }
    end

    def text_object_span(buffer, window, motion)
      around = motion.start_with?("a")
      kind = motion[1..]
      case kind
      when "w"
        word_object_span(buffer, window, around:)
      when "p"
        paragraph_object_span(buffer, window, around:)
      when '"'
        quote_object_span(buffer, window, quote: '"', around:)
      when "'"
        quote_object_span(buffer, window, quote: "'", around:)
      when "`"
        quote_object_span(buffer, window, quote: "`", around:)
      when ")"
        paren_object_span(buffer, window, open: "(", close: ")", around:)
      when "]"
        paren_object_span(buffer, window, open: "[", close: "]", around:)
      when "}"
        paren_object_span(buffer, window, open: "{", close: "}", around:)
      else
        nil
      end
    end

    def text_object_motion?(motion)
      motion.is_a?(String) && motion.match?(/\A[ia](w|p|["'`\)\]\}])\z/)
    end

    def quote_object_span(buffer, window, quote:, around:)
      row = window.cursor_y
      line = buffer.line_at(row)
      return nil if line.empty?
      x = [window.cursor_x, line.length - 1].min
      return nil if x.negative?

      left = find_left_quote(line, x, quote)
      right_from = [x, (left ? left + 1 : 0)].max
      right = find_right_quote(line, right_from, quote)
      return nil unless left && right && left < right

      if around
        { start_row: row, start_col: left, end_row: row, end_col: right + 1 }
      else
        { start_row: row, start_col: left + 1, end_row: row, end_col: right }
      end
    end

    def paren_object_span(buffer, window, open:, close:, around:)
      row = window.cursor_y
      line = buffer.line_at(row)
      return nil if line.empty?
      x = [window.cursor_x, line.length - 1].min
      return nil if x.negative?

      left = find_matching_left_delim(line, x, open:, close:)
      right = find_matching_right_delim(line, [x, left || 0].max, open:, close:)
      return nil unless left && right && left < right

      if around
        { start_row: row, start_col: left, end_row: row, end_col: right + 1 }
      else
        { start_row: row, start_col: left + 1, end_row: row, end_col: right }
      end
    end

    def paragraph_object_span(buffer, window, around:)
      row = [[window.cursor_y, 0].max, buffer.line_count - 1].min
      return nil if row.negative?

      blank = buffer.line_at(row).strip.empty?
      start_row = row
      end_row = row

      while start_row.positive? && (buffer.line_at(start_row - 1).strip.empty? == blank)
        start_row -= 1
      end
      while end_row + 1 < buffer.line_count && (buffer.line_at(end_row + 1).strip.empty? == blank)
        end_row += 1
      end

      if around && !blank
        if end_row + 1 < buffer.line_count && buffer.line_at(end_row + 1).strip.empty?
          while end_row + 1 < buffer.line_count && buffer.line_at(end_row + 1).strip.empty?
            end_row += 1
          end
        elsif start_row.positive? && buffer.line_at(start_row - 1).strip.empty?
          while start_row.positive? && buffer.line_at(start_row - 1).strip.empty?
            start_row -= 1
          end
        end
      end

      if around && end_row + 1 < buffer.line_count
        {
          start_row: start_row,
          start_col: 0,
          end_row: end_row + 1,
          end_col: 0
        }
      else
        {
          start_row: start_row,
          start_col: 0,
          end_row: end_row,
          end_col: buffer.line_length(end_row)
        }
      end
    end

    def find_left_quote(line, x, quote)
      i = x
      while i >= 0
        return i if line[i] == quote && !escaped?(line, i)
        i -= 1
      end
      nil
    end

    def find_right_quote(line, x, quote)
      i = x
      while i < line.length
        return i if line[i] == quote && !escaped?(line, i)
        i += 1
      end
      nil
    end

    def escaped?(line, idx)
      backslashes = 0
      i = idx - 1
      while i >= 0 && line[i] == "\\"
        backslashes += 1
        i -= 1
      end
      backslashes.odd?
    end

    def find_matching_left_delim(line, x, open:, close:)
      depth = 0
      i = x
      while i >= 0
        ch = line[i]
        if ch == close
          depth += 1
        elsif ch == open
          return i if depth.zero?
          depth -= 1
        end
        i -= 1
      end
      nil
    end

    def find_matching_right_delim(line, x, open:, close:)
      depth = 0
      i = x
      while i < line.length
        ch = line[i]
        if ch == open
          depth += 1
        elsif ch == close
          if depth <= 1
            return i
          end
          depth -= 1
        end
        i += 1
      end
      nil
    end

    def same_word_class?(ch, cls, keyword_rx = nil)
      return false if ch.nil?
      case cls
      when :word then keyword_char?(ch, keyword_rx)
      when :punct then !(keyword_char?(ch, keyword_rx) || ch =~ /\s/)
      else false
      end
    end

    def keyword_char?(ch, keyword_rx = nil)
      return false if ch.nil?

      (keyword_rx || /[[:alnum:]_]/).match?(ch)
    end

    def keyword_char_regex(editor, buffer, window)
      win = window || editor&.current_window
      buf = buffer || editor&.current_buffer
      raw =
        if editor
          editor.effective_option("iskeyword", window: win, buffer: buf).to_s
        else
          buf&.options&.fetch("iskeyword", nil).to_s
        end
      RuVim::KeywordChars.regex(raw)
    end

    def move_cursor_horizontally(ctx, direction:, count:)
      count = [count.to_i, 1].max
      allow_wrap = whichwrap_allows?(ctx, direction)
      virtualedit_mode = virtualedit_mode(ctx)
      count.times do
        line = ctx.buffer.line_at(ctx.window.cursor_y)
        if direction == :left
          if ctx.window.cursor_x > line.length && virtualedit_mode
            ctx.window.cursor_x -= 1
          elsif ctx.window.cursor_x.positive?
            ctx.window.cursor_x = RuVim::TextMetrics.previous_grapheme_char_index(line, ctx.window.cursor_x)
          elsif allow_wrap && ctx.window.cursor_y.positive?
            ctx.window.cursor_y -= 1
            ctx.window.cursor_x = ctx.buffer.line_length(ctx.window.cursor_y)
          end
        else
          max_right =
            case virtualedit_mode
            when :all then line.length + count + 1024 # practical cap; clamp below uses current cursor
            when :onemore then line.length + 1
            else line.length
            end
          if ctx.window.cursor_x < max_right
            ctx.window.cursor_x =
              if virtualedit_mode == :onemore && ctx.window.cursor_x == line.length
                line.length + 1
              elsif virtualedit_mode == :all && ctx.window.cursor_x >= line.length
                ctx.window.cursor_x + 1
              else
                RuVim::TextMetrics.next_grapheme_char_index(line, ctx.window.cursor_x)
              end
            ctx.window.cursor_x = [ctx.window.cursor_x, max_right].min
          elsif allow_wrap && ctx.window.cursor_y < ctx.buffer.line_count - 1
            ctx.window.cursor_y += 1
            ctx.window.cursor_x = 0
          end
        end
      end
      extra =
        case virtualedit_mode
        when :all
          [ctx.window.cursor_x - ctx.buffer.line_length(ctx.window.cursor_y), 0].max
        when :onemore
          1
        else
          0
        end
      ctx.window.clamp_to_buffer(ctx.buffer, max_extra_col: extra)
    end

    def whichwrap_allows?(ctx, direction)
      toks = ctx.editor.effective_option("whichwrap", window: ctx.window, buffer: ctx.buffer).to_s
               .split(",").map { |s| s.strip.downcase }.reject(&:empty?)
      return false if toks.empty?

      if direction == :left
        toks.include?("h") || toks.include?("<") || toks.include?("left")
      else
        toks.include?("l") || toks.include?(">") || toks.include?("right")
      end
    end

    def virtualedit_mode(ctx)
      spec = ctx.editor.effective_option("virtualedit", window: ctx.window, buffer: ctx.buffer).to_s
      toks = spec.split(",").map { |s| s.strip.downcase }
      return :all if toks.include?("all")
      return :onemore if toks.include?("onemore")

      nil
    end

    def scroll_window_vertically(ctx, direction:, lines:, view_height:, count:)
      step = [[lines.to_i, 1].max * [count.to_i, 1].max, 1].max
      height = [view_height.to_i, 1].max
      max_row_offset = [ctx.buffer.line_count - height, 0].max

      before = ctx.window.row_offset.to_i
      after =
        if direction == :up
          [before - step, 0].max
        else
          [before + step, max_row_offset].min
        end
      return if after == before

      ctx.window.row_offset = after

      # Vim-like behavior: scroll viewport first, then keep cursor inside it.
      top = after
      bottom = after + height - 1
      if ctx.window.cursor_y < top
        ctx.window.cursor_y = top
      elsif ctx.window.cursor_y > bottom
        ctx.window.cursor_y = bottom
      end
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def cursor_to_offset(buffer, row, col)
      offset = 0
      row.times { |r| offset += buffer.line_length(r) + 1 }
      offset + col
    end

    def offset_to_cursor(buffer, offset)
      remaining = offset
      (0...buffer.line_count).each do |row|
        len = buffer.line_length(row)
        return { row:, col: [remaining, len].min } if remaining <= len
        remaining -= (len + 1)
      end
      { row: buffer.line_count - 1, col: buffer.line_length(buffer.line_count - 1) }
    end

    def paste_register(ctx, before:, count:)
      reg_name = ctx.editor.consume_active_register("\"")
      reg = ctx.editor.get_register(reg_name)
      unless reg
        ctx.editor.echo("Register is empty")
        return
      end

      if reg[:type] == :linewise
        paste_linewise(ctx, reg[:text], before:, count:)
      else
        paste_charwise(ctx, reg[:text], before:, count:)
      end
    end

    def paste_linewise(ctx, text, before:, count:)
      lines = text.sub(/\n\z/, "").split("\n", -1)
      return if lines.empty?

      insert_at = before ? ctx.window.cursor_y : (ctx.window.cursor_y + 1)
      ctx.buffer.begin_change_group
      count.times { ctx.buffer.insert_lines_at(insert_at, lines) }
      ctx.buffer.end_change_group
      ctx.window.cursor_y = insert_at
      ctx.window.cursor_x = 0
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def store_register(ctx, text:, type:, kind: :generic)
      name = ctx.editor.consume_active_register("\"")
      if kind == :generic
        ctx.editor.set_register(name, text:, type:)
      else
        ctx.editor.store_operator_register(name, text:, type:, kind:)
      end
    end

    def store_delete_register(ctx, text:, type:)
      store_register(ctx, text:, type:, kind: :delete)
    end

    def store_yank_register(ctx, text:, type:)
      store_register(ctx, text:, type:, kind: :yank)
    end

    def record_jump(ctx)
      ctx.editor.push_jump_location(ctx.editor.current_location)
    end

    def find_matching_bracket(buffer, row, col, open_ch, close_ch, direction)
      depth = 1
      pos = { row: row, col: col }
      loop do
        pos = direction == :forward ? next_buffer_pos(buffer, pos[:row], pos[:col]) : prev_buffer_pos(buffer, pos[:row], pos[:col])
        return nil unless pos

        ch = buffer.line_at(pos[:row])[pos[:col]]
        next unless ch

        if ch == open_ch
          depth += 1
        elsif ch == close_ch
          depth -= 1
          return pos if depth.zero?
        end
      end
    end

    def next_buffer_pos(buffer, row, col)
      line = buffer.line_at(row)
      if col + 1 < line.length
        { row: row, col: col + 1 }
      elsif row + 1 < buffer.line_count
        { row: row + 1, col: 0 }
      end
    end

    def prev_buffer_pos(buffer, row, col)
      if col.positive?
        { row: row, col: col - 1 }
      elsif row.positive?
        prev_row = row - 1
        prev_len = buffer.line_length(prev_row)
        return { row: prev_row, col: prev_len - 1 } if prev_len.positive?

        { row: prev_row, col: 0 }
      end
    end

    def materialize_intro_buffer_if_needed(ctx)
      ctx.editor.materialize_intro_buffer!
      nil
    end

    def maybe_autowrite_before_switch(ctx)
      return false unless ctx.editor.effective_option("autowrite", window: ctx.window, buffer: ctx.buffer)
      return false unless ctx.buffer.file_buffer?
      return false unless ctx.buffer.path && !ctx.buffer.path.empty?

      ctx.buffer.write_to(ctx.buffer.path)
      true
    rescue StandardError
      false
    end

    def file_token_under_cursor(buffer, window)
      line = buffer.line_at(window.cursor_y)
      return nil if line.empty?

      x = [[window.cursor_x, 0].max, [line.length - 1, 0].max].min
      file_char = /[[:alnum:]_\.\/~-]/
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

    def ex_set_common(ctx, argv, scope:)
      editor = ctx.editor
      if argv.empty?
        items = editor.option_snapshot(window: ctx.window, buffer: ctx.buffer).map do |opt|
          format_option_value(opt[:name], opt[:effective])
        end
        ctx.editor.echo(items.join(" "))
        return
      end

      output = []
      argv.each do |token|
        output.concat(handle_set_token(ctx, token, scope:))
      end
      ctx.editor.echo(output.join(" ")) unless output.empty?
    end

    def handle_set_token(ctx, token, scope:)
      t = token.to_s
      return [] if t.empty?

      if t.end_with?("?")
        name = t[0...-1]
        val = ctx.editor.get_option(name, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
        return ["#{name}=#{format_option_scalar(val)}"]
      end

      if t.start_with?("no")
        name = t[2..]
        return [apply_bool_option(ctx, name, false, scope:)]
      end

      if t.start_with?("inv")
        name = t[3..]
        cur = !!ctx.editor.get_option(name, scope: :effective, window: ctx.window, buffer: ctx.buffer)
        return [apply_bool_option(ctx, name, !cur, scope:)]
      end

      if t.include?("=")
        name, raw = t.split("=", 2)
        val = parse_option_value(ctx.editor, name, raw)
        applied = ctx.editor.set_option(name, val, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
        return ["#{name}=#{format_option_scalar(applied)}"]
      end

      if bool_option?(ctx.editor, t)
        return [apply_bool_option(ctx, t, true, scope:)]
      end

      val = ctx.editor.get_option(t, scope: resolve_option_scope(ctx.editor, t, scope), window: ctx.window, buffer: ctx.buffer)
      ["#{t}=#{format_option_scalar(val)}"]
    end

    def apply_bool_option(ctx, name, value, scope:)
      unless bool_option?(ctx.editor, name)
        raise RuVim::CommandError, "#{name} is not a boolean option"
      end
      applied = ctx.editor.set_option(name, value, scope: resolve_option_scope(ctx.editor, name, scope), window: ctx.window, buffer: ctx.buffer)
      applied ? name.to_s : "no#{name}"
    end

    def resolve_option_scope(editor, name, requested_scope)
      case requested_scope
      when :auto
        :auto
      when :global
        :global
      when :local
        editor.option_default_scope(name) == :buffer ? :buffer : :window
      else
        requested_scope
      end
    end

    def parse_option_value(editor, name, raw)
      defn = editor.option_def(name)
      return raw unless defn

      case defn[:type]
      when :bool
        parse_bool(raw)
      when :int
        Integer(raw)
      else
        raw
      end
    rescue ArgumentError
      raise RuVim::CommandError, "Invalid value for #{name}: #{raw}"
    end

    def parse_bool(raw)
      case raw.to_s.downcase
      when "1", "true", "on", "yes" then true
      when "0", "false", "off", "no" then false
      else
        raise ArgumentError
      end
    end

    def bool_option?(editor, name)
      editor.option_def(name)&.dig(:type) == :bool
    end

    def format_option_value(name, value)
      if value == true
        name.to_s
      elsif value == false
        "no#{name}"
      else
        "#{name}=#{format_option_scalar(value)}"
      end
    end

    def format_option_scalar(value)
      value.nil? ? "nil" : value.to_s
    end

    def ex_command_help_line(spec)
      aliases = spec.aliases.empty? ? "" : " aliases=#{spec.aliases.join(',')}"
      nargs = " nargs=#{spec.nargs}"
      bang = spec.bang ? " !" : ""
      src = spec.source == :user ? " [user]" : ""
      ":#{spec.name}#{bang} - #{spec.desc}#{aliases}#{nargs}#{src}"
    end

    def option_help_line(name)
      case name
      when "number"
        "number (bool, window-local): line numbers. :set number / :set nonumber"
      when "tabstop"
        "tabstop (int, buffer-local): tab display width. ex: :set tabstop=4"
      when "relativenumber"
        "relativenumber (bool, window-local): show relative line numbers. ex: :set relativenumber"
      when "ignorecase"
        "ignorecase (bool, global): case-insensitive search unless smartcase + uppercase pattern"
      when "smartcase"
        "smartcase (bool, global): with ignorecase, uppercase in pattern makes search case-sensitive"
      when "hlsearch"
        "hlsearch (bool, global): highlight search matches on screen"
      when "filetype"
        "filetype (string, buffer-local): used for ftplugin and filetype-local keymaps"
      else
        "No option help: #{name}"
      end
    end

    def help_text_to_lines(topic, text)
      [
        "RuVim help: #{topic}",
        "",
        *text.to_s.scan(/.{1,78}(?:\s+|$)|.{1,78}/).map(&:rstrip)
      ]
    end

    def paste_charwise(ctx, text, before:, count:)
      y = ctx.window.cursor_y
      x = ctx.window.cursor_x
      insert_col = before ? x : [x + 1, ctx.buffer.line_length(y)].min

      ctx.buffer.begin_change_group
      count.times do
        y, insert_col = ctx.buffer.insert_text(y, insert_col, text)
      end
      ctx.buffer.end_change_group
      ctx.window.cursor_y = y
      ctx.window.cursor_x = [insert_col - 1, 0].max
      ctx.window.clamp_to_buffer(ctx.buffer)
    end

    def repeat_search(ctx, forward:, count:)
      prev = ctx.editor.last_search
      unless prev
        ctx.editor.echo("No previous search")
        return
      end

      direction = forward ? prev[:direction] : invert_direction(prev[:direction])
      move_to_search(ctx, pattern: prev[:pattern], direction:, count:)
    end

    def invert_direction(direction)
      direction.to_sym == :forward ? :backward : :forward
    end

    def move_to_search(ctx, pattern:, direction:, count:)
      count = 1 if count.to_i <= 0
      regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
      count.times do
        match = find_next_match(ctx.buffer, ctx.window, regex, direction: direction)
        unless match
          ctx.editor.echo("Pattern not found: #{pattern}")
          return
        end
        ctx.window.cursor_y = match[:row]
        ctx.window.cursor_x = match[:col]
      end
      ctx.editor.echo("/#{pattern}")
    end

    def find_next_match(buffer, window, regex, direction:)
      return nil unless regex

      if direction.to_sym == :backward
        find_backward_match(buffer, window, regex)
      else
        find_forward_match(buffer, window, regex)
      end
    end

    def find_forward_match(buffer, window, regex)
      start_row = window.cursor_y
      start_col = window.cursor_x + 1
      last_row = buffer.line_count - 1

      (0..last_row).each do |offset|
        row = (start_row + offset) % (last_row + 1)
        line = buffer.line_at(row)
        col_from = row == start_row ? start_col : 0
        m = regex.match(line, col_from)
        return { row:, col: m.begin(0) } if m
      end
      nil
    end

    def find_backward_match(buffer, window, regex)
      start_row = window.cursor_y
      start_col = [window.cursor_x - 1, buffer.line_length(start_row)].min
      last_row = buffer.line_count - 1

      (0..last_row).each do |offset|
        row = (start_row - offset) % (last_row + 1)
        line = buffer.line_at(row)
        idx = last_regex_match_before(line, regex, row == start_row ? start_col : line.length)
        return { row:, col: idx } if idx
      end
      nil
    end

    def last_regex_match_before(line, regex, max_col)
      idx = nil
      offset = 0
      while (m = regex.match(line, offset))
        break if m.begin(0) > max_col
        idx = m.begin(0) if m.begin(0) <= max_col
        next_offset = m.begin(0) == m.end(0) ? m.begin(0) + 1 : m.end(0)
        break if next_offset > line.length
        offset = next_offset
      end
      idx
    end

    def compile_search_regex(pattern, editor: nil, window: nil, buffer: nil)
      flags = search_regexp_flags(pattern.to_s, editor:, window:, buffer:)
      Regexp.new(pattern.to_s, flags)
    rescue RegexpError => e
      raise RuVim::CommandError, "Invalid regex: #{e.message}"
    end

    def search_regexp_flags(pattern, editor:, window:, buffer:)
      return 0 unless editor

      ignorecase = !!editor.effective_option("ignorecase", window:, buffer:)
      return 0 unless ignorecase

      smartcase = !!editor.effective_option("smartcase", window:, buffer:)
      if smartcase && pattern.match?(/[A-Z]/)
        0
      else
        Regexp::IGNORECASE
      end
    rescue StandardError
      0
    end
  end
end
