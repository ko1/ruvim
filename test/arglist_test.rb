require "test_helper"

class ArglistTest < Minitest::Test
  def setup
    @editor = RuVim::Editor.new
  end

  def test_initial_arglist_is_empty
    assert_empty @editor.arglist
    assert_equal 0, @editor.arglist_index
  end

  def test_set_arglist
    paths = %w[file1.txt file2.txt file3.txt]
    @editor.set_arglist(paths)
    
    assert_equal paths, @editor.arglist
    assert_equal 0, @editor.arglist_index
    assert_equal "file1.txt", @editor.arglist_current
  end

  def test_arglist_next
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt])
    
    assert_equal "file2.txt", @editor.arglist_next
    assert_equal 1, @editor.arglist_index
    
    assert_equal "file3.txt", @editor.arglist_next
    assert_equal 2, @editor.arglist_index
    
    error = assert_raises(RuVim::CommandError) do
      @editor.arglist_next
    end
    assert_equal "Already at last argument", error.message
  end

  def test_arglist_prev
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt])
    @editor.arglist_next(2) # Move to index 2
    
    assert_equal "file2.txt", @editor.arglist_prev
    assert_equal 1, @editor.arglist_index
    
    assert_equal "file1.txt", @editor.arglist_prev
    assert_equal 0, @editor.arglist_index
    
    error = assert_raises(RuVim::CommandError) do
      @editor.arglist_prev
    end
    assert_equal "Already at first argument", error.message
  end

  def test_arglist_first
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt])
    @editor.arglist_next(2) # Move to index 2
    
    assert_equal "file1.txt", @editor.arglist_first
    assert_equal 0, @editor.arglist_index
  end

  def test_arglist_last
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt])
    
    assert_equal "file3.txt", @editor.arglist_last
    assert_equal 2, @editor.arglist_index
  end

  def test_arglist_next_with_count
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt file4.txt])
    
    assert_equal "file3.txt", @editor.arglist_next(2)
    assert_equal 2, @editor.arglist_index
  end

  def test_arglist_prev_with_count
    @editor.set_arglist(%w[file1.txt file2.txt file3.txt file4.txt])
    @editor.arglist_last
    
    assert_equal "file2.txt", @editor.arglist_prev(2)
    assert_equal 1, @editor.arglist_index
  end

  def test_arglist_empty_operations
    assert_nil @editor.arglist_current
    assert_nil @editor.arglist_first
    assert_nil @editor.arglist_last
  end

  def test_startup_multiple_files_creates_buffers
    # Simulate what open_startup_paths! does without layout option:
    # all files should be loaded as buffers so they appear in :ls
    paths = [File.expand_path("../../t.md", __FILE__),
             File.expand_path("../../t.rb", __FILE__)]
    existing = paths.select { |p| File.exist?(p) }
    skip "need t.md and t.rb in project root" if existing.length < 2

    @editor.ensure_bootstrap_buffer!
    @editor.set_arglist(paths)

    # Open first file (displayed in current window)
    first_buf = @editor.add_buffer_from_file(paths[0])
    @editor.switch_to_buffer(first_buf.id)

    # Load remaining files as buffers (not displayed, but registered)
    paths[1..].each { |p| @editor.add_buffer_from_file(p) }

    # All files should be in the buffer list
    all_paths = @editor.buffer_ids.map { |id| @editor.buffers[id].path }
    paths.each do |p|
      assert_includes all_paths, p, "#{p} should appear in buffer list"
    end
  end
end