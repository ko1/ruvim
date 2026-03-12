# frozen_string_literal: true

require "set"

module RuVim
  class SpellChecker
    DICT_PATHS = [
      "/usr/share/dict/words",
      "/usr/share/dict/american-english",
      "/usr/share/dict/british-english"
    ].freeze

    WORD_RE = /[a-zA-Z']+/

    def initialize(dict_path: nil)
      @dictionary = load_dictionary(dict_path)
    end

    def valid?(word)
      return true if word.nil? || word.empty?
      return true if word.match?(/\A\d+\z/)
      return true if word.length <= 1

      w = word.downcase.delete("'")
      @dictionary.include?(w)
    end

    # Returns array of { word:, col:, length: } for misspelled words in a line.
    # Skips lines starting with '#' (comment lines, e.g. git commit).
    def misspelled_words(line)
      return [] if line.nil? || line.empty?
      return [] if line.match?(/\A\s*#/)

      results = []
      line.scan(WORD_RE) do
        word = Regexp.last_match[0]
        next if valid?(word)
        col = Regexp.last_match.begin(0)
        results << { word: word, col: col, length: word.length }
      end
      results
    end

    # Returns hash { col => true } for misspelled character positions.
    # Used by Screen rendering to apply underline highlight.
    def spell_highlight_cols(line, source_col_offset: 0)
      cols = {}
      misspelled_words(line).each do |m|
        (m[:col]...m[:col] + m[:length]).each do |i|
          cols[source_col_offset + i] = true
        end
      end
      cols
    end

    private

    def load_dictionary(explicit_path)
      path = explicit_path || find_dict_path
      dict = Set.new
      if path && File.exist?(path)
        File.foreach(path, chomp: true) do |word|
          # Skip possessive forms, store lowercase base
          w = word.downcase.delete("'")
          dict.add(w)
        end
      end
      # Add common programming/git terms not in standard dictionaries
      add_extra_words(dict)
      dict
    end

    def find_dict_path
      DICT_PATHS.find { |p| File.exist?(p) }
    end

    def add_extra_words(dict)
      %w[
        refactor refactored refactoring repo repos
        todo fixme hacktodo changelog readme
        api apis url urls http https json yaml toml csv tsv
        config configs init src lib bin tmp
        stdin stdout stderr args argv env
        github gitlab bitbucket
        ci cd pr prs merge merged merging rebase rebased rebasing
        commit commits committed committing amend amended
        diff diffs upstream downstream
        signup login logout auth oauth
        async await callback callbacks
        ok
      ].each { |w| dict.add(w) }
    end
  end
end
