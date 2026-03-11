# frozen_string_literal: true

require "open3"

module RuVim
  module Commands
    module Gh
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
        encoded = [text].pack("m0")
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
        root, err = Commands::Git.repo_root(file_path)
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

      # Build a GitHub PR search URL for a branch.
      def pr_search_url(base_url, branch)
        "#{base_url}/pulls?q=head:#{branch}"
      end

      # Resolve GitHub PR URL for the current repo.
      # Returns [url, error_message].
      def resolve_pr(file_path)
        root, err = Commands::Git.repo_root(file_path)
        return [nil, err] unless root

        _, base_url = find_github_remote(root)
        return [nil, "No GitHub remote found"] unless base_url

        branch, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD", chdir: root)
        return [nil, "Cannot determine branch"] unless status.success?

        [pr_search_url(base_url, branch.strip), nil]
      end

      module Handler
        GH_SUBCOMMANDS = {
          "link"   => :gh_link,
          "browse" => :gh_browse,
          "pr"     => :gh_pr,
        }.freeze

        def gh_dispatch(ctx, argv: [], kwargs: {}, **)
          raise RuVim::CommandError, "Restricted mode: :gh is disabled" if ctx.editor.respond_to?(:restricted_mode?) && ctx.editor.restricted_mode?

          sub = argv.first.to_s.downcase
          if sub.empty?
            ctx.editor.echo("GitHub subcommands: #{GH_SUBCOMMANDS.keys.join(', ')}")
            return
          end

          method = GH_SUBCOMMANDS[sub]
          unless method
            executor = ctx.editor.shell_executor
            if executor
              command = (["gh"] + argv).join(" ")
              status = executor.call(command)
              ctx.editor.echo("shell exit #{status.exitstatus}")
            else
              ctx.editor.echo_error("Unknown gh subcommand: #{sub}")
            end
            return
          end

          public_send(method, ctx, argv: argv[1..], kwargs: kwargs, bang: false, count: 1)
        end

        def gh_link(ctx, argv: [], kwargs: {}, **)
          url, warning = gh_resolve_url(ctx, argv: argv, kwargs: kwargs, command: "gh link")
          return unless url

          # Copy to clipboard via OSC 52
          $stdout.write(Gh.osc52_copy_sequence(url))
          $stdout.flush

          msg = warning ? "#{url} #{warning}" : url
          ctx.editor.echo(msg)
        end

        def gh_browse(ctx, argv: [], kwargs: {}, **)
          url, warning = gh_resolve_url(ctx, argv: argv, kwargs: kwargs, command: "gh browse")
          return unless url

          unless Browser.open_url(url)
            ctx.editor.echo_error("gh browse: could not open browser")
            return
          end

          msg = warning ? "Opened #{url} #{warning}" : "Opened #{url}"
          ctx.editor.echo(msg)
        end

        def gh_pr(ctx, **)
          path = ctx.buffer.path || Dir.pwd
          url, err = Gh.resolve_pr(path)
          unless url
            ctx.editor.echo_error("gh pr: #{err}")
            return
          end

          unless Browser.open_url(url)
            ctx.editor.echo_error("gh pr: could not open browser")
            return
          end

          ctx.editor.echo("Opened #{url}")
        end

        private

        def gh_resolve_url(ctx, argv:, kwargs:, command:)
          path = ctx.buffer.path
          unless path && File.exist?(path)
            ctx.editor.echo_error("Buffer has no file path")
            return nil
          end

          line_start = kwargs[:range_start]
          line_end = kwargs[:range_end]

          if line_start
            line_start += 1
            line_end += 1 if line_end
          else
            line_start = ctx.window.cursor_y + 1
            line_end = nil
          end

          remote_name = argv.first

          url, warning, err = Gh.resolve(path, line_start, line_end, remote_name: remote_name)
          unless url
            ctx.editor.echo_error("#{command}: #{err}")
            return nil
          end

          [url, warning]
        end
      end
    end
  end
end
