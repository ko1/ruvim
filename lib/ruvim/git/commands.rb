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
    end
  end
end
