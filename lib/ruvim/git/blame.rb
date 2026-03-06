# frozen_string_literal: true

require "open3"

module RuVim
  module Git
    module Blame
      module_function

      # Parse `git blame --porcelain` output into an array of entry hashes.
      # Each entry: { hash:, short_hash:, author:, date:, summary:, text:, orig_line: }
      def parse_porcelain(output)
        entries = []
        commit_cache = {}
        current = nil

        output.each_line(chomp: true) do |line|
          if line.start_with?("\t")
            # Content line — finalize current entry
            current[:text] = line[1..]
            entries << current
            current = nil
          elsif current.nil?
            # Header line: <hash> <orig_line> <final_line> [<group_count>]
            parts = line.split(" ")
            hash = parts[0]
            orig_line = parts[1].to_i

            if commit_cache.key?(hash)
              current = commit_cache[hash].dup
              current[:orig_line] = orig_line
            else
              current = { hash: hash, short_hash: hash[0, 8], orig_line: orig_line }
            end
          else
            # Metadata lines
            case line
            when /\Aauthor (.+)/
              current[:author] = $1
            when /\Aauthor-time (\d+)/
              current[:date] = Time.at($1.to_i).strftime("%Y-%m-%d")
            when /\Asummary (.+)/
              current[:summary] = $1
            when /\Afilename (.+)/
              # Cache commit info on first occurrence
              commit_cache[current[:hash]] ||= current.dup
            end
          end
        end

        entries
      end

      # Format entries into display lines for the blame buffer.
      def format_lines(entries)
        max_author = entries.map { |e| e[:author].to_s.length }.max || 0
        max_author = [max_author, 20].min

        entries.map do |e|
          author = (e[:author] || "").ljust(max_author)[0, max_author]
          "#{e[:short_hash]} #{author} #{e[:date]} #{e[:text]}"
        end
      end

      # Run git blame for a file at a given revision.
      # Returns [entries, error_message].
      def run(file_path, rev: nil)
        dir = File.dirname(file_path)
        basename = File.basename(file_path)

        cmd = ["git", "blame", "--porcelain"]
        if rev
          cmd << rev << "--" << basename
        else
          cmd << "--" << basename
        end

        out, err, status = Open3.capture3(*cmd, chdir: dir)
        unless status.success?
          return [nil, err.strip]
        end

        entries = parse_porcelain(out)
        [entries, nil]
      end

      # Run git show for a commit.
      # Returns [lines, error_message].
      def show_commit(file_path, commit_hash)
        dir = File.dirname(file_path)
        out, err, status = Open3.capture3("git", "show", commit_hash, chdir: dir)
        unless status.success?
          return [nil, err.strip]
        end
        [out.lines(chomp: true), nil]
      end
    end
  end
end
