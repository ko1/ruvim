require_relative "test_helper"
require "tmpdir"
require "fileutils"

class OnSaveHookTest < Minitest::Test
  def test_base_on_save_is_noop
    editor = fresh_editor
    ctx = RuVim::Context.new(editor: editor)
    # Should not raise
    RuVim::Lang::Base.on_save(ctx, "/tmp/nonexistent.txt")
  end

  def test_ruby_on_save_with_valid_file
    editor = fresh_editor
    ctx = RuVim::Context.new(editor: editor)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "valid.rb")
      File.write(path, "puts 'hello'\n")
      RuVim::Lang::Ruby.on_save(ctx, path)
      # No error message should be set (echo from before should remain)
      refute editor.message_error?
      assert_empty editor.quickfix_items, "quickfix list should be empty for valid file"
    end
  end

  def test_ruby_on_save_with_syntax_error
    editor = fresh_editor
    ctx = RuVim::Context.new(editor: editor)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.rb")
      File.write(path, "def foo(\n")
      RuVim::Lang::Ruby.on_save(ctx, path)
      assert editor.message_error?
      assert_match(/syntax error/i, editor.message)
      refute_empty editor.quickfix_items, "quickfix list should be populated on syntax error"
      item = editor.quickfix_items.first
      assert_kind_of Integer, item[:row]
      assert_match(/syntax error/i, item[:text])
    end
  end

  def test_ruby_on_save_with_nil_path
    editor = fresh_editor
    ctx = RuVim::Context.new(editor: editor)
    # Should not raise
    RuVim::Lang::Ruby.on_save(ctx, nil)
    refute editor.message_error?
  end

  def test_file_write_calls_on_save
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!

    called = false
    hook_module = Module.new do
      define_method(:on_save) do |_ctx, _path|
        called = true
      end
      module_function :on_save
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.rb")
      editor.current_buffer.instance_variable_set(:@lang_module, hook_module)
      editor.current_buffer.replace_all_lines!(["hello"])

      # Execute :w command
      keys = ":w #{path}\n".chars
      keys.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }

      assert called, "on_save hook should have been called"
    end
  end

  def test_write_then_bracket_q_navigates_quickfix
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!

    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.rb")
      # Two lines so error is on line 2 — verifiable jump target
      File.write(path, "x = 1\ndef foo(\n")

      # Open and write the file
      ":e #{path}\n".chars.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }
      ":w\n".chars.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }

      refute_empty editor.quickfix_items, "quickfix should be populated after :w with syntax error"
      assert_nil editor.quickfix_index, "quickfix index should be nil before navigation"

      # Press ]q — should jump to first item (index 0)
      app.send(:handle_key, "]")
      app.send(:handle_key, "q")

      assert_equal 0, editor.quickfix_index
      first_item = editor.quickfix_items.first
      assert_equal first_item[:row], editor.current_window.cursor_y,
        "cursor should jump to first quickfix item on ]q"

      assert_match(/qf/, editor.message)
    end
  end

  def test_write_valid_clears_quickfix
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!

    Dir.mktmpdir do |dir|
      path = File.join(dir, "ok.rb")
      File.write(path, "puts 'hi'\n")

      ":e #{path}\n".chars.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }
      # Set some dummy quickfix items first
      editor.set_quickfix_list([{ buffer_id: editor.current_buffer.id, row: 0, col: 0, text: "dummy" }])
      refute_empty editor.quickfix_items

      ":w\n".chars.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }
      assert_empty editor.quickfix_items, "quickfix should be cleared after :w with valid file"
    end
  end

  def test_file_write_skips_on_save_when_onsavehook_disabled
    app = RuVim::App.new(clean: true)
    editor = app.instance_variable_get(:@editor)
    editor.materialize_intro_buffer!

    called = false
    hook_module = Module.new do
      define_method(:on_save) do |_ctx, _path|
        called = true
      end
      module_function :on_save
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.rb")
      editor.current_buffer.instance_variable_set(:@lang_module, hook_module)
      editor.current_buffer.replace_all_lines!(["hello"])
      editor.set_option("onsavehook", false)

      keys = ":w #{path}\n".chars
      keys.each { |k| app.send(:handle_key, k == "\n" ? :enter : k) }

      refute called, "on_save hook should NOT have been called when onsavehook is disabled"
    end
  end
end
