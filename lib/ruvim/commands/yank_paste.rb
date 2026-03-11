# frozen_string_literal: true

module RuVim
  module Commands
    # Yank, paste, visual yank/delete, register operations
    module YankPaste
      def yank_line(ctx, count:, **)
        count = normalized_count(count)
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
        when "G"
          yank_lines_to_end(ctx)
        when "gg"
          yank_lines_to_start(ctx)
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

      private

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

        count = normalized_count(count)
        insert_at = before ? ctx.window.cursor_y : (ctx.window.cursor_y + 1)
        ctx.buffer.begin_change_group
        count.times { ctx.buffer.insert_lines_at(insert_at, lines) }
        ctx.buffer.end_change_group
        ctx.window.cursor_y = insert_at
        ctx.window.cursor_x = 0
        ctx.window.clamp_to_buffer(ctx.buffer)
      end

      def paste_charwise(ctx, text, before:, count:)
        count = normalized_count(count)
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

      def yank_text_object_word(ctx, around:)
        yank_span(ctx, word_object_span(ctx.buffer, ctx.window, around:))
      end

      def yank_text_object(ctx, motion)
        yank_span(ctx, text_object_span(ctx.buffer, ctx.window, motion))
      end

      def yank_span(ctx, span)
        return false unless span

        text = ctx.buffer.span_text(span[:start_row], span[:start_col], span[:end_row], span[:end_col])
        store_yank_register(ctx, text:, type: :charwise) unless text.empty?
        ctx.editor.echo("yanked")
        true
      end

      def yank_lines_to_end(ctx)
        y = ctx.window.cursor_y
        total = ctx.buffer.lines.length - y
        text = ctx.buffer.line_block_text(y, total)
        store_yank_register(ctx, text: text, type: :linewise)
        ctx.editor.echo("#{total} line(s) yanked")
      end

      def yank_lines_to_start(ctx)
        y = ctx.window.cursor_y
        total = y + 1
        text = ctx.buffer.line_block_text(0, total)
        store_yank_register(ctx, text: text, type: :linewise)
        ctx.editor.echo("#{total} line(s) yanked")
      end

      def blockwise_selection_text(buffer, sel)
        (sel[:start_row]..sel[:end_row]).map do |row|
          line = buffer.line_at(row)
          s_col = [sel[:start_col], line.length].min
          e_col = [sel[:end_col], line.length].min
          line[s_col...e_col].to_s
        end.join("\n")
      end
    end
  end
end
