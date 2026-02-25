module RuVim
  class Editor
    OPTION_DEFS = {
      "number" => { default_scope: :window, type: :bool, default: false },
      "tabstop" => { default_scope: :buffer, type: :int, default: 2 },
      "filetype" => { default_scope: :buffer, type: :string, default: nil }
    }.freeze

    attr_reader :buffers, :windows
    attr_accessor :current_window_id, :mode, :message, :pending_count, :alternate_buffer_id, :window_layout

    def initialize
      @buffers = {}
      @windows = {}
      @window_order = []
      @tabpages = []
      @current_tabpage_index = nil
      @next_tabpage_id = 1
      @suspend_tab_autosave = false
      @next_buffer_id = 1
      @next_window_id = 1
      @current_window_id = nil
      @alternate_buffer_id = nil
      @mode = :normal
      @window_layout = :single
      @message = ""
      @pending_count = nil
      @running = true
      @global_options = default_global_options
      @command_line = CommandLine.new
      @last_search = nil
      @registers = {}
      @active_register_name = nil
      @local_marks = Hash.new { |h, k| h[k] = {} }
      @global_marks = {}
      @jumplist = []
      @jump_index = nil
      @macros = {}
      @macro_recording = nil
      @visual_state = nil
    end

    def running?
      @running
    end

    def request_quit!
      @running = false
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

    def set_last_search(pattern:, direction:)
      @last_search = { pattern: pattern.to_s, direction: direction.to_sym }
    end

    def current_window
      @windows.fetch(@current_window_id)
    end

    def current_buffer
      @buffers.fetch(current_window.buffer_id)
    end

    def option_def(name)
      OPTION_DEFS[name.to_s]
    end

    def option_default_scope(name)
      option_def(name)&.fetch(:default_scope, :global) || :global
    end

    def effective_option(name, window: current_window, buffer: current_buffer)
      key = name.to_s
      if window && window.options.key?(key)
        window.options[key]
      elsif buffer && buffer.options.key?(key)
        buffer.options[key]
      else
        @global_options[key]
      end
    end

    def get_option(name, scope: :effective, window: current_window, buffer: current_buffer)
      key = name.to_s
      case scope.to_sym
      when :global
        @global_options[key]
      when :buffer
        buffer&.options&.[](key)
      when :window
        window&.options&.[](key)
      else
        effective_option(key, window:, buffer:)
      end
    end

    def set_option(name, value, scope: :auto, window: current_window, buffer: current_buffer)
      key = name.to_s
      value = coerce_option_value(key, value)
      actual_scope = (scope.to_sym == :auto ? option_default_scope(key) : scope.to_sym)
      case actual_scope
      when :global
        @global_options[key] = value
      when :buffer
        raise RuVim::CommandError, "No current buffer" unless buffer
        buffer.options[key] = value
      when :window
        raise RuVim::CommandError, "No current window" unless window
        window.options[key] = value
      else
        raise RuVim::CommandError, "Unknown option scope: #{actual_scope}"
      end
      value
    end

    def option_snapshot(window: current_window, buffer: current_buffer)
      keys = (OPTION_DEFS.keys + @global_options.keys + (buffer&.options&.keys || []) + (window&.options&.keys || [])).uniq.sort
      keys.map do |k|
        {
          name: k,
          effective: get_option(k, scope: :effective, window:, buffer:),
          global: get_option(k, scope: :global, window:, buffer:),
          buffer: get_option(k, scope: :buffer, window:, buffer:),
          window: get_option(k, scope: :window, window:, buffer:)
        }
      end
    end

    def detect_filetype(path)
      p = path.to_s
      return nil if p.empty?

      base = File.basename(p)
      return "ruby" if %w[Gemfile Rakefile Guardfile].include?(base)

      {
        ".rb" => "ruby",
        ".rake" => "ruby",
        ".ru" => "ruby",
        ".py" => "python",
        ".js" => "javascript",
        ".mjs" => "javascript",
        ".cjs" => "javascript",
        ".ts" => "typescript",
        ".tsx" => "typescriptreact",
        ".jsx" => "javascriptreact",
        ".json" => "json",
        ".yml" => "yaml",
        ".yaml" => "yaml",
        ".md" => "markdown",
        ".txt" => "text",
        ".html" => "html",
        ".css" => "css",
        ".sh" => "sh"
      }[File.extname(base).downcase]
    end

    def registers
      @registers
    end

    def set_register(name = "\"", text:, type: :charwise)
      key = name.to_s
      payload = write_register_payload(key, text: text.to_s, type: type.to_sym)
      write_clipboard_register(key, payload)
      @registers["\""] = payload unless key == "\""
      payload
    end

    def get_register(name = "\"")
      key = name.to_s.downcase
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
      @mode = mode.to_sym
      @visual_state = {
        mode: mode.to_sym,
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
      if @visual_state[:mode] == :visual_line
        start_row, end_row = [ay, cy].minmax
        {
          mode: :linewise,
          start_row: start_row,
          start_col: 0,
          end_row: end_row,
          end_col: current_buffer.line_length(end_row)
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
      buffer.options["filetype"] = filetype if filetype
      @buffers[id] = buffer
      buffer
    end

    def add_buffer_from_file(path)
      id = next_buffer_id
      buffer = Buffer.from_file(id:, path:)
      assign_detected_filetype(buffer)
      @buffers[id] = buffer
      buffer
    end

    def add_window(buffer_id:)
      id = next_window_id
      window = Window.new(id:, buffer_id:)
      @windows[id] = window
      @window_order << id
      @current_window_id ||= id
      ensure_initial_tabpage!
      save_current_tabpage_state! unless @suspend_tab_autosave
      window
    end

    def split_current_window(layout: :horizontal)
      save_current_tabpage_state! unless @suspend_tab_autosave
      src = current_window
      win = add_window(buffer_id: src.buffer_id)
      win.cursor_x = src.cursor_x
      win.cursor_y = src.cursor_y
      win.row_offset = src.row_offset
      win.col_offset = src.col_offset
      @window_layout = layout.to_sym
      @current_window_id = win.id
      save_current_tabpage_state! unless @suspend_tab_autosave
      win
    end

    def focus_window(id)
      return nil unless @windows.key?(id)

      @current_window_id = id
      save_current_tabpage_state! unless @suspend_tab_autosave
      current_window
    end

    def focus_next_window
      return current_window if @window_order.length <= 1

      idx = @window_order.index(@current_window_id) || 0
      focus_window(@window_order[(idx + 1) % @window_order.length])
    end

    def focus_prev_window
      return current_window if @window_order.length <= 1

      idx = @window_order.index(@current_window_id) || 0
      focus_window(@window_order[(idx - 1) % @window_order.length])
    end

    def focus_window_direction(dir)
      return current_window if @window_order.length <= 1

      case @window_layout
      when :vertical
        if dir == :left
          focus_prev_window
        elsif dir == :right
          focus_next_window
        else
          current_window
        end
      when :horizontal
        if dir == :up
          focus_prev_window
        elsif dir == :down
          focus_next_window
        else
          current_window
        end
      else
        focus_next_window
      end
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
      buffer = add_buffer_from_file(path)
      switch_to_buffer(buffer.id)
      echo(path && File.exist?(path) ? "\"#{path}\" #{buffer.line_count}L" : "\"#{path}\" [New File]")
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
      current_buffer.options["filetype"] = "help"
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
      current_buffer.options["filetype"] = nil
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

    def window_order
      @window_order
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

    def tabnew(path: nil)
      ensure_initial_tabpage!
      save_current_tabpage_state!

      with_tab_autosave_suspended do
        @window_order = []
        @current_window_id = nil
        @window_layout = :single

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
      enter_normal_mode
    end

    def echo(msg)
      @message = msg.to_s
    end

    def clear_message
      @message = ""
    end

    def text_viewport_size(rows:, cols:)
      text_rows = command_line_active? ? rows - 2 : rows - 1
      [text_rows, cols]
    end

    def command_line_active?
      @mode == :command_line
    end

    private

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

    def assign_detected_filetype(buffer)
      ft = detect_filetype(buffer.path)
      buffer.options["filetype"] = ft if ft && !ft.empty?
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
      return if @window_order.empty?

      @tabpages << new_tabpage_snapshot
      @current_tabpage_index = 0
    end

    def save_current_tabpage_state!
      return if @current_tabpage_index.nil?
      return if @tabpages.empty?

      @tabpages[@current_tabpage_index] = new_tabpage_snapshot(id: @tabpages[@current_tabpage_index][:id])
    end

    def load_tabpage_state!(tab)
      @window_order = tab[:window_order].dup
      @current_window_id = tab[:current_window_id]
      @window_layout = tab[:window_layout]
      current_window
    end

    def new_tabpage_snapshot(id: nil)
      {
        id: id || next_tabpage_id,
        window_order: @window_order.dup,
        current_window_id: @current_window_id,
        window_layout: @window_layout
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
  end
end
