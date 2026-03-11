# frozen_string_literal: true

module RuVim
  module Commands
    # Search, substitute, global, filter, grep
    module Search
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

      def ex_substitute(ctx, pattern:, replacement:, flags_str: nil, range_start: nil, range_end: nil, global: false, **)
        materialize_intro_buffer_if_needed(ctx)
        flags = parse_substitute_flags(flags_str, default_global: global)

        regex = build_substitute_regex(pattern, flags, ctx)

        r_start = range_start || 0
        r_end = range_end || (ctx.buffer.line_count - 1)

        if flags[:count_only]
          total = count_matches_in_range(ctx.buffer, regex, r_start, r_end, flags[:global])
          ctx.editor.echo("#{total} match(es)")
          return
        end

        changed = if flags[:confirm]
                    substitute_range_confirm(ctx, regex, replacement, r_start, r_end, flags)
                  else
                    substitute_range(ctx, regex, replacement, r_start, r_end, flags)
                  end

        if changed.positive?
          ctx.editor.echo("#{changed} substitution(s)")
        elsif flags[:no_error]
          ctx.editor.echo("Pattern not found: #{pattern}")
        else
          ctx.editor.echo("Pattern not found: #{pattern}")
        end
      end

      def ex_global(ctx, pattern:, command:, invert: false, range_start: nil, range_end: nil, **)
        materialize_intro_buffer_if_needed(ctx)
        buf = ctx.buffer
        regex = compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: buf)

        r_start = range_start || 0
        r_end = range_end || (buf.line_count - 1)

        # Collect matching line numbers first (lines may shift during execution)
        matching = (r_start..r_end).select do |row|
          matched = regex.match?(buf.line_at(row))
          invert ? !matched : matched
        end

        if matching.empty?
          ctx.editor.echo("Pattern not found: #{pattern}")
          return
        end

        ctx.editor.with_echo_accumulation do
          buf.begin_change_group
          begin
            offset = 0
            matching.each do |orig_row|
              row = orig_row + offset
              next if row < 0 || row >= buf.line_count

              prev_count = buf.line_count
              ctx.window.cursor_y = row
              ctx.window.cursor_x = 0
              execute_global_sub_command(ctx, command)
              offset += buf.line_count - prev_count
            end
          ensure
            buf.end_change_group
          end
        end

        ctx.window.clamp_to_buffer(buf)
      end

      def ex_grep(ctx, argv:, kwargs: {}, **)
        run_external_grep(ctx, argv:, target: :quickfix)
      end

      def ex_lgrep(ctx, argv:, kwargs: {}, **)
        run_external_grep(ctx, argv:, target: :location_list)
      end

      def search_filter(ctx, **)
        editor = ctx.editor
        search = editor.last_search
        unless search
          editor.echo_error("No search pattern")
          return
        end

        regex = compile_search_regex(search[:pattern], editor: editor, window: ctx.window, buffer: ctx.buffer)
        source_buffer = ctx.buffer

        # Collect matching lines with origin mapping
        origins = []
        matching_lines = []
        source_buffer.lines.each_with_index do |line, row|
          if regex.match?(line)
            # If source is a filter buffer, chain back to the original
            if source_buffer.kind == :filter && source_buffer.options["filter_origins"]
              origins << source_buffer.options["filter_origins"][row]
            else
              origins << { buffer_id: source_buffer.id, row: row }
            end
            matching_lines << line
          end
        end

        if matching_lines.empty?
          editor.echo_error("Pattern not found: #{search[:pattern]}")
          return
        end

        filetype = source_buffer.options["filetype"]
        filter_buf = editor.add_virtual_buffer(
          kind: :filter,
          name: "[Filter: /#{search[:pattern]}/]",
          lines: matching_lines,
          filetype: filetype,
          readonly: false,
          modifiable: false
        )
        filter_buf.options["filter_origins"] = origins
        filter_buf.options["filter_source_buffer_id"] = source_buffer.id
        filter_buf.options["filter_source_cursor_y"] = ctx.window.cursor_y
        filter_buf.options["filter_source_cursor_x"] = ctx.window.cursor_x
        filter_buf.options["filter_source_row_offset"] = ctx.window.row_offset
        filter_buf.options["filter_source_col_offset"] = ctx.window.col_offset
        editor.switch_to_buffer(filter_buf.id)
        editor.echo("filter: #{matching_lines.length} line(s)")
      end

      def ex_filter(ctx, argv:, **)
        if argv.any?
          pattern = parse_vimgrep_pattern(argv.join(" "))
          editor = ctx.editor
          editor.set_last_search(pattern: pattern, direction: :forward)
        end
        search_filter(ctx)
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
        direction == :forward ? :backward : :forward
      end

      def move_to_search(ctx, pattern:, direction:, count:)
        count = normalized_count(count)
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

        if direction == :backward
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

      def parse_substitute_flags(flags_str, default_global: false)
        flags = { global: default_global, ignore_case: false, match_case: false, count_only: false, no_error: false, confirm: false }
        return flags if flags_str.nil? || flags_str.empty?

        flags_str.each_char do |ch|
          case ch
          when "g" then flags[:global] = true
          when "i" then flags[:ignore_case] = true
          when "I" then flags[:match_case] = true
          when "n" then flags[:count_only] = true
          when "e" then flags[:no_error] = true
          when "c" then flags[:confirm] = true
          end
        end
        flags
      end

      def build_substitute_regex(pattern, flags, ctx)
        if flags[:match_case]
          # I flag: force case-sensitive
          Regexp.new(pattern.to_s)
        elsif flags[:ignore_case]
          # i flag: force case-insensitive
          Regexp.new(pattern.to_s, Regexp::IGNORECASE)
        else
          compile_search_regex(pattern, editor: ctx.editor, window: ctx.window, buffer: ctx.buffer)
        end
      rescue RegexpError => e
        raise RuVim::CommandError, "Invalid regex: #{e.message}"
      end

      def substitute_range(ctx, regex, replacement, r_start, r_end, flags)
        changed = 0
        new_lines = ctx.buffer.lines.each_with_index.map do |line, idx|
          if idx >= r_start && idx <= r_end
            if flags[:global]
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
          else
            line
          end
        end

        if changed.positive?
          ctx.buffer.begin_change_group
          ctx.buffer.replace_all_lines!(new_lines)
          ctx.buffer.end_change_group
        end
        changed
      end

      def substitute_range_confirm(ctx, regex, replacement, r_start, r_end, flags)
        changed = 0
        reader = ctx.editor.confirm_key_reader
        return 0 unless reader

        ctx.buffer.begin_change_group
        replace_all = false

        catch(:quit_substitute) do
          (r_start..r_end).each do |row|
            line = ctx.buffer.line_at(row)
            offset = 0

            loop do
              m = line.match(regex, offset)
              break unless m

              match_col = m.begin(0)
              match_text = m[0]

              unless replace_all
                ctx.window.cursor_y = row
                ctx.window.cursor_x = match_col
                ctx.editor.echo("replace with #{replacement} (y/n/a/q/l/Esc)?")

                key = reader.call
                case key
                when "y"
                  # replace and continue
                when "n"
                  offset = match_col + [match_text.length, 1].max
                  next
                when "a"
                  replace_all = true
                when "l"
                  # replace this one and stop
                  new_line = line[0...match_col] + line[match_col..].sub(regex, replacement)
                  ctx.buffer.replace_line!(row, new_line)
                  changed += 1
                  throw :quit_substitute
                when "q", :escape, :ctrl_c
                  throw :quit_substitute
                else
                  offset = match_col + [match_text.length, 1].max
                  next
                end
              end

              # Do the replacement
              new_line = line[0...match_col] + line[match_col..].sub(regex, replacement)
              replaced_length = new_line.length - line.length + match_text.length
              ctx.buffer.replace_line!(row, new_line)
              line = new_line
              changed += 1
              offset = match_col + [replaced_length, 1].max

              break unless flags[:global]
            end
          end
        end

        ctx.buffer.end_change_group
        changed
      end

      def count_matches_in_range(buffer, regex, r_start, r_end, global)
        total = 0
        (r_start..r_end).each do |idx|
          line = buffer.line_at(idx)
          if global
            line.scan(regex) { total += 1 }
          else
            total += 1 if line.match?(regex)
          end
        end
        total
      end

      def execute_global_sub_command(ctx, command)
        dispatcher = RuVim::Dispatcher.new
        dispatcher.dispatch_ex(ctx.editor, command)
      end

      def run_external_grep(ctx, argv:, target:)
        if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?
          raise RuVim::CommandError, "Restricted mode: :grep is disabled"
        end

        args = Array(argv)
        raise RuVim::CommandError, "Usage: :grep pattern [files...]" if args.empty?

        grepprg = ctx.editor.effective_option("grepprg", window: ctx.window, buffer: ctx.buffer) || "grep -n"
        cmd_parts = Shellwords.shellsplit(grepprg)
        expanded_args = args.flat_map { |a| (g = Dir.glob(a)).empty? ? [a] : g }

        stdout, stderr, status = Open3.capture3(*cmd_parts, *expanded_args)
        if stdout.strip.empty? && !status.success?
          msg = stderr.strip.empty? ? "No matches found" : stderr.strip
          ctx.editor.echo_error(msg)
          return
        end

        items = parse_grep_output(ctx, stdout)
        if items.empty?
          ctx.editor.echo_error("No matches found")
          return
        end

        case target
        when :quickfix
          ctx.editor.set_quickfix_list(items)
          ctx.editor.select_quickfix(0)
          ctx.editor.jump_to_location(ctx.editor.current_quickfix_item)
          ctx.editor.echo("quickfix: #{items.length} item(s)")
        when :location_list
          ctx.editor.set_location_list(items, window_id: ctx.window.id)
          ctx.editor.select_location_list(0, window_id: ctx.window.id)
          ctx.editor.jump_to_location(ctx.editor.current_location_list_item(ctx.window.id))
          ctx.editor.echo("location list: #{items.length} item(s)")
        end
      end

      def parse_grep_output(ctx, output)
        items = []
        output.each_line do |line|
          line = line.chomp
          # Parse filename:lineno:text format
          if (m = line.match(/\A(.+?):(\d+):(.*)?\z/))
            filepath = m[1]
            lineno = m[2].to_i - 1 # 0-based
            text = m[3].to_s
            buf = ensure_buffer_for_grep_file(ctx, filepath)
            items << { buffer_id: buf.id, row: lineno, col: 0, text: text }
          end
        end
        items
      end

      def ensure_buffer_for_grep_file(ctx, filepath)
        abspath = File.expand_path(filepath)
        # Check if buffer already exists for this file
        existing = ctx.editor.buffers.values.find { |b| b.path && File.expand_path(b.path) == abspath }
        return existing if existing

        # Create buffer for the file
        if File.exist?(abspath)
          ctx.editor.add_buffer_from_file(abspath)
        else
          ctx.editor.add_empty_buffer(path: abspath)
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

      def parse_vimgrep_pattern(argv)
        raw = Array(argv).join(" ").strip
        raise RuVim::CommandError, "Usage: :vimgrep /pattern/" if raw.empty?

        if raw.length >= 2 && raw[0] == raw[-1] && raw[0] !~ /[[:alnum:]\s]/
          raw[1...-1]
        else
          raw
        end
      end
    end
  end
end
