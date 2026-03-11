# frozen_string_literal: true

module RuVim
  module Commands
    # Window split/focus/close/resize, tab operations
    module Window
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

      def window_focus_or_split_left(ctx, **)
        ed = ctx.editor
        if ed.has_split_ancestor_on_axis?(:left)
          ed.focus_window_direction(:left)
        else
          ed.split_current_window(layout: :vertical, place: :before)
        end
      end

      def window_focus_or_split_right(ctx, **)
        ed = ctx.editor
        if ed.has_split_ancestor_on_axis?(:right)
          ed.focus_window_direction(:right)
        else
          ed.split_current_window(layout: :vertical, place: :after)
        end
      end

      def window_focus_or_split_up(ctx, **)
        ed = ctx.editor
        if ed.has_split_ancestor_on_axis?(:up)
          ed.focus_window_direction(:up)
        else
          ed.split_current_window(layout: :horizontal, place: :before)
        end
      end

      def window_focus_or_split_down(ctx, **)
        ed = ctx.editor
        if ed.has_split_ancestor_on_axis?(:down)
          ed.focus_window_direction(:down)
        else
          ed.split_current_window(layout: :horizontal, place: :after)
        end
      end

      def window_close(ctx, **)
        if ctx.editor.window_count <= 1
          ctx.editor.echo("Cannot close last window")
          return
        end
        ctx.editor.close_current_window
      end

      def window_only(ctx, **)
        if ctx.editor.window_count <= 1
          ctx.editor.echo("Already only one window")
          return
        end
        ctx.editor.close_other_windows
      end

      def window_equalize(ctx, **)
        ctx.editor.equalize_windows
      end

      def window_resize_height_inc(ctx, count: 1, **)
        ctx.editor.resize_window(:height_increase, count)
      end

      def window_resize_height_dec(ctx, count: 1, **)
        ctx.editor.resize_window(:height_decrease, count)
      end

      def window_resize_width_inc(ctx, count: 1, **)
        ctx.editor.resize_window(:width_increase, count)
      end

      def window_resize_width_dec(ctx, count: 1, **)
        ctx.editor.resize_window(:width_decrease, count)
      end

      def tab_new(ctx, argv:, **)
        path = argv[0]
        if ctx.buffer.modified? && !ctx.editor.effective_option("hidden", window: ctx.window, buffer: ctx.buffer)
          unless maybe_autowrite_before_switch(ctx)
            ctx.editor.echo_error("Unsaved changes (use :w or :q!)")
            return
          end
        end
        ctx.editor.tabnew(path: path)
      end

      def tab_next(ctx, count:, **)
        count = normalized_count(count)
        ctx.editor.tabnext(count)
      end

      def tab_prev(ctx, count:, **)
        count = normalized_count(count)
        ctx.editor.tabprev(count)
      end

      def tab_list(ctx, **)
        editor = ctx.editor
        items = []
        # For current tab, use live window_order; for others, use saved snapshot
        editor.tabpages.each_with_index do |tab, i|
          is_current = (i == editor.current_tabpage_index)
          current_marker = is_current ? ">" : " "
          items << "#{current_marker}Tab page #{i + 1}"
          win_ids = is_current ? editor.window_order : editor.tabpage_windows(tab)
          win_ids.each do |wid|
            win = editor.windows[wid]
            next unless win
            buf = editor.buffers[win.buffer_id]
            next unless buf
            active = (is_current && wid == editor.current_window_id) ? ">" : " "
            name = buf.display_name
            items << "  #{active} #{name}"
          end
        end
        editor.echo_multiline(items)
      end
    end
  end
end
