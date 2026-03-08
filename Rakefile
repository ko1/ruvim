# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rake/extensiontask"

Rake::ExtensionTask.new("ruvim_ext") do |ext|
  ext.lib_dir = "lib/ruvim"
  ext.ext_dir = "ext/ruvim"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/*_test.rb"]
end
task test: :compile

namespace :docs do
  task :check do
    required = %w[
      README.md
      docs/tutorial.md
      docs/spec.md
      docs/command.md
      docs/binding.md
      docs/config.md
      docs/vim_diff.md
      docs/todo.md
    ]
    missing = required.reject { |p| File.file?(p) }
    raise "Missing docs: #{missing.join(', ')}" unless missing.empty?

    refs = Dir["README.md", "docs/*.md"].flat_map do |path|
      File.read(path).scan(/`(docs\/[^`]+\.md)`/).flatten
    end.uniq
    bad_refs = refs.reject { |p| File.file?(p) }
    raise "Broken docs refs: #{bad_refs.join(', ')}" unless bad_refs.empty?
  end
end

task :ci => %i[test docs:check]

task default: %i[test]
