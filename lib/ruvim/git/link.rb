# frozen_string_literal: true

require "open3"
require "base64"

module RuVim
  module Git
    module Link
      module_function

      # Parse a git remote URL and return the GitHub HTTPS base URL.
      # Returns nil if the remote is not a GitHub URL.
      def github_url_from_remote(remote_url)
        url = remote_url.to_s.strip
        return nil if url.empty?

        case url
        when %r{\Agit@github\.com:(.+?)(?:\.git)?\z}
          "https://github.com/#{$1}"
        when %r{\Ahttps://github\.com/(.+?)(?:\.git)?\z}
          "https://github.com/#{$1}"
        end
      end

      # Build a GitHub blob URL.
      def build_url(base_url, ref, relative_path, line_start, line_end = nil)
        fragment = if line_end && line_end != line_start
                     "#L#{line_start}-L#{line_end}"
                   else
                     "#L#{line_start}"
                   end
        "#{base_url}/blob/#{ref}/#{relative_path}#{fragment}"
      end

      # Generate OSC 52 escape sequence for clipboard copy.
      def osc52_copy_sequence(text)
        encoded = Base64.strict_encode64(text)
        "\e]52;c;#{encoded}\a"
      end

      # Resolve GitHub link for a file path at given line(s).
      # Returns [url, error_message].
      def resolve(file_path, line_start, line_end = nil)
        root, err = Git.repo_root(file_path)
        return [nil, err] unless root

        remote_url, err, status = Open3.capture3("git", "remote", "get-url", "origin", chdir: root)
        unless status.success?
          return [nil, "No remote 'origin': #{err.strip}"]
        end

        base_url = github_url_from_remote(remote_url.strip)
        return [nil, "Not a GitHub remote: #{remote_url.strip}"] unless base_url

        branch, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD", chdir: root)
        unless status.success?
          return [nil, "Cannot determine branch"]
        end

        relative_path = file_path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
        url = build_url(base_url, branch.strip, relative_path, line_start, line_end)
        [url, nil]
      end

      module HandlerMethods
        def gh_link(ctx, argv: [], kwargs: {}, **)
          path = ctx.buffer.path
          unless path && File.exist?(path)
            ctx.editor.echo_error("Buffer has no file path")
            return
          end

          line_start = kwargs[:range_start]
          line_end = kwargs[:range_end]

          if line_start
            # Range lines are 0-based, GitHub uses 1-based
            line_start += 1
            line_end += 1 if line_end
          else
            # Current cursor line (0-based) → 1-based
            line_start = ctx.window.cursor_y + 1
            line_end = nil
          end

          url, err = Link.resolve(path, line_start, line_end)
          unless url
            ctx.editor.echo_error("gh link: #{err}")
            return
          end

          # Copy to clipboard via OSC 52
          $stdout.write(Link.osc52_copy_sequence(url))
          $stdout.flush

          ctx.editor.echo(url)
        end
      end
    end
  end
end
