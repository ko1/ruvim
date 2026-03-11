# frozen_string_literal: true

require "json"
require "fileutils"

# Utilities
require_relative "command_invocation"
require_relative "display_width"
require_relative "keyword_chars"
require_relative "text_metrics"

# Autoloaded: used on demand, not at startup
module RuVim
  autoload :Clipboard, File.expand_path("clipboard", __dir__)
  autoload :Browser, File.expand_path("browser", __dir__)
  autoload :SpellChecker, File.expand_path("spell_checker", __dir__)
  autoload :FileWatcher, File.expand_path("file_watcher", __dir__)
end

# Language modules (registry loads all lang/* internally)
require_relative "lang/registry"

# Core data structures
require_relative "highlighter"
require_relative "context"
require_relative "buffer"
require_relative "window"
require_relative "editor"

# Registries and commands (handler.rb loads git/* internally)
require_relative "command_registry"
require_relative "ex_command_registry"
require_relative "commands/gh"
require_relative "commands/git/handler"
require_relative "global_commands"
require_relative "dispatcher"

# Input and rendering (rich_view.rb loads tsv/csv internally)
require_relative "keymap_manager"
require_relative "command_line"
require_relative "input"
require_relative "terminal"
require_relative "rich_view"
require_relative "screen"

# Configuration
require_relative "config_dsl"
require_relative "config_loader"

# App components
require_relative "stream_mixer"
require_relative "completion_manager"
require_relative "key_handler"
require_relative "app_defaults"

module RuVim
  class App
    StartupState = Struct.new(
      :readonly, :diff_mode, :quickfix_errorfile, :session_file,
      :nomodifiable, :follow, :time_path, :time_origin, :timeline,
      :open_layout, :open_count, :skip_user_config, :config_path,
      keyword_init: true
    )
    def initialize(path: nil, paths: nil, stdin: STDIN, ui_stdin: nil, stdin_stream_mode: false, stdout: STDOUT, pre_config_actions: [], startup_actions: [], clean: false, skip_user_config: false, config_path: nil, readonly: false, diff_mode: false, quickfix_errorfile: nil, session_file: nil, nomodifiable: false, follow: false, restricted: false, verbose_level: 0, verbose_io: STDERR, startup_time_path: nil, startup_open_layout: nil, startup_open_count: nil)
      startup_paths = Array(paths || path).compact
      stdin_stream = !!stdin_stream_mode
      effective_stdin = ui_stdin || stdin
      @terminal = Terminal.new(stdin: effective_stdin, stdout:)
      @input = Input.new(effective_stdin)
      @screen = Screen.new(terminal: @terminal)
      @dispatcher = Dispatcher.new
      @keymaps = KeymapManager.new
      @signal_r, @signal_w = IO.pipe
      @needs_redraw = true
      @clean_mode = clean
      @startup = StartupState.new(
        skip_user_config: skip_user_config,
        config_path: config_path,
        readonly: readonly,
        diff_mode: diff_mode,
        quickfix_errorfile: quickfix_errorfile,
        session_file: session_file,
        nomodifiable: nomodifiable,
        follow: follow,
        time_path: startup_time_path,
        time_origin: monotonic_now,
        timeline: [],
        open_layout: startup_open_layout,
        open_count: startup_open_count
      )
      @verbose_level = verbose_level.to_i
      @verbose_io = verbose_io

      @editor = Editor.new(
        restricted_mode: restricted,
        keymap_manager: @keymaps
      )
      @stream_mixer = StreamMixer.new(editor: @editor, signal_w: @signal_w)
      @editor.stream_mixer = @stream_mixer
      @key_handler = KeyHandler.new(
        editor: @editor,
        dispatcher: @dispatcher,
        completion: CompletionManager.new(
          editor: @editor,
          verbose_logger: method(:verbose_log)
        )
      )
      @editor.app_action_handler = @key_handler.method(:handle_editor_app_action)
      @editor.suspend_handler = -> {
        @terminal.suspend_for_tstp
        @screen.invalidate_cache!
      }
      @editor.shell_executor = ->(command) {
        result = @terminal.suspend_for_shell(command)
        @screen.invalidate_cache!
        result
      }
      @editor.confirm_key_reader = -> {
        @screen.render(@editor)
        @input.read_key
      }
      @editor.normal_key_feeder = ->(keys) { keys.each { |k| @key_handler.handle(k) } }

      @key_handler.load_history!

      startup_mark("init.start")
      register_builtins!
      bind_default_keys!
      init_config_loader!
      @editor.ensure_bootstrap_buffer!
      verbose_log(1, "startup: run_pre_config_actions count=#{Array(pre_config_actions).length}")
      run_startup_actions!(pre_config_actions, log_prefix: "pre-config")
      startup_mark("pre_config_actions.done")
      verbose_log(1, "startup: load_user_config")
      load_user_config!
      startup_mark("config.loaded")
      install_signal_handlers
      startup_mark("signals.installed")

      if stdin_stream && startup_paths.empty?
        verbose_log(1, "startup: stdin stream buffer")
        @stream_mixer.prepare_stdin_stream_buffer!(stdin)
      elsif startup_paths.empty?
        verbose_log(1, "startup: intro")
        @editor.show_intro_buffer_if_applicable!
      else
        verbose_log(1, "startup: open_paths #{startup_paths.inspect} layout=#{@startup.open_layout || :single}")
        open_startup_paths!(startup_paths)
      end
      startup_mark("buffers.opened")
      verbose_log(1, "startup: load_current_ftplugin")
      load_current_ftplugin!
      startup_mark("ftplugin.loaded")
      apply_startup_compat_mode_messages!
      verbose_log(1, "startup: run_startup_actions count=#{Array(startup_actions).length}")
      run_startup_actions!(startup_actions)
      startup_mark("startup_actions.done")
      @stream_mixer.start_pending_stdin!
      write_startuptime_log!
      @startup = nil
    end

    def run
      @terminal.with_ui do
        loop do
          @needs_redraw = true if @stream_mixer.drain_events!
          if @needs_redraw
            @screen.render(@editor)
            @needs_redraw = false
          end
          break unless @editor.running?

          key = @input.read_key(
            wakeup_ios: [@signal_r],
            timeout: @key_handler.loop_timeout_seconds,
            esc_timeout: @key_handler.escape_sequence_timeout_seconds
          )
          if key.nil?
            @needs_redraw = true if @key_handler.handle_idle_timeout
            next
          end

          needs_redraw_from_key = @key_handler.handle(key)
          @needs_redraw = true
          load_current_ftplugin!

          # Force redraw after suspend_to_shell
          @needs_redraw = true if needs_redraw_from_key

          # Batch insert-mode keystrokes to avoid per-char rendering during paste
          if @editor.mode == :insert && @input.has_pending_input?
            @key_handler.paste_batch = true
            begin
              while @editor.mode == :insert && @input.has_pending_input?
                batch_key = @input.read_key(timeout: 0, esc_timeout: 0)
                break unless batch_key
                @key_handler.handle(batch_key)
              end
            ensure
              @key_handler.paste_batch = false
            end
          end
        end
      end
    ensure
      @stream_mixer.shutdown!
      @key_handler.save_history!
    end

    def run_startup_actions!(actions, log_prefix: "startup")
      Array(actions).each do |action|
        run_startup_action!(action, log_prefix:)
        break unless @editor.running?
      end
    end

    private

    def clear_expired_transient_message_if_any
      @needs_redraw = true if @key_handler.handle_idle_timeout
    end


    def install_signal_handlers
      Signal.trap("WINCH") do
        @screen.invalidate_cache! if @screen.respond_to?(:invalidate_cache!)
        @needs_redraw = true
        notify_signal_wakeup
      end
    rescue ArgumentError
      nil
    end

    def init_config_loader!
      @config_loader = ConfigLoader.new(
        command_registry: CommandRegistry.instance,
        ex_registry: ExCommandRegistry.instance,
        keymaps: @keymaps,
        command_host: GlobalCommands.instance
      )
    end

    def load_user_config!
      return if @clean_mode || @editor.restricted_mode?
      return if @startup.skip_user_config

      if @startup.config_path
        @config_loader.load_file(@startup.config_path)
      else
        @config_loader.load_default!
      end
    rescue StandardError => e
      @editor.echo_error("config error: #{e.message}")
    end

    def load_current_ftplugin!
      return if @clean_mode || @editor.restricted_mode?
      return unless @config_loader

      @config_loader.load_ftplugin!(@editor, @editor.current_buffer)
    rescue StandardError => e
      @editor.echo_error("ftplugin error: #{e.message}")
    end

    def run_startup_action!(action, log_prefix: "startup")
      case action[:type]
      when :ex
        verbose_log(2, "#{log_prefix} ex: #{action[:value]}")
        @dispatcher.dispatch_ex(@editor, action[:value].to_s)
      when :line
        verbose_log(2, "#{log_prefix} line: #{action[:value]}")
        @editor.move_cursor_to_line(action[:value].to_i)
      when :line_end
        verbose_log(2, "#{log_prefix} line_end")
        @editor.move_cursor_to_line(@editor.current_buffer.line_count)
      end
    end

    def verbose_log(level, message)
      return if @verbose_level < level
      return unless @verbose_io

      @verbose_io.puts("[ruvim:v#{@verbose_level}] #{message}")
      @verbose_io.flush if @verbose_io.respond_to?(:flush)
    rescue StandardError
      nil
    end

    def startup_mark(label)
      return unless @startup&.time_path

      @startup.timeline << [label.to_s, monotonic_now]
    end

    def write_startuptime_log!
      return unless @startup&.time_path

      prev = @startup.time_origin
      lines = @startup.timeline.map do |label, t|
        total_ms = ((t - @startup.time_origin) * 1000.0)
        delta_ms = ((t - prev) * 1000.0)
        prev = t
        format("%9.3f %9.3f %s", total_ms, delta_ms, label)
      end
      File.write(@startup.time_path, lines.join("\n") + "\n")
    rescue StandardError => e
      verbose_log(1, "startuptime write error: #{e.message}")
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue StandardError
      Time.now.to_f
    end

    def apply_startup_buffer_flags!
      buf = @editor.current_buffer
      return unless buf&.file_buffer?

      if @startup.readonly
        buf.readonly = true
        @editor.echo("readonly: #{buf.display_name}")
      end
      if @startup.nomodifiable
        buf.modifiable = false
        buf.readonly = true
        @editor.echo("nomodifiable: #{buf.display_name}")
      end
      @editor.start_follow_current_buffer! if @startup.follow
    end

    def apply_startup_compat_mode_messages!
      if @startup.diff_mode
        verbose_log(1, "startup: -d requested (diff mode placeholder)")
        @editor.echo("diff mode (-d) is not implemented yet")
      end

      if @startup.quickfix_errorfile
        verbose_log(1, "startup: -q #{@startup.quickfix_errorfile} requested (quickfix placeholder)")
        @editor.echo("quickfix startup (-q #{@startup.quickfix_errorfile}) is not implemented yet")
      end

      if @startup.session_file
        verbose_log(1, "startup: -S #{@startup.session_file} requested (session placeholder)")
        @editor.echo("session startup (-S #{@startup.session_file}) is not implemented yet")
      end
    end

    def open_startup_paths!(paths)
      list = Array(paths).compact
      return if list.empty?

      @editor.evict_bootstrap_buffer!
      @editor.set_arglist(list)

      first, *rest = list
      @editor.open_path(first)
      apply_startup_buffer_flags!

      case @startup.open_layout
      when :horizontal
        first_win_id = @editor.current_window_id
        rest.each { |p| open_path_in_split!(p, layout: :horizontal) }
        @editor.focus_window(first_win_id)
      when :vertical
        first_win_id = @editor.current_window_id
        rest.each { |p| open_path_in_split!(p, layout: :vertical) }
        @editor.focus_window(first_win_id)
      when :tab
        rest.each { |p| open_path_in_tab!(p) }
        @editor.tabnext(-(@editor.tabpage_count - 1))
      else
        rest.each do |p|
          buf = @editor.add_buffer_from_file(p)
          @editor.start_follow!(buf) if @startup.follow
        end
      end
    end

    def open_path_in_split!(path, layout:)
      @editor.split_current_window(layout:)
      @editor.open_path(path)
      apply_startup_buffer_flags!
    end

    def open_path_in_tab!(path)
      @editor.tabnew(path:)
      apply_startup_buffer_flags!
    end

    def notify_signal_wakeup
      @signal_w.write_nonblock(".")
    rescue IO::WaitWritable, Errno::EPIPE
      nil
    end

    def register_internal_unless(registry, id, **spec)
      return if registry.registered?(id)

      registry.register(id, **spec)
    end

    def register_ex_unless(registry, name, **spec)
      return if registry.registered?(name)

      registry.register(name, **spec)
    end
  end
end
