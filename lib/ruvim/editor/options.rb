# frozen_string_literal: true

module RuVim
  class Editor
    module Options
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
        "showbreak" => { default_scope: :window, type: :string, default: "" },
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
    end
  end
end
