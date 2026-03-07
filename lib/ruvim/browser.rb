# frozen_string_literal: true

require "open3"

module RuVim
  module Browser
    ALLOWED_SCHEMES = %w[https http].freeze

    module_function

    def open_url(url)
      return false unless valid_url?(url)

      backend = detect_backend
      return false unless backend

      if backend[:type] == :powershell
        cmd = powershell_encoded_command(backend[:ps_path], url)
        _, _, status = Open3.capture3(*cmd)
      else
        _, _, status = Open3.capture3(*backend[:command], url)
      end
      status.success?
    rescue StandardError
      false
    end

    def valid_url?(url)
      scheme = url.to_s.split(":", 2).first.to_s.downcase
      ALLOWED_SCHEMES.include?(scheme)
    end

    def powershell_encoded_command(ps_path, url)
      # Encode as UTF-16LE Base64 to avoid any command injection via -Command.
      # This matches the approach used by Node.js "open" package.
      ps_script = "Start-Process '#{url.gsub("'", "''")}'"
      encoded = [ps_script.encode("UTF-16LE")].pack("m0")
      [ps_path, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]
    end

    def detect_backend
      return { command: %w[open], type: :macos } if command_available?("open") && macos?
      return { command: %w[xdg-open], type: :xdg } if command_available?("xdg-open") && !wsl?
      return { command: %w[wslview], type: :wslview } if command_available?("wslview")

      ps_path = powershell_path(wsl_mount_point)
      if wsl? && File.exist?(ps_path)
        return { ps_path: ps_path, type: :powershell }
      end

      nil
    end

    def powershell_path(mount_point)
      "#{mount_point}c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    end

    def wsl_mount_point(config: nil)
      config ||= begin
        File.read("/etc/wsl.conf")
      rescue StandardError
        nil
      end

      default = "/mnt/"
      return default unless config

      config.each_line do |line|
        stripped = line.strip
        next if stripped.start_with?("#")

        if stripped.match?(/\Aroot\s*=/)
          value = stripped.sub(/\Aroot\s*=\s*/, "").strip
          value += "/" unless value.end_with?("/")
          return value
        end
      end

      default
    end

    def macos?
      RUBY_PLATFORM.include?("darwin")
    end

    def wsl?
      return @wsl if defined?(@wsl)

      @wsl = begin
        File.read("/proc/version").include?("microsoft")
      rescue StandardError
        false
      end
    end

    def reset!
      @wsl = nil
    end

    def command_available?(name)
      system("which", name, out: File::NULL, err: File::NULL)
    end
  end
end
