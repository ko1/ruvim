require "open3"

module RuVim
  module Clipboard
    module_function

    def available?
      !backend.nil?
    end

    def read
      cmd = backend&.dig(:read)
      return nil unless cmd

      out, status = Open3.capture2(*cmd)
      return nil unless status.success?

      out
    rescue StandardError
      nil
    end

    def write(text)
      cmd = backend&.dig(:write)
      return false unless cmd

      Open3.popen2(*cmd) do |stdin, _stdout, wait|
        stdin.write(text.to_s)
        stdin.close
        return wait.value.success?
      end
    rescue StandardError
      false
    end

    def reset_backend!
      @backend = nil
    end

    def backend
      @backend ||= detect_backend
    end

    def detect_backend
      return pbcopy_backend if command_available?("pbcopy") && command_available?("pbpaste")
      return wayland_backend if command_available?("wl-copy") && command_available?("wl-paste")
      return xclip_backend if command_available?("xclip")
      return xsel_backend if command_available?("xsel")

      nil
    end

    def pbcopy_backend
      { write: %w[pbcopy], read: %w[pbpaste] }
    end

    def wayland_backend
      { write: %w[wl-copy], read: %w[wl-paste -n] }
    end

    def xclip_backend
      { write: %w[xclip -selection clipboard -in], read: %w[xclip -selection clipboard -out] }
    end

    def xsel_backend
      { write: %w[xsel --clipboard --input], read: %w[xsel --clipboard --output] }
    end

    def command_available?(name)
      system("which", name, out: File::NULL, err: File::NULL)
    end
  end
end
