# frozen_string_literal: true

require_relative "test_helper"

class FiletypeTest < Minitest::Test
  def setup
    @editor = fresh_editor
  end

  # --- Extension-based detection ---

  def test_detect_rb_as_ruby
    assert_equal "ruby", @editor.detect_filetype("foo.rb")
  end

  def test_detect_py_as_python
    assert_equal "python", @editor.detect_filetype("test.py")
  end

  def test_detect_js_as_javascript
    assert_equal "javascript", @editor.detect_filetype("app.js")
  end

  def test_detect_ts_as_typescript
    assert_equal "typescript", @editor.detect_filetype("app.ts")
  end

  def test_detect_go_as_go
    assert_equal "go", @editor.detect_filetype("main.go")
  end

  def test_detect_rs_as_rust
    assert_equal "rust", @editor.detect_filetype("lib.rs")
  end

  def test_detect_c_as_c
    assert_equal "c", @editor.detect_filetype("main.c")
  end

  def test_detect_json_as_json
    assert_equal "json", @editor.detect_filetype("config.json")
  end

  def test_detect_yaml_as_yaml
    assert_equal "yaml", @editor.detect_filetype("config.yml")
  end

  def test_detect_md_as_markdown
    assert_equal "markdown", @editor.detect_filetype("README.md")
  end

  def test_detect_sh_as_sh
    assert_equal "sh", @editor.detect_filetype("script.sh")
  end

  def test_detect_html_as_html
    assert_equal "html", @editor.detect_filetype("index.html")
  end

  # --- Basename-based detection ---

  def test_detect_makefile
    assert_equal "make", @editor.detect_filetype("Makefile")
  end

  def test_detect_dockerfile
    assert_equal "dockerfile", @editor.detect_filetype("Dockerfile")
  end

  def test_detect_gemfile_as_ruby
    assert_equal "ruby", @editor.detect_filetype("Gemfile")
  end

  def test_detect_rakefile_as_ruby
    assert_equal "ruby", @editor.detect_filetype("Rakefile")
  end

  # --- Unknown files ---

  def test_detect_unknown_extension_returns_nil
    assert_nil @editor.detect_filetype("data.xyz123")
  end

  def test_detect_empty_path_returns_nil
    assert_nil @editor.detect_filetype("")
  end

  def test_detect_nil_path_returns_nil
    assert_nil @editor.detect_filetype(nil)
  end

  # --- Shebang detection ---

  def test_detect_shebang_ruby
    tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
    path = File.join(tmpdir, "shebang_test_ruby")
    File.write(path, "#!/usr/bin/env ruby\nputs 'hello'\n")
    assert_equal "ruby", @editor.detect_filetype(path)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_detect_shebang_python
    tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
    path = File.join(tmpdir, "shebang_test_python")
    File.write(path, "#!/usr/bin/python3\nprint('hello')\n")
    assert_equal "python", @editor.detect_filetype(path)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_detect_shebang_bash
    tmpdir = ENV["TMPDIR"] || "/tmp/claude-#{Process.uid}"
    path = File.join(tmpdir, "shebang_test_bash")
    File.write(path, "#!/bin/bash\necho hello\n")
    assert_equal "sh", @editor.detect_filetype(path)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  # --- assign_filetype ---

  def test_assign_filetype_sets_option
    buffer = @editor.current_buffer
    @editor.assign_filetype(buffer, "ruby")
    assert_equal "ruby", buffer.options["filetype"]
  end
end
