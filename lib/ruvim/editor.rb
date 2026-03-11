# frozen_string_literal: true

module RuVim
  class Editor
    OPTION_DEFS = {
      "number" => { default_scope: :window, type: :bool, default: false },
      "relativenumber" => { default_scope: :window, type: :bool, default: false },
      "wrap" => { default_scope: :window, type: :bool, default: true },
      "linebreak" => { default_scope: :window, type: :bool, default: false },
      "breakindent" => { default_scope: :window, type: :bool, default: false },
      "cursorline" => { default_scope: :window, type: :bool, default: false },
      "scrolloff" => { default_scope: :window, type: :int, default: 0 },
      "sidescrolloff" => { default_scope: :window, type: :int, default: 0 },
      "numberwidth" => { default_scope: :window, type: :int, default: 4 },
      "colorcolumn" => { default_scope: :window, type: :string, default: nil },
      "signcolumn" => { default_scope: :window, type: :string, default: "auto" },
      "list" => { default_scope: :window, type: :bool, default: false },
      "listchars" => { default_scope: :window, type: :string, default: "tab:>-,trail:-,nbsp:+" },
      "showbreak" => { default_scope: :window, type: :string, default: ">" },
      "showmatch" => { default_scope: :global, type: :bool, default: false },
      "matchtime" => { default_scope: :global, type: :int, default: 5 },
      "whichwrap" => { default_scope: :global, type: :string, default: "" },
      "virtualedit" => { default_scope: :global, type: :string, default: "" },
      "ignorecase" => { default_scope: :global, type: :bool, default: false },
      "smartcase" => { default_scope: :global, type: :bool, default: false },
      "hlsearch" => { default_scope: :global, type: :bool, default: true },
      "incsearch" => { default_scope: :global, type: :bool, default: false },
      "splitbelow" => { default_scope: :global, type: :bool, default: false },
      "splitright" => { default_scope: :global, type: :bool, default: false },
      "hidden" => { default_scope: :global, type: :bool, default: false },
      "autowrite" => { default_scope: :global, type: :bool, default: false },
      "clipboard" => { default_scope: :global, type: :string, default: "" },
      "timeoutlen" => { default_scope: :global, type: :int, default: 1000 },
      "ttimeoutlen" => { default_scope: :global, type: :int, default: 50 },
      "backspace" => { default_scope: :global, type: :string, default: "indent,eol,start" },
      "completeopt" => { default_scope: :global, type: :string, default: "menu,menuone,noselect" },
      "pumheight" => { default_scope: :global, type: :int, default: 10 },
      "wildmode" => { default_scope: :global, type: :string, default: "full" },
      "wildignore" => { default_scope: :global, type: :string, default: "" },
      "wildignorecase" => { default_scope: :global, type: :bool, default: false },
      "wildmenu" => { default_scope: :global, type: :bool, default: false },
      "termguicolors" => { default_scope: :global, type: :bool, default: false },
      "path" => { default_scope: :buffer, type: :string, default: nil },
      "suffixesadd" => { default_scope: :buffer, type: :string, default: nil },
      "textwidth" => { default_scope: :buffer, type: :int, default: 0 },
      "formatoptions" => { default_scope: :buffer, type: :string, default: nil },
      "expandtab" => { default_scope: :buffer, type: :bool, default: false },
      "shiftwidth" => { default_scope: :buffer, type: :int, default: 2 },
      "softtabstop" => { default_scope: :buffer, type: :int, default: 0 },
      "autoindent" => { default_scope: :buffer, type: :bool, default: true },
      "smartindent" => { default_scope: :buffer, type: :bool, default: true },
      "iskeyword" => { default_scope: :buffer, type: :string, default: nil },
      "tabstop" => { default_scope: :buffer, type: :int, default: 2 },
      "filetype" => { default_scope: :buffer, type: :string, default: nil },
      "onsavehook" => { default_scope: :buffer, type: :bool, default: true },
      "undofile" => { default_scope: :global, type: :bool, default: true },
      "undodir" => { default_scope: :global, type: :string, default: nil },
      "grepprg" => { default_scope: :global, type: :string, default: "grep -nH" },
      "grepformat" => { default_scope: :global, type: :string, default: "%f:%l:%m" },
      "runprg" => { default_scope: :buffer, type: :string, default: nil },
      "spell" => { default_scope: :buffer, type: :bool, default: false },
      "spelllang" => { default_scope: :buffer, type: :string, default: "en" }
    }.freeze

    attr_reader :buffers, :windows, :layout_tree

    # Editor state
    attr_accessor :current_window_id, :mode, :message, :pending_count, :alternate_buffer_id, :restricted_mode, :current_window_view_height_hint

    # External dependencies (injected by App, settable for tests)
    attr_accessor :keymap_manager, :app_action_handler, :shell_executor, :stream_mixer, :confirm_key_reader, :normal_key_feeder

    def initialize(restricted_mode: false, stream_mixer: nil, keymap_manager: nil,
                   app_action_handler: nil, shell_executor: nil, confirm_key_reader: nil,
                   normal_key_feeder: nil)
      @buffers = {}
      @windows = {}
      @layout_tree = nil
      @tabpages = []
      @current_tabpage_index = nil
      @next_tabpage_id = 1
      @suspend_tab_autosave = false
      @next_buffer_id = 1
      @next_window_id = 1
      @current_window_id = nil
      @alternate_buffer_id = nil
      @mode = :normal
      @message = ""
      @message_kind = :info
      @message_deadline = nil
      @pending_count = nil
      @restricted_mode = restricted_mode
      @current_window_view_height_hint = 1
      @running = true
      @stream_mixer = stream_mixer
      @keymap_manager = keymap_manager
      @app_action_handler = app_action_handler
      @shell_executor = shell_executor
      @confirm_key_reader = confirm_key_reader
      @normal_key_feeder = normal_key_feeder
      @global_options = default_global_options
      @command_line = CommandLine.new
      @last_search = nil
      @hlsearch_suppressed = false
      @last_find = nil
      @registers = {}
      @active_register_name = nil
      @local_marks = Hash.new { |h, k| h[k] = {} }
      @global_marks = {}
      @jumplist = []
      @jump_index = nil
      @macros = {}
      @macro_recording = nil
      @visual_state = nil
      @rich_state = nil
      @quickfix_list = { items: [], index: nil }
      @location_lists = Hash.new { |h, k| h[k] = { items: [], index: nil } }
      @arglist = []
      @arglist_index = 0
      @hit_enter_lines = nil
      @run_history = {}  # buffer_id => last run command (unexpanded)
      @run_output_buffer_id = nil
      @spell_checker = nil
    end

    def spell_checker
      @spell_checker ||= SpellChecker.new
    end

    def running?
      @running
    end

    def restricted_mode?
      !!@restricted_mode
    end

    def request_quit!
      @running = false
    end

    def run_history
      @run_history
    end

    def run_output_buffer_id
      @run_output_buffer_id
    end

    def run_output_buffer_id=(id)
      @run_output_buffer_id = id
    end

    def command_line
      @command_line
    end

    def global_options
      @global_options
    end

    def command_line_prefix
      @command_line.prefix
    end

    def last_search
      @last_search
    end

    def last_find
      @last_find
    end

    def set_last_search(pattern:, direction:)
      @last_search = { pattern: pattern, direction: direction }
      @hlsearch_suppressed = false
    end

    def suppress_hlsearch!
      @hlsearch_suppressed = true
    end

    def hlsearch_suppressed?
      @hlsearch_suppressed
    end

    def set_last_find(char:, direction:, till:)
      @last_find = { char: char, direction: direction, till: !!till }
    end

    def current_window
      @windows.fetch(@current_window_id)
    end

    def current_buffer
      @buffers.fetch(current_window.buffer_id)
    end

    def stream_stop_or_cancel!
      handler = current_buffer&.stream&.stop_handler
      return false unless handler

      handler.call
    end

    def invoke_app_action(name, **kwargs)
      handler = @app_action_handler
      return false unless handler

      handler.call(name, **kwargs)
      true
    end

    def option_def(name)
      OPTION_DEFS[name.to_s]
    end

    def option_default_scope(name)
      option_def(name)&.fetch(:default_scope, :global) || :global
    end

    def effective_option(name, window: nil, buffer: nil)
      key = name.to_s
      w = window || current_window
      b = buffer || current_buffer
      if w && w.options.key?(key)
        w.options[key]
      elsif b && b.options.key?(key)
        b.options[key]
      else
        @global_options[key]
      end
    end

    def get_option(name, scope: :effective, window: nil, buffer: nil)
      key = name.to_s
      case scope
      when :global
        @global_options[key]
      when :buffer
        (buffer || current_buffer)&.options&.[](key)
      when :window
        (window || current_window)&.options&.[](key)
      else
        effective_option(key, window: window, buffer: buffer)
      end
    end

    def set_option(name, value, scope: :auto, window: nil, buffer: nil)
      key = name.to_s
      value = coerce_option_value(key, value)
      actual_scope = (scope == :auto ? option_default_scope(key) : scope)
      case actual_scope
      when :global
        @global_options[key] = value
      when :buffer
        b = buffer || current_buffer
        raise RuVim::CommandError, "No current buffer" unless b
        b.options[key] = value
      when :window
        w = window || current_window
        raise RuVim::CommandError, "No current window" unless w
        w.options[key] = value
      else
        raise RuVim::CommandError, "Unknown option scope: #{actual_scope}"
      end
      value
    end

    def option_snapshot(window: nil, buffer: nil)
      w = window || current_window
      b = buffer || current_buffer
      keys = (OPTION_DEFS.keys + @global_options.keys + (b&.options&.keys || []) + (w&.options&.keys || [])).uniq.sort
      keys.map do |k|
        {
          name: k,
          effective: get_option(k, scope: :effective, window: w, buffer: b),
          global: get_option(k, scope: :global, window: w, buffer: b),
          buffer: get_option(k, scope: :buffer, window: w, buffer: b),
          window: get_option(k, scope: :window, window: w, buffer: b)
        }
      end
    end

    def detect_filetype(path)
      p = path.to_s
      return nil if p.empty?

      base = File.basename(p)

      # Basename-based detection (exact match, then prefix)
      base_ft = Lang::Registry.detect_by_basename(base)
      return base_ft if base_ft

      # Extension-based detection
      ext_ft = Lang::Registry.detect_by_extension(File.extname(base))
      return ext_ft if ext_ft

      detect_filetype_from_shebang(p)
    end

    def registers
      @registers
    end

    def set_register(name = "\"", text:, type: :charwise)
      key = name.to_s
      return { text: text, type: type } if key == "_"

      payload = write_register_payload(key, text: text, type: type)
      write_clipboard_register(key, payload)
      if key == "\""
        if (default_clip = clipboard_default_register_key)
          mirror = write_register_payload(default_clip, text: payload[:text], type: payload[:type])
          write_clipboard_register(default_clip, mirror)
        end
      end
      @registers["\""] = payload unless key == "\""
      payload
    end

    def store_operator_register(name = "\"", text:, type:, kind:)
      key = (name || "\"")
      payload = { text: text, type: type }
      return payload if key == "_"

      written = set_register(key, text: payload[:text], type: payload[:type])
      op_payload = dup_register_payload(written)

      case kind
      when :yank
        @registers["0"] = dup_register_payload(op_payload)
      when :delete, :change
        rotate_delete_registers!(op_payload)
      end

      written
    end

    def get_register(name = "\"")
      key = name.to_s.downcase
      if key == "\""
        if (default_clip = clipboard_default_register_key)
          if (payload = read_clipboard_register(default_clip))
            @registers["\""] = dup_register_payload(payload)
            return @registers["\""]
          end
        end
      end
      return read_clipboard_register(key) if clipboard_register?(key)

      @registers[key]
    end

    def set_active_register(name)
      @active_register_name = name.to_s
    end

    def active_register_name
      @active_register_name
    end

    def consume_active_register(default = "\"")
      name = @active_register_name || default
      @active_register_name = nil
      name
    end

    def visual_state
      @visual_state
    end

    def macros
      @macros
    end

    def macro_recording?
      !@macro_recording.nil?
    end

    def macro_recording_name
      @macro_recording && @macro_recording[:name]
    end

    def start_macro_recording(name)
      reg = name.to_s
      return false unless reg.match?(/\A[A-Za-z0-9]\z/)

      @macro_recording = { name: reg, keys: [] }
      true
    end

    def stop_macro_recording
      rec = @macro_recording
      @macro_recording = nil
      return nil unless rec

      name = rec[:name]
      keys = rec[:keys]
      if name.match?(/\A[A-Z]\z/)
        base = name.downcase
        @macros[base] = [*(@macros[base] || []), *keys]
        @macros[base]
      else
        @macros[name.downcase] = keys
      end
    end

    def record_macro_key(key)
      return unless @macro_recording

      @macro_recording[:keys] << dup_macro_key(key)
    end

    def macro_keys(name)
      @macros[name.to_s.downcase]
    end

    def current_location
      { buffer_id: current_buffer.id, row: current_window.cursor_y, col: current_window.cursor_x }
    end

    def set_mark(name, window = current_window)
      mark = name.to_s
      return false unless mark.match?(/\A[A-Za-z]\z/)

      loc = { buffer_id: window.buffer_id, row: window.cursor_y, col: window.cursor_x }
      if mark.match?(/\A[a-z]\z/)
        @local_marks[window.buffer_id][mark] = loc
      else
        @global_marks[mark] = loc
      end
      true
    end

    def mark_location(name, buffer_id: current_buffer.id)
      mark = name.to_s
      return nil unless mark.match?(/\A[A-Za-z]\z/)

      if mark.match?(/\A[a-z]\z/)
        @local_marks[buffer_id][mark]
      else
        @global_marks[mark]
      end
    end

    def push_jump_location(location = current_location)
      loc = normalize_location(location)
      return nil unless loc

      if @jump_index && @jump_index < @jumplist.length - 1
        @jumplist = @jumplist[0..@jump_index]
      end
      @jumplist << loc unless same_location?(@jumplist.last, loc)
      @jump_index = @jumplist.length - 1 unless @jumplist.empty?
      loc
    end

    def jump_older(linewise: false)
      return nil if @jumplist.empty?

      if @jump_index.nil?
        push_jump_location(current_location)
      else
        @jump_index = [@jump_index - 1, 0].max
      end
      jump_to_location(@jumplist[@jump_index], linewise:)
    end

    def jump_newer(linewise: false)
      return nil if @jumplist.empty? || @jump_index.nil?

      next_idx = @jump_index + 1
      return nil if next_idx >= @jumplist.length

      @jump_index = next_idx
      jump_to_location(@jumplist[@jump_index], linewise:)
    end

    def jump_to_mark(name, linewise: false)
      loc = mark_location(name)
      return nil unless loc

      jump_to_location(loc, linewise:)
    end

    def visual_active?
      !@visual_state.nil?
    end

    def enter_visual(mode)
      @mode = mode
      @visual_state = {
        mode: mode,
        anchor_y: current_window.cursor_y,
        anchor_x: current_window.cursor_x
      }
      @pending_count = nil
    end

    def clear_visual
      @visual_state = nil
    end

    def visual_selection(window = current_window)
      return nil unless @visual_state

      ay = @visual_state[:anchor_y]
      ax = @visual_state[:anchor_x]
      cy = window.cursor_y
      cx = window.cursor_x
      case @visual_state[:mode]
      when :visual_line
        start_row, end_row = [ay, cy].minmax
        {
          mode: :linewise,
          start_row: start_row,
          start_col: 0,
          end_row: end_row,
          end_col: current_buffer.line_length(end_row)
        }
      when :visual_block
        start_row, end_row = [ay, cy].minmax
        start_col, end_col = [ax, cx].minmax
        {
          mode: :blockwise,
          start_row: start_row,
          start_col: start_col,
          end_row: end_row,
          end_col: end_col + 1
        }
      else
        if ay < cy || (ay == cy && ax <= cx)
          s_row, s_col, e_row, e_col = [ay, ax, cy, cx]
        else
          s_row, s_col, e_row, e_col = [cy, cx, ay, ax]
        end
        {
          mode: :charwise,
          start_row: s_row,
          start_col: s_col,
          end_row: e_row,
          end_col: e_col + 1
        }
      end
    end

    def rich_state
      @rich_state
    end

    def rich_mode?
      @mode == :rich
    end

    def enter_rich_mode(format:, delimiter:)
      @mode = :rich
      @pending_count = nil
      @rich_state = { format: format, delimiter: delimiter }
    end

    def exit_rich_mode
      @rich_state = nil
      enter_normal_mode
    end

    def hit_enter_active?
      @mode == :hit_enter
    end

    def hit_enter_lines
      @hit_enter_lines
    end

    def enter_hit_enter_mode(lines)
      @mode = :hit_enter
      @hit_enter_lines = Array(lines)
      @pending_count = nil
    end

    def exit_hit_enter_mode
      @hit_enter_lines = nil
      enter_normal_mode
    end

    def echo_multiline(lines)
      lines = Array(lines)
      if lines.length <= 1
        echo(lines.first.to_s)
      else
        enter_hit_enter_mode(lines)
      end
    end

    def add_empty_buffer(path: nil)
      id = next_buffer_id
      buffer = Buffer.new(id:, path:)
      assign_detected_filetype(buffer)
      @buffers[id] = buffer
      buffer
    end

    def add_virtual_buffer(kind:, name:, lines:, filetype: nil, readonly: true, modifiable: false)
      id = next_buffer_id
      buffer = Buffer.new(id:, lines:, kind:, name:, readonly:, modifiable:)
      assign_filetype(buffer, filetype) if filetype
      @buffers[id] = buffer
      buffer
    end

    def add_buffer_from_file(path)
      id = next_buffer_id
      buffer = Buffer.from_file(id:, path:)
      assign_detected_filetype(buffer)
      load_undo_file_for(buffer)
      @buffers[id] = buffer
      buffer
    end

    def add_window(buffer_id:)
      id = next_window_id
      window = Window.new(id:, buffer_id:)
      @windows[id] = window
      leaf = { type: :window, id: id }
      if @layout_tree.nil?
        @layout_tree = leaf
      else
        # Append as sibling — used for initial bootstrap only
        if @layout_tree[:type] == :window
          @layout_tree = { type: :hsplit, children: [@layout_tree, leaf] }
        else
          @layout_tree[:children] << leaf
        end
      end
      @current_window_id ||= id
      ensure_initial_tabpage!
      save_current_tabpage_state! unless @suspend_tab_autosave
      window
    end

    def split_current_window(layout: :horizontal, place: :after)
      save_current_tabpage_state! unless @suspend_tab_autosave
      src = current_window
      id = next_window_id
      win = Window.new(id:, buffer_id: src.buffer_id)
      @windows[id] = win
      ensure_initial_tabpage!
      win.cursor_x = src.cursor_x
      win.cursor_y = src.cursor_y
      win.row_offset = src.row_offset
      win.col_offset = src.col_offset

      split_type = (layout == :vertical ? :vsplit : :hsplit)
      new_leaf = { type: :window, id: win.id }

      @layout_tree = tree_split_leaf(@layout_tree, src.id, split_type, new_leaf, place)

      @current_window_id = win.id
      save_current_tabpage_state! unless @suspend_tab_autosave
      win
    end

    def close_current_window
      close_window(@current_window_id)
    end

    def close_window(id)
      leaves = tree_leaves(@layout_tree)
      return nil if leaves.empty?
      return nil if leaves.length <= 1
      return nil unless leaves.include?(id)

      save_current_tabpage_state! unless @suspend_tab_autosave
      idx = leaves.index(id) || 0
      @windows.delete(id)
      @location_lists.delete(id)

      @layout_tree = tree_remove(@layout_tree, id)

      new_leaves = tree_leaves(@layout_tree)
      @current_window_id = new_leaves[[idx, new_leaves.length - 1].min] if @current_window_id == id
      @current_window_id ||= new_leaves.first
      save_current_tabpage_state! unless @suspend_tab_autosave
      current_window
    end

    def close_other_windows
      leaves = tree_leaves(@layout_tree)
      return if leaves.length <= 1

      save_current_tabpage_state! unless @suspend_tab_autosave
      leaves.each do |wid|
        next if wid == @current_window_id

        @windows.delete(wid)
        @location_lists.delete(wid)
      end
      @layout_tree = { type: :window, id: @current_window_id }
      save_current_tabpage_state! unless @suspend_tab_autosave
    end

    def resize_window(dir, amount = 1)
      return if window_count <= 1

      save_current_tabpage_state! unless @suspend_tab_autosave
      _split_type, parent, child_idx = find_parent_split(@layout_tree, @current_window_id, dir)
      return unless parent

      parent[:weights] ||= Array.new(parent[:children].length, 1.0)
      weights = parent[:weights]

      case dir
      when :height_increase
        weights[child_idx] += amount * 0.1
      when :height_decrease
        weights[child_idx] = [weights[child_idx] - amount * 0.1, 0.1].max
      when :width_increase
        weights[child_idx] += amount * 0.1
      when :width_decrease
        weights[child_idx] = [weights[child_idx] - amount * 0.1, 0.1].max
      end
      save_current_tabpage_state! unless @suspend_tab_autosave
    end

    def equalize_windows
      clear_weights(@layout_tree)
    end

    def close_current_tabpage
      ensure_initial_tabpage!
      return nil if @tabpages.length <= 1

      save_current_tabpage_state!
      removed = @tabpages.delete_at(@current_tabpage_index)
      removed_tree = removed && removed[:layout_tree]
      tree_leaves(removed_tree).each do |wid|
        @windows.delete(wid)
        @location_lists.delete(wid)
      end
      @current_tabpage_index = [@current_tabpage_index, @tabpages.length - 1].min
      load_tabpage_state!(@tabpages[@current_tabpage_index])
      current_window
    end

    def focus_window(id)
      return nil unless @windows.key?(id)

      @current_window_id = id
      save_current_tabpage_state! unless @suspend_tab_autosave
      current_window
    end

    def focus_next_window
      order = window_order
      return current_window if order.length <= 1

      idx = order.index(@current_window_id) || 0
      focus_window(order[(idx + 1) % order.length])
    end

    def focus_prev_window
      order = window_order
      return current_window if order.length <= 1

      idx = order.index(@current_window_id) || 0
      focus_window(order[(idx - 1) % order.length])
    end

    def focus_window_direction(dir)
      leaves = tree_leaves(@layout_tree)
      return current_window if leaves.length <= 1

      rects = tree_compute_rects(@layout_tree, top: 0.0, left: 0.0, height: 1.0, width: 1.0)
      cur = rects[@current_window_id]
      return current_window unless cur

      best_id = nil
      best_dist = Float::INFINITY
      cur_cx = cur[:left] + cur[:width] / 2.0
      cur_cy = cur[:top] + cur[:height] / 2.0

      rects.each do |wid, r|
        next if wid == @current_window_id
        rcx = r[:left] + r[:width] / 2.0
        rcy = r[:top] + r[:height] / 2.0

        in_direction = case dir
                       when :left  then rcx < cur_cx
                       when :right then rcx > cur_cx
                       when :up    then rcy < cur_cy
                       when :down  then rcy > cur_cy
                       end
        next unless in_direction

        dist = (rcx - cur_cx).abs + (rcy - cur_cy).abs
        if dist < best_dist
          best_dist = dist
          best_id = wid
        end
      end

      best_id ? focus_window(best_id) : current_window
    end

    def switch_to_buffer(buffer_id)
      prev_buffer_id = current_window&.buffer_id
      current_window.buffer_id = buffer_id
      current_window.cursor_x = 0
      current_window.cursor_y = 0
      current_window.row_offset = 0
      current_window.col_offset = 0
      if prev_buffer_id && prev_buffer_id != buffer_id
        @alternate_buffer_id = prev_buffer_id
      end
      save_current_tabpage_state! unless @suspend_tab_autosave
      current_window
    end

    def open_path(path)
      loc = RuVim::GlobalCommands.parse_path_with_location(path)
      actual_path = loc[:path]

      result = if @stream_mixer
                 @stream_mixer.open_path_with_large_file_support(actual_path)
               else
                 open_path_sync(actual_path)
               end

      if loc[:line]
        w = current_window
        b = current_buffer
        w.cursor_y = [[loc[:line] - 1, 0].max, b.line_count - 1].min
        w.cursor_x = loc[:col].to_i if loc[:col]
        w.cursor_x = 0 unless loc[:col]
        w.clamp_to_buffer(b)
      end

      result
    end

    def open_path_sync(path)
      buffer = add_buffer_from_file(path)
      switch_to_buffer(buffer.id)
      echo("[New File]") unless path && File.exist?(path)
      buffer
    end

    def ensure_bootstrap_buffer!
      return unless @buffers.empty?

      buffer = add_empty_buffer
      add_window(buffer_id: buffer.id)
      ensure_initial_tabpage!
    end

    def show_help_buffer!(title:, lines:, filetype: "help")
      buffer = add_virtual_buffer(
        kind: :help,
        name: title,
        lines: Array(lines),
        filetype: filetype,
        readonly: true,
        modifiable: false
      )
      switch_to_buffer(buffer.id)
      echo(title)
      buffer
    end

    def show_intro_buffer_if_applicable!
      return unless @buffers.length == 1
      return unless current_buffer.file_buffer?
      return unless current_buffer.path.nil?
      return unless current_buffer.lines == [""]
      return if current_buffer.modified?

      current_buffer.replace_all_lines!(intro_lines)
      current_buffer.configure_special!(kind: :intro, name: "[Intro]", readonly: true, modifiable: false)
      current_buffer.modified = false
      assign_filetype(current_buffer, "help")
      current_window.cursor_x = 0
      current_window.cursor_y = 0
      current_window.row_offset = 0
      current_window.col_offset = 0
      clear_message
      current_buffer
    end

    def materialize_intro_buffer!
      return false unless current_buffer.intro_buffer?

      current_buffer.become_normal_empty_buffer!
      assign_filetype(current_buffer, nil)
      current_window.cursor_x = 0
      current_window.cursor_y = 0
      current_window.row_offset = 0
      current_window.col_offset = 0
      true
    end

    def buffer_ids
      @buffers.keys
    end

    def next_buffer_id_from(current_id, step = 1)
      ids = buffer_ids
      return nil if ids.empty?

      idx = ids.index(current_id) || 0
      ids[(idx + step) % ids.length]
    end

    def delete_buffer(buffer_id)
      buffer = @buffers[buffer_id]
      return nil unless buffer

      if @buffers.length <= 1
        replacement = add_empty_buffer
      else
        replacement = nil
      end

      fallback_id =
        if replacement
          replacement.id
        else
          candidates = @buffers.keys.reject { |bid| bid == buffer_id }
          alt = @alternate_buffer_id
          (alt && alt != buffer_id && @buffers.key?(alt)) ? alt : candidates.first
        end

      @windows.each_value do |win|
        next unless win.buffer_id == buffer_id
        next unless fallback_id

        win.buffer_id = fallback_id
        win.cursor_x = 0
        win.cursor_y = 0
        win.row_offset = 0
        win.col_offset = 0
      end

      @buffers.delete(buffer_id)
      @local_marks.delete(buffer_id)
      @alternate_buffer_id = nil if @alternate_buffer_id == buffer_id
      save_current_tabpage_state! unless @suspend_tab_autosave
      ensure_bootstrap_buffer! if @buffers.empty?
      true
    end

    def window_order
      tree_leaves(@layout_tree)
    end

    def window_layout
      return :single if @layout_tree.nil? || @layout_tree[:type] == :window
      case @layout_tree[:type]
      when :vsplit then :vertical
      when :hsplit then :horizontal
      else :single
      end
    end

    def tabpages
      @tabpages
    end

    def current_tabpage_index
      @current_tabpage_index || 0
    end

    def current_tabpage_number
      current_tabpage_index + 1
    end

    def tabpage_count
      @tabpages.length
    end

    def tabpage_windows(tab)
      tree_leaves(tab[:layout_tree])
    end

    def window_count
      tree_leaves(@layout_tree).length
    end

    def quickfix_items
      @quickfix_list[:items]
    end

    def quickfix_index
      @quickfix_list[:index]
    end

    def set_quickfix_list(items)
      ary = Array(items).map { |it| normalize_location(it)&.merge(text: (it[:text] || it["text"]).to_s) }.compact
      @quickfix_list = { items: ary, index: nil }
      @quickfix_list
    end

    def current_quickfix_item
      idx = @quickfix_list[:index]
      idx ? @quickfix_list[:items][idx] : nil
    end

    def move_quickfix(step)
      items = @quickfix_list[:items]
      return nil if items.empty?

      cur = @quickfix_list[:index]
      @quickfix_list[:index] = if cur.nil?
                                  step.to_i > 0 ? 0 : items.length - 1
                                else
                                  (cur + step.to_i) % items.length
                                end
      current_quickfix_item
    end

    def select_quickfix(index)
      items = @quickfix_list[:items]
      return nil if items.empty?

      i = [[index.to_i, 0].max, items.length - 1].min
      @quickfix_list[:index] = i
      current_quickfix_item
    end

    def location_list(window_id = current_window_id)
      @location_lists[window_id]
    end

    def location_items(window_id = current_window_id)
      location_list(window_id)[:items]
    end

    def set_location_list(items, window_id: current_window_id)
      ary = Array(items).map { |it| normalize_location(it)&.merge(text: (it[:text] || it["text"]).to_s) }.compact
      @location_lists[window_id] = { items: ary, index: nil }
      @location_lists[window_id]
    end

    def current_location_list_item(window_id = current_window_id)
      list = location_list(window_id)
      idx = list[:index]
      idx ? list[:items][idx] : nil
    end

    def move_location_list(step, window_id: current_window_id)
      list = location_list(window_id)
      items = list[:items]
      return nil if items.empty?

      cur = list[:index]
      list[:index] = if cur.nil?
                       step.to_i > 0 ? 0 : items.length - 1
                     else
                       (cur + step.to_i) % items.length
                     end
      current_location_list_item(window_id)
    end

    def select_location_list(index, window_id: current_window_id)
      list = location_list(window_id)
      items = list[:items]
      return nil if items.empty?

      i = [[index.to_i, 0].max, items.length - 1].min
      list[:index] = i
      current_location_list_item(window_id)
    end

    # Check if the path from root to the current window passes through
    # a split node matching the direction's axis. Used by focus_or_split
    # to decide whether to split or stay put at edges.
    #   left/right → check for :vsplit ancestor
    #   up/down    → check for :hsplit ancestor
    def has_split_ancestor_on_axis?(dir)
      target_type = case dir
                    when :left, :right then :vsplit
                    when :up, :down then :hsplit
                    end
      tree_path_has_split_type?(@layout_tree, @current_window_id, target_type)
    end

    def find_window_ids_by_buffer_kind(kind)
      window_order.select do |wid|
        win = @windows[wid]
        buf = win && @buffers[win.buffer_id]
        buf && buf.kind == kind
      end
    end

    def tabnew(path: nil)
      ensure_initial_tabpage!
      save_current_tabpage_state!

      with_tab_autosave_suspended do
        @layout_tree = nil
        @current_window_id = nil

        buffer = path ? add_buffer_from_file(path) : add_empty_buffer
        add_window(buffer_id: buffer.id)
        tab = new_tabpage_snapshot
        @tabpages << tab
        @current_tabpage_index = @tabpages.length - 1
        load_tabpage_state!(tab)
        return tab
      end
    end

    def tabnext(step = 1)
      return nil if @tabpages.empty?
      save_current_tabpage_state!
      @current_tabpage_index = (@current_tabpage_index + step) % @tabpages.length
      load_tabpage_state!(@tabpages[@current_tabpage_index])
    end

    def tabprev(step = 1)
      tabnext(-step)
    end

    def enter_normal_mode
      @mode = :normal
      @pending_count = nil
      clear_visual
      @rich_state = nil
    end

    def enter_insert_mode
      @mode = :insert
      @pending_count = nil
    end

    def enter_command_line_mode(prefix = ":")
      @mode = :command_line
      @command_line.reset(prefix:)
      @pending_count = nil
    end

    def cancel_command_line
      @command_line.clear
      leave_command_line
    end

    def leave_command_line
      if @rich_state
        @mode = :rich
        @pending_count = nil
      else
        enter_normal_mode
      end
    end

    def echo(msg)
      @message_kind = :info
      if @echo_accumulator
        @echo_accumulator << msg.to_s
      else
        @message = msg.to_s
      end
      @message_deadline = nil
    end

    def with_echo_accumulation
      @echo_accumulator = []
      yield
      unless @echo_accumulator.empty?
        echo_multiline(@echo_accumulator)
      end
    ensure
      @echo_accumulator = nil
    end

    def echo_temporary(msg, duration_seconds:)
      @message_kind = :info
      @message = msg.to_s
      dur = duration_seconds.to_f
      @message_deadline = dur.positive? ? (Process.clock_gettime(Process::CLOCK_MONOTONIC) + dur) : nil
    rescue StandardError
      @message_deadline = nil
    end

    def echo_error(msg)
      @message_kind = :error
      @message = msg.to_s
      @message_deadline = nil
    end

    def clear_message
      @message_kind = :info
      @message = ""
      @message_deadline = nil
    end

    def message_error?
      !@message.to_s.empty? && @message_kind == :error
    end

    def transient_message_timeout_seconds(now: nil)
      return nil unless @message_deadline
      return nil if message_error?
      return nil if command_line_active?

      now ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [@message_deadline - now, 0.0].max
    rescue StandardError
      nil
    end

    def clear_expired_transient_message!(now: nil)
      return false unless @message_deadline
      return false if message_error?
      return false if command_line_active?

      now ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return false if now < @message_deadline

      clear_message
      true
    rescue StandardError
      false
    end

    def text_viewport_size(rows:, cols:)
      # Reserve one status row + one command/error row at the bottom.
      text_rows = rows - 2
      [text_rows, cols]
    end

    def command_line_active?
      @mode == :command_line
    end

    def command_area_active?
      command_line_active? || message_error?
    end

    def assign_filetype(buffer, ft)
      buffer.options["filetype"] = ft
      buffer.lang_module = resolve_lang_module(ft)
      apply_filetype_defaults(buffer, ft)
    end

    def apply_filetype_defaults(buffer, ft)
      Lang::Registry.buffer_defaults_for(ft).each do |key, value|
        buffer.options[key] = value unless buffer.options.key?(key)
      end
    end

    def resolved_undodir
      dir = get_option("undodir", scope: :global)
      return dir if dir && !dir.empty?

      xdg = ENV["XDG_DATA_HOME"]
      base = (xdg && !xdg.empty?) ? xdg : File.join(Dir.home, ".local", "share")
      File.join(base, "ruvim", "undo")
    end

    def load_undo_file_for(buffer)
      return unless get_option("undofile", scope: :global)

      buffer.load_undo_file(resolved_undodir)
    end

    def save_undo_file_for(buffer)
      return unless get_option("undofile", scope: :global)

      buffer.save_undo_file(resolved_undodir)
    end

    private

    def resolve_lang_module(ft)
      Lang::Registry.resolve_module(ft)
    end

    def detect_filetype_from_shebang(path)
      line = read_first_line(path)
      return nil unless line.start_with?("#!")

      cmd = shebang_command_name(line)
      return nil if cmd.nil? || cmd.empty?

      Lang::Registry.detect_by_shebang(cmd)
    rescue StandardError
      nil
    end

    def read_first_line(path)
      return "" unless path && !path.empty?
      return "" unless File.file?(path)

      File.open(path, "rb") do |f|
        (f.gets || "").to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
    rescue StandardError
      ""
    end

    def shebang_command_name(line)
      src = line.to_s.sub(/\A#!/, "").strip
      return nil if src.empty?

      tokens = src.split(/\s+/)
      return nil if tokens.empty?

      prog = tokens[0].to_s
      if File.basename(prog) == "env"
        i = 1
        while i < tokens.length && tokens[i].start_with?("-")
          if tokens[i] == "-S"
            i += 1
            break
          end
          i += 1
        end
        prog = tokens[i].to_s
      end

      File.basename(prog)
    end

    def default_global_options
      OPTION_DEFS.each_with_object({}) { |(k, v), h| h[k] = v[:default] }
    end

    def coerce_option_value(name, value)
      defn = option_def(name)
      return value unless defn

      case defn[:type]
      when :bool
        !!value
      when :int
        iv = value.is_a?(Integer) ? value : Integer(value)
        raise RuVim::CommandError, "#{name} must be >= 0" if iv.negative?
        iv
      when :string
        value.nil? ? nil : value.to_s
      else
        value
      end
    rescue ArgumentError, TypeError
      raise RuVim::CommandError, "Invalid value for #{name}: #{value.inspect}"
    end

    def write_register_payload(key, text:, type:)
      if key.match?(/\A[A-Z]\z/)
        base = key.downcase
        prev = @registers[base]
        payload = { text: "#{prev ? prev[:text] : ""}#{text}", type: type }
        @registers[base] = payload
      else
        payload = { text: text, type: type }
        @registers[key.downcase] = payload
      end
      payload
    end

    def rotate_delete_registers!(payload)
      9.downto(2) do |i|
        prev = @registers[(i - 1).to_s]
        if prev
          @registers[i.to_s] = dup_register_payload(prev)
        else
          @registers.delete(i.to_s)
        end
      end
      @registers["1"] = dup_register_payload(payload)
    end

    def dup_register_payload(payload)
      return nil unless payload

      { text: payload[:text].dup, type: payload[:type] }
    end

    def assign_detected_filetype(buffer)
      ft = detect_filetype(buffer.path)
      assign_filetype(buffer, ft) if ft && !ft.empty?
      buffer
    end

    def intro_lines
      [
        "RuVim - Vi IMproved (Ruby edition)",
        "",
        "type  :help         for help",
        "type  :help regex   for Ruby Regexp search/substitute help",
        "type  :q            to quit",
        "",
        "keys  i a o         to start editing",
        "keys  / ?           to search",
        "keys  :             to enter command-line",
        "",
        "This is the intro screen (Vim-style).",
        "It will be replaced with an empty buffer when you start editing."
      ]
    end

    public

    def jump_to_location(loc, linewise: false)
      location = normalize_location(loc)
      return nil unless location
      return nil unless @buffers.key?(location[:buffer_id])

      switch_to_buffer(location[:buffer_id]) if current_buffer.id != location[:buffer_id]
      current_window.cursor_y = location[:row]
      current_window.cursor_x = linewise ? 0 : location[:col]
      current_window.clamp_to_buffer(current_buffer)
      current_window.cursor_x = first_nonblank_col(current_buffer, current_window.cursor_y) if linewise
      current_window.clamp_to_buffer(current_buffer)
      current_location
    end

    def arglist
      @arglist.dup
    end

    def arglist_index
      @arglist_index
    end

    def set_arglist(paths)
      @arglist = Array(paths).dup
      @arglist_index = 0
    end

    def arglist_current
      @arglist[@arglist_index] if @arglist_index < @arglist.length
    end

    def arglist_next(count = 1)
      new_index = @arglist_index + count
      if new_index >= @arglist.length
        raise RuVim::CommandError, "Already at last argument"
      end
      @arglist_index = new_index
      @arglist[@arglist_index]
    end

    def arglist_prev(count = 1)
      new_index = @arglist_index - count
      if new_index < 0
        raise RuVim::CommandError, "Already at first argument"
      end
      @arglist_index = new_index
      @arglist[@arglist_index]
    end

    def arglist_first
      @arglist_index = 0
      @arglist[@arglist_index] if @arglist.length > 0
    end

    def arglist_last
      @arglist_index = [@arglist.length - 1, 0].max
      @arglist[@arglist_index] if @arglist.length > 0
    end

    private

    def first_nonblank_col(buffer, row)
      line = buffer.line_at(row)
      line.index(/\S/) || 0
    end

    def normalize_location(loc)
      return nil unless loc

      {
        buffer_id: Integer(loc[:buffer_id] || loc["buffer_id"]),
        row: [Integer(loc[:row] || loc["row"]), 0].max,
        col: [Integer(loc[:col] || loc["col"]), 0].max
      }
    rescue StandardError
      nil
    end

    def same_location?(a, b)
      return false unless a && b

      a[:buffer_id] == b[:buffer_id] && a[:row] == b[:row] && a[:col] == b[:col]
    end

    def dup_macro_key(key)
      case key
      when String
        key.dup
      when Array
        key.map { |v| v.is_a?(String) ? v.dup : v }
      else
        key
      end
    end

    def clipboard_register?(key)
      key == "+" || key == "*"
    end

    def clipboard_default_register_key
      spec = @global_options["clipboard"].to_s
      parts = spec.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
      return "+" if parts.include?("unnamedplus")
      return "*" if parts.include?("unnamed")

      nil
    end

    def write_clipboard_register(key, payload)
      return unless clipboard_register?(key.downcase)

      RuVim::Clipboard.write(payload[:text])
    end

    def read_clipboard_register(key)
      text = RuVim::Clipboard.read
      if text
        payload = { text: text, type: text.end_with?("\n") ? :linewise : :charwise }
        @registers[key] = payload
      end
      @registers[key]
    end

    def ensure_initial_tabpage!
      return unless @tabpages.empty?
      return if @layout_tree.nil?

      @tabpages << new_tabpage_snapshot
      @current_tabpage_index = 0
    end

    def save_current_tabpage_state!
      return if @current_tabpage_index.nil?
      return if @tabpages.empty?

      @tabpages[@current_tabpage_index] = new_tabpage_snapshot(id: @tabpages[@current_tabpage_index][:id])
    end

    def load_tabpage_state!(tab)
      @layout_tree = tree_deep_dup(tab[:layout_tree])
      @current_window_id = tab[:current_window_id]
      current_window
    end

    def new_tabpage_snapshot(id: nil)
      {
        id: id || next_tabpage_id,
        layout_tree: tree_deep_dup(@layout_tree),
        current_window_id: @current_window_id
      }
    end

    def next_buffer_id
      id = @next_buffer_id
      @next_buffer_id += 1
      id
    end

    def next_window_id
      id = @next_window_id
      @next_window_id += 1
      id
    end

    def next_tabpage_id
      id = @next_tabpage_id
      @next_tabpage_id += 1
      id
    end

    def with_tab_autosave_suspended
      prev = @suspend_tab_autosave
      @suspend_tab_autosave = true
      yield
    ensure
      @suspend_tab_autosave = prev
    end

    # --- Layout tree helpers ---

    def tree_leaves(node)
      return [] if node.nil?
      return [node[:id]] if node[:type] == :window

      node[:children].flat_map { |c| tree_leaves(c) }
    end

    def tree_deep_dup(node)
      return nil if node.nil?
      return { type: :window, id: node[:id] } if node[:type] == :window

      { type: node[:type], children: node[:children].map { |c| tree_deep_dup(c) } }
    end

    # Split a leaf node into a new split node. If the parent is already the same
    # split type, merge into the parent instead of nesting.
    def tree_split_leaf(node, target_id, split_type, new_leaf, place)
      if node[:type] == :window
        if node[:id] == target_id
          children = place == :before ? [new_leaf, node] : [node, new_leaf]
          return { type: split_type, children: children }
        end
        return node
      end

      new_children = node[:children].flat_map do |child|
        result = tree_split_leaf(child, target_id, split_type, new_leaf, place)
        # If the child was replaced with the same split type as this node, merge
        if result[:type] == node[:type] && result != child
          result[:children]
        else
          [result]
        end
      end

      { type: node[:type], children: new_children }
    end

    def tree_remove(node, target_id)
      return nil if node.nil?
      return nil if node[:type] == :window && node[:id] == target_id
      return node if node[:type] == :window

      new_children = node[:children].filter_map { |c| tree_remove(c, target_id) }
      return nil if new_children.empty?
      return new_children.first if new_children.length == 1

      { type: node[:type], children: new_children }
    end

    # Check if the path from root to the target window passes through
    # a split node of the given type. Returns true if any ancestor of the
    # target window in the tree has type == split_type.
    def tree_path_has_split_type?(node, target_id, split_type)
      return false if node.nil?
      return false if node[:type] == :window
      # Check if target is in any child subtree
      node[:children].each do |child|
        if tree_subtree_contains?(child, target_id)
          return true if node[:type] == split_type
          return tree_path_has_split_type?(child, target_id, split_type)
        end
      end
      false
    end

    def tree_subtree_contains?(node, target_id)
      return false if node.nil?
      return node[:id] == target_id if node[:type] == :window
      node[:children].any? { |c| tree_subtree_contains?(c, target_id) }
    end

    # Compute normalized rects (0.0–1.0 coordinate space) for direction finding.
    # Separators are ignored here — this is purely for adjacency/direction logic.
    def find_parent_split(node, target_id, dir)
      return nil unless node.is_a?(Hash) && node[:children]

      wanted_type = case dir
                    when :height_increase, :height_decrease then :hsplit
                    when :width_increase, :width_decrease then :vsplit
                    end

      node[:children].each_with_index do |child, i|
        if child[:type] == :window && child[:id] == target_id
          return [node[:type], node, i] if node[:type] == wanted_type
        elsif child[:children]
          result = find_parent_split(child, target_id, dir)
          return result if result
        end
      end

      nil
    end

    def clear_weights(node)
      return unless node.is_a?(Hash)

      node.delete(:weights) if node.key?(:weights)
      node[:children]&.each { |c| clear_weights(c) }
    end

    def tree_compute_rects(node, top:, left:, height:, width:)
      return {} if node.nil?

      if node[:type] == :window
        return { node[:id] => { top: top, left: left, height: height, width: width } }
      end

      children = node[:children]
      n = children.length
      rects = {}

      case node[:type]
      when :vsplit
        w_each = width / n.to_f
        children.each_with_index do |child, i|
          rects.merge!(tree_compute_rects(child, top: top, left: left + i * w_each, height: height, width: w_each))
        end
      when :hsplit
        h_each = height / n.to_f
        children.each_with_index do |child, i|
          rects.merge!(tree_compute_rects(child, top: top + i * h_each, left: left, height: h_each, width: width))
        end
      end

      rects
    end
  end
end
