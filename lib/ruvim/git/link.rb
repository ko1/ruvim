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

      # Find a GitHub remote. If remote_name is given, use that specific remote.
      # Otherwise, scan all remotes (preferring "origin", then "upstream", then others).
      # Returns [remote_name, base_url] or [nil, nil].
      def find_github_remote(root, remote_name = nil)
        if remote_name
          url, _, status = Open3.capture3("git", "remote", "get-url", remote_name, chdir: root)
          return [nil, nil] unless status.success?

          base = github_url_from_remote(url.strip)
          return base ? [remote_name, base] : [nil, nil]
        end

        remotes_out, _, status = Open3.capture3("git", "remote", chdir: root)
        return [nil, nil] unless status.success?

        remotes = remotes_out.lines(chomp: true)
        # Prefer origin, then upstream, then others
        ordered = []
        ordered << "origin" if remotes.include?("origin")
        ordered << "upstream" if remotes.include?("upstream")
        remotes.each { |r| ordered << r unless ordered.include?(r) }

        ordered.each do |name|
          url, _, st = Open3.capture3("git", "remote", "get-url", name, chdir: root)
          next unless st.success?

          base = github_url_from_remote(url.strip)
          return [name, base] if base
        end

        [nil, nil]
      end

      # Check if a file differs from the remote tracking branch.
      def file_differs_from_remote?(root, remote_name, branch, file_path)
        remote_ref = "#{remote_name}/#{branch}"
        diff_out, _, status = Open3.capture3("git", "diff", remote_ref, "--", file_path, chdir: root)
        # If the remote ref doesn't exist or diff fails, consider it as differing
        return true unless status.success?

        !diff_out.empty?
      end

      # Resolve GitHub link for a file path at given line(s).
      # Returns [url, warning, error_message].
      def resolve(file_path, line_start, line_end = nil, remote_name: nil)
        root, err = Git.repo_root(file_path)
        return [nil, nil, err] unless root

        found_remote, base_url = find_github_remote(root, remote_name)
        unless base_url
          msg = remote_name ? "Remote '#{remote_name}' is not a GitHub remote" : "No GitHub remote found"
          return [nil, nil, msg]
        end

        branch, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD", chdir: root)
        unless status.success?
          return [nil, nil, "Cannot determine branch"]
        end
        branch = branch.strip

        relative_path = file_path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
        url = build_url(base_url, branch, relative_path, line_start, line_end)

        warning = nil
        if file_differs_from_remote?(root, found_remote, branch, file_path)
          warning = "(remote may differ)"
        end

        [url, warning, nil]
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

          remote_name = argv.first

          url, warning, err = Link.resolve(path, line_start, line_end, remote_name: remote_name)
          unless url
            ctx.editor.echo_error("gh link: #{err}")
            return
          end

          # Copy to clipboard via OSC 52
          $stdout.write(Link.osc52_copy_sequence(url))
          $stdout.flush

          msg = warning ? "#{url} #{warning}" : url
          ctx.editor.echo(msg)
        end
      end
    end
  end
end
