# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Commands
      module_function

      # Find git repository root from a file path.
      # Returns [root_path, error_message].
      def repo_root(file_path)
        dir = File.directory?(file_path) ? file_path : File.dirname(file_path)
        out, err, status = Open3.capture3("git", "rev-parse", "--show-toplevel", chdir: dir)
        unless status.success?
          return [nil, err.strip]
        end
        [out.strip, nil]
      end

      # Run git status.
      # Returns [lines, error_message].
      def status(file_path)
        root, err = repo_root(file_path)
        return [nil, err] unless root

        out, err, status = Open3.capture3("git", "status", chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Run git diff with optional extra args.
      # Returns [lines, error_message].
      def diff(file_path, args: [])
        root, err = repo_root(file_path)
        return [nil, err] unless root

        cmd = ["git", "diff", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end

      # Run git log with optional extra args.
      # Returns [lines, error_message].
      def log(file_path, args: [])
        root, err = repo_root(file_path)
        return [nil, err] unless root

        cmd = ["git", "log", *args]
        out, err, status = Open3.capture3(*cmd, chdir: root)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end
    end
  end
end
