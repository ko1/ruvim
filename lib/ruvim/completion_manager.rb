# frozen_string_literal: true

require "json"
require "fileutils"

module RuVim
  class CompletionManager
      def initialize(editor:, terminal:, verbose_logger: nil)
        @editor = editor
        @terminal = terminal
        @verbose_logger = verbose_logger
        @cmdline_history = Hash.new { |h, k| h[k] = [] }
        @cmdline_history_index = nil
        @cmdline_completion = nil
        @insert_completion = nil
        @incsearch_preview = nil
      end

      # --- Command-line history ---

      def push_history(prefix, line)
        text = line.to_s
        return if text.empty?

        hist = @cmdline_history[prefix]
        hist.delete(text)
        hist << text
        hist.shift while hist.length > 100
        @cmdline_history_index = nil
      end

      def reset_history_index!
        @cmdline_history_index = nil
      end

      def load_history!
        path = history_file_path
        return unless path
        return unless File.file?(path)

        raw = File.read(path)
        data = JSON.parse(raw)
        return unless data.is_a?(Hash)

        loaded = Hash.new { |h, k| h[k] = [] }
        data.each do |prefix, items|
          key = prefix.to_s
          next unless [":", "/", "?"].include?(key)
          next unless items.is_a?(Array)

          hist = loaded[key]
          items.each do |item|
            text = item.to_s
            next if text.empty?

            hist.delete(text)
            hist << text
          end
          hist.shift while hist.length > 100
        end
        @cmdline_history = loaded
      rescue StandardError => e
        verbose_log(1, "history load error: #{e.message}")
      end

      def save_history!
        path = history_file_path
        return unless path

        payload = {
          ":" => Array(@cmdline_history[":"]).map(&:to_s).last(100),
          "/" => Array(@cmdline_history["/"]).map(&:to_s).last(100),
          "?" => Array(@cmdline_history["?"]).map(&:to_s).last(100)
        }

        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp"
        File.write(tmp, JSON.pretty_generate(payload) + "\n")
        File.rename(tmp, path)
      rescue StandardError => e
        verbose_log(1, "history save error: #{e.message}")
      end

      def history_move(delta)
        cmd = @editor.command_line
        hist = @cmdline_history[cmd.prefix]
        return if hist.empty?

        @cmdline_history_index =
          if @cmdline_history_index.nil?
            delta.negative? ? hist.length - 1 : hist.length
          else
            @cmdline_history_index + delta
          end

        @cmdline_history_index = [[@cmdline_history_index, 0].max, hist.length].min
        if @cmdline_history_index == hist.length
          cmd.replace_text("")
        else
          cmd.replace_text(hist[@cmdline_history_index])
        end
        update_incsearch_preview_if_needed
      end

      # --- Command-line completion ---

      def command_line_complete
        cmd = @editor.command_line
        return unless cmd.prefix == ":"

        ctx = ex_completion_context(cmd)
        return unless ctx

        matches = reusable_command_line_completion_matches(cmd, ctx) || ex_completion_candidates(ctx)
        case matches.length
        when 0
          clear_command_line_completion
          @editor.echo("No completion")
        when 1
          clear_command_line_completion
          cmd.replace_span(ctx[:token_start], ctx[:token_end], matches.first)
        else
          apply_wildmode_completion(cmd, ctx, matches)
        end
        update_incsearch_preview_if_needed
      end

      def clear_command_line_completion
        @cmdline_completion = nil
      end

      # --- Insert completion ---

      def clear_insert_completion
        @insert_completion = nil
      end

      def insert_complete(direction)
        state = ensure_insert_completion_state
        return unless state

        matches = state[:matches]
        if matches.empty?
          @editor.echo("No completion")
          return
        end

        if state[:index].nil? && insert_completion_noselect? && matches.length > 1
          show_insert_completion_menu(matches, selected: nil)
          state[:index] = :pending_select
          return
        end

        if state[:index].nil? && insert_completion_noinsert?
          preview_idx = direction.positive? ? 0 : matches.length - 1
          state[:index] = :pending_insert
          state[:pending_index] = preview_idx
          show_insert_completion_menu(matches, selected: preview_idx, current: matches[preview_idx])
          return
        end

        idx = state[:index]
        idx = nil if idx == :pending_select
        if idx == :pending_insert
          idx = state.delete(:pending_index) || (direction.positive? ? 0 : matches.length - 1)
        else
          idx = idx.nil? ? (direction.positive? ? 0 : matches.length - 1) : (idx + direction) % matches.length
        end
        replacement = matches[idx]

        end_col = state[:current_end_col]
        start_col = state[:start_col]
        @editor.current_buffer.delete_span(state[:row], start_col, state[:row], end_col)
        _y, new_x = @editor.current_buffer.insert_text(state[:row], start_col, replacement)
        @editor.current_window.cursor_y = state[:row]
        @editor.current_window.cursor_x = new_x
        state[:index] = idx
        state[:current_end_col] = start_col + replacement.length
        if matches.length == 1
          @editor.echo(replacement)
        else
          show_insert_completion_menu(matches, selected: idx, current: replacement)
        end
      rescue StandardError => e
        @editor.echo_error("Completion error: #{e.message}")
        clear_insert_completion
      end

      # --- Incremental search preview ---

      def incsearch_enabled?
        return false unless @editor.command_line_active?
        return false unless ["/", "?"].include?(@editor.command_line.prefix)

        !!@editor.effective_option("incsearch")
      end

      def update_incsearch_preview_if_needed
        return unless incsearch_enabled?

        cmd = @editor.command_line
        ensure_incsearch_preview_origin!(direction: (cmd.prefix == "/" ? :forward : :backward))
        pattern = cmd.text.to_s
        if pattern.empty?
          clear_incsearch_preview_state(apply: false)
          return
        end

        buf = @editor.current_buffer
        win = @editor.current_window
        origin = @incsearch_preview[:origin]
        tmp_window = RuVim::Window.new(id: -1, buffer_id: buf.id)
        tmp_window.cursor_y = origin[:row]
        tmp_window.cursor_x = origin[:col]
        regex = GlobalCommands.instance.send(:compile_search_regex, pattern, editor: @editor, window: win, buffer: buf)
        match = GlobalCommands.instance.send(:find_next_match, buf, tmp_window, regex, direction: @incsearch_preview[:direction])
        if match
          win.cursor_y = match[:row]
          win.cursor_x = match[:col]
          win.clamp_to_buffer(buf)
        end
        @incsearch_preview[:active] = true
      rescue RuVim::CommandError, RegexpError
        # Keep editing command-line without forcing an error flash on every keystroke.
      end

      def cancel_incsearch_preview_if_any
        clear_incsearch_preview_state(apply: false)
      end

      def clear_incsearch_preview_state(apply:)
        return unless @incsearch_preview

        if !apply && @incsearch_preview[:origin]
          @editor.jump_to_location(@incsearch_preview[:origin])
        end
        @incsearch_preview = nil
      end

      # --- Keyword helpers ---

      def trailing_keyword_fragment(prefix_text, window, buffer)
        cls = keyword_char_class(window, buffer)
        prefix_text.to_s[/[#{cls}]+\z/]
      rescue RegexpError
        prefix_text.to_s[/[[:alnum:]_]+\z/]
      end

      private

      def verbose_log(level, message)
        @verbose_logger&.call(level, message)
      end

      def history_file_path
        xdg_state_home = ENV["XDG_STATE_HOME"].to_s
        if !xdg_state_home.empty?
          return File.join(xdg_state_home, "ruvim", "history.json")
        end

        home = ENV["HOME"].to_s
        return nil if home.empty?

        File.join(home, ".ruvim", "history.json")
      end

      def reusable_command_line_completion_matches(cmd, ctx)
        state = @cmdline_completion
        return nil unless state
        return nil unless state[:prefix] == cmd.prefix
        return nil unless state[:kind] == ctx[:kind]
        return nil unless state[:command] == ctx[:command]
        return nil unless state[:arg_index] == ctx[:arg_index]
        return nil unless state[:token_start] == ctx[:token_start]

        before_text = cmd.text[0...ctx[:token_start]].to_s
        after_text = cmd.text[ctx[:token_end]..].to_s
        return nil unless state[:before_text] == before_text
        return nil unless state[:after_text] == after_text

        matches = Array(state[:matches]).map(&:to_s)
        return nil if matches.empty?

        current_token = cmd.text[ctx[:token_start]...ctx[:token_end]].to_s
        return nil unless current_token.empty? || matches.include?(current_token) || common_prefix(matches).start_with?(current_token) || current_token.start_with?(common_prefix(matches))

        matches
      end

      def apply_wildmode_completion(cmd, ctx, matches)
        mode_steps = wildmode_steps
        mode_steps = [:full] if mode_steps.empty?
        state = @cmdline_completion
        before_text = cmd.text[0...ctx[:token_start]].to_s
        after_text = cmd.text[ctx[:token_end]..].to_s
        same = state &&
               state[:prefix] == cmd.prefix &&
               state[:kind] == ctx[:kind] &&
               state[:command] == ctx[:command] &&
               state[:arg_index] == ctx[:arg_index] &&
               state[:token_start] == ctx[:token_start] &&
               state[:before_text] == before_text &&
               state[:after_text] == after_text &&
               state[:matches] == matches
        unless same
          state = {
            prefix: cmd.prefix,
            kind: ctx[:kind],
            command: ctx[:command],
            arg_index: ctx[:arg_index],
            token_start: ctx[:token_start],
            before_text: before_text,
            after_text: after_text,
            matches: matches.dup,
            step_index: -1,
            full_index: nil
          }
        end

        state[:step_index] += 1
        step = mode_steps[state[:step_index] % mode_steps.length]
        case step
        when :longest
          pref = common_prefix(matches)
          cmd.replace_span(ctx[:token_start], ctx[:token_end], pref) if pref.length > ctx[:prefix].length
        when :list
          show_command_line_completion_menu(matches, selected: state[:full_index], force: true)
        when :full
          state[:full_index] = state[:full_index] ? (state[:full_index] + 1) % matches.length : 0
          cmd.replace_span(ctx[:token_start], ctx[:token_end], matches[state[:full_index]])
          show_command_line_completion_menu(matches, selected: state[:full_index], force: false)
        else
          pref = common_prefix(matches)
          cmd.replace_span(ctx[:token_start], ctx[:token_end], pref) if pref.length > ctx[:prefix].length
        end

        @cmdline_completion = state
      end

      def wildmode_steps
        raw = @editor.effective_option("wildmode").to_s
        return [:full] if raw.empty?

        raw.split(",").flat_map do |tok|
          tok.to_s.split(":").map do |part|
            case part.strip.downcase
            when "longest" then :longest
            when "list" then :list
            when "full" then :full
            end
          end
        end.compact
      end

      def show_command_line_completion_menu(matches, selected:, force:)
        return unless force || @editor.effective_option("wildmenu")

        items = matches.each_with_index.map do |m, i|
          idx = i
          idx == selected ? "[#{m}]" : m
        end
        @editor.echo(compose_command_line_completion_menu(items))
      end

      def compose_command_line_completion_menu(items)
        parts = Array(items).map(&:to_s)
        return "" if parts.empty?

        width = command_line_completion_menu_width
        width = [width.to_i, 1].max
        out = +""
        shown = 0

        parts.each_with_index do |item, idx|
          token = shown.zero? ? item : " #{item}"
          if out.empty? && token.length > width
            out = token[0, width]
            shown = 1
            break
          end
          break if out.length + token.length > width

          out << token
          shown = idx + 1
        end

        if shown < parts.length
          ellipsis = (out.empty? ? "..." : " ...")
          if out.length + ellipsis.length <= width
            out << ellipsis
          elsif width >= 3
            out = out[0, width - 3] + "..."
          else
            out = "." * width
          end
        end

        out
      end

      def command_line_completion_menu_width
        return 80 unless defined?(@terminal) && @terminal && @terminal.respond_to?(:winsize)

        _rows, cols = @terminal.winsize
        [cols.to_i, 1].max
      rescue StandardError
        80
      end

      def common_prefix(strings)
        return "" if strings.empty?

        prefix = strings.first.dup
        strings[1..]&.each do |s|
          while !prefix.empty? && !s.start_with?(prefix)
            prefix = prefix[0...-1]
          end
        end
        prefix
      end

      def insert_completion_noselect?
        @editor.effective_option("completeopt").to_s.split(",").map { |s| s.strip.downcase }.include?("noselect")
      end

      def insert_completion_noinsert?
        @editor.effective_option("completeopt").to_s.split(",").map { |s| s.strip.downcase }.include?("noinsert")
      end

      def insert_completion_menu_enabled?
        opts = @editor.effective_option("completeopt").to_s.split(",").map { |s| s.strip.downcase }
        opts.include?("menu") || opts.include?("menuone")
      end

      def show_insert_completion_menu(matches, selected:, current: nil)
        if insert_completion_menu_enabled?
          limit = [@editor.effective_option("pumheight").to_i, 1].max
          items = matches.first(limit).each_with_index.map do |m, i|
            i == selected ? "[#{m}]" : m
          end
          items << "..." if matches.length > limit
          if current
            @editor.echo("#{current} (#{selected + 1}/#{matches.length}) | #{items.join(' ')}")
          else
            @editor.echo(items.join(" "))
          end
        elsif current
          @editor.echo("#{current} (#{selected + 1}/#{matches.length})")
        end
      end

      def ensure_insert_completion_state
        row = @editor.current_window.cursor_y
        col = @editor.current_window.cursor_x
        line = @editor.current_buffer.line_at(row)
        prefix = trailing_keyword_fragment(line[0...col].to_s, @editor.current_window, @editor.current_buffer)
        return nil if prefix.nil? || prefix.empty?

        start_col = col - prefix.length
        current_token = line[start_col...col].to_s
        state = @insert_completion

        if state &&
           state[:row] == row &&
           state[:start_col] == start_col &&
           state[:prefix] == prefix &&
           col == state[:current_end_col]
          return state
        end

        matches = collect_buffer_word_completions(prefix, current_word: current_token)
        @insert_completion = {
          row: row,
          start_col: start_col,
          prefix: prefix,
          matches: matches,
          index: nil,
          current_end_col: col
        }
      end

      def collect_buffer_word_completions(prefix, current_word:)
        words = []
        seen = {}
        rx = keyword_scan_regex(@editor.current_window, @editor.current_buffer)
        @editor.buffers.values.each do |buf|
          buf.lines.each do |line|
            line.scan(rx) do |w|
              next unless w.start_with?(prefix)
              next if w == current_word
              next if seen[w]

              seen[w] = true
              words << w
            end
          end
        end
        words.sort
      end

      def ensure_incsearch_preview_origin!(direction:)
        return if @incsearch_preview

        @incsearch_preview = {
          origin: @editor.current_location,
          direction: direction,
          active: false
        }
      end

      def keyword_scan_regex(window, buffer)
        cls = keyword_char_class(window, buffer)
        /[#{cls}]+/
      rescue RegexpError
        /[[:alnum:]_]+/
      end

      def keyword_char_class(window, buffer)
        raw = @editor.effective_option("iskeyword", window:, buffer:).to_s
        RuVim::KeywordChars.char_class(raw)
      rescue StandardError
        "[:alnum:]_"
      end

      def ex_completion_context(cmd)
        text = cmd.text
        cursor = cmd.cursor
        token_start = token_start_index(text, cursor)
        token_end = token_end_index(text, cursor)
        prefix = text[token_start...cursor].to_s
        before = text[0...token_start].to_s
        argv_before = before.split(/\s+/).reject(&:empty?)

        if argv_before.empty?
          {
            kind: :command,
            token_start: token_start,
            token_end: token_end,
            prefix: prefix
          }
        else
          {
            kind: :arg,
            command: argv_before.first,
            arg_index: argv_before.length - 1,
            token_start: token_start,
            token_end: token_end,
            prefix: prefix
          }
        end
      end

      def ex_completion_candidates(ctx)
        case ctx[:kind]
        when :command
          ExCommandRegistry.instance.all.flat_map { |spec| [spec.name, *spec.aliases] }.uniq.sort.select { |n| n.start_with?(ctx[:prefix]) }
        when :arg
          ex_arg_completion_candidates(ctx[:command], ctx[:arg_index], ctx[:prefix])
        else
          []
        end
      end

      def ex_arg_completion_candidates(command_name, arg_index, prefix)
        cmd = command_name.to_s
        return [] unless arg_index.zero?

        if %w[e edit w write tabnew].include?(cmd)
          return path_completion_candidates(prefix)
        end

        if %w[buffer b].include?(cmd)
          return buffer_completion_candidates(prefix)
        end

        if %w[set setlocal setglobal].include?(cmd)
          return option_completion_candidates(prefix)
        end

        if cmd == "git"
          return Git::Handler::GIT_SUBCOMMANDS.keys.sort.select { |s| s.start_with?(prefix) }
        end

        []
      end

      def path_completion_candidates(prefix)
        input = prefix.to_s
        base_dir =
          if input.empty?
            "."
          elsif input.end_with?("/")
            input
          else
            File.dirname(input)
          end
        partial = input.end_with?("/") ? "" : File.basename(input)
        pattern =
          if input.empty?
            "*"
          elsif base_dir == "."
            "#{partial}*"
          else
            File.join(base_dir, "#{partial}*")
          end
        partial_starts_with_dot = partial.start_with?(".")
        entries = Dir.glob(pattern, File::FNM_DOTMATCH).filter_map do |p|
          next if [".", ".."].include?(File.basename(p))
          next unless p.start_with?(input) || input.empty?
          next if wildignore_path?(p)
          File.directory?(p) ? "#{p}/" : p
        end
        entries.sort_by do |p|
          base = File.basename(p.to_s.sub(%r{/\z}, ""))
          hidden_rank = (!partial_starts_with_dot && base.start_with?(".")) ? 1 : 0
          [hidden_rank, p]
        end
      rescue StandardError
        []
      end

      def wildignore_path?(path)
        spec = @editor.global_options["wildignore"].to_s
        return false if spec.empty?

        flags = @editor.global_options["wildignorecase"] ? File::FNM_CASEFOLD : 0
        name = path.to_s
        base = File.basename(name)
        spec.split(",").map(&:strip).reject(&:empty?).any? do |pat|
          File.fnmatch?(pat, name, flags) || File.fnmatch?(pat, base, flags)
        end
      rescue StandardError
        false
      end

      def buffer_completion_candidates(prefix)
        pfx = prefix.to_s
        items = @editor.buffers.values.flat_map do |b|
          path = b.path.to_s
          base = path.empty? ? nil : File.basename(path)
          [b.id.to_s, path, base].compact
        end.uniq.sort
        items.select { |s| s.start_with?(pfx) }
      end

      def option_completion_candidates(prefix)
        pfx = prefix.to_s
        names = RuVim::Editor::OPTION_DEFS.keys
        tokens = names + names.map { |n| "no#{n}" } + names.map { |n| "inv#{n}" } + names.map { |n| "#{n}?" }
        tokens.uniq.sort.select { |s| s.start_with?(pfx) }
      end

      def token_start_index(text, cursor)
        i = [[cursor, 0].max, text.length].min
        i -= 1 while i.positive? && !whitespace_char?(text[i - 1])
        i
      end

      def token_end_index(text, cursor)
        i = [[cursor, 0].max, text.length].min
        i += 1 while i < text.length && !whitespace_char?(text[i])
        i
      end

      def whitespace_char?(ch)
        ch && ch.match?(/\s/)
      end
  end
end
