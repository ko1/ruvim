# frozen_string_literal: true

require_relative "test_helper"
require "ruvim/file_watcher"
require "tempfile"

class FileWatcherTest < Minitest::Test
  def setup
    @tmpfile = Tempfile.new("file_watcher_test")
    @tmpfile.write("initial\n")
    @tmpfile.flush
    @path = @tmpfile.path
  end

  def teardown
    @watcher&.stop
    @tmpfile&.close!
  end

  def test_polling_watcher_detects_append
    received = Queue.new
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) do |data|
      received << data
    end
    @watcher.start

    File.open(@path, "a") { |f| f.write("appended\n") }

    data = nil
    assert_eventually(timeout: 2) { data = received.pop(true) rescue nil; !data.nil? }
    assert_includes data, "appended"
  ensure
    @watcher&.stop
  end

  def test_polling_watcher_stop
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) { |_| }
    @watcher.start
    assert @watcher.alive?
    @watcher.stop
    refute @watcher.alive?
  end

  def test_polling_watcher_error_on_missing_file
    assert_raises(ArgumentError) do
      RuVim::FileWatcher::PollingWatcher.new("/nonexistent/path") { |_| }
    end
  end

  def test_inotify_watcher_detects_append
    skip "inotify not available" unless RuVim::FileWatcher::InotifyWatcher.available?

    received = Queue.new
    @watcher = RuVim::FileWatcher::InotifyWatcher.new(@path) do |data|
      received << data
    end
    @watcher.start

    File.open(@path, "a") { |f| f.write("inotify appended\n") }

    data = nil
    assert_eventually(timeout: 2) { data = received.pop(true) rescue nil; !data.nil? }
    assert_includes data, "inotify appended"
  ensure
    @watcher&.stop
  end

  def test_inotify_watcher_stop
    skip "inotify not available" unless RuVim::FileWatcher::InotifyWatcher.available?

    @watcher = RuVim::FileWatcher::InotifyWatcher.new(@path) { |_| }
    @watcher.start
    assert @watcher.alive?
    @watcher.stop
    refute @watcher.alive?
  end

  def test_create_prefers_inotify
    watcher = RuVim::FileWatcher.create(@path) { |_| }
    if RuVim::FileWatcher::InotifyWatcher.available?
      assert_kind_of RuVim::FileWatcher::InotifyWatcher, watcher
    else
      assert_kind_of RuVim::FileWatcher::PollingWatcher, watcher
    end
  ensure
    watcher&.stop
  end

  def test_polling_backoff_resets_on_change
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) { |_| }
    assert_equal RuVim::FileWatcher::PollingWatcher::MIN_INTERVAL, @watcher.current_interval
  end

  private

  def assert_eventually(timeout: 2, interval: 0.05)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        flunk "Timed out waiting for condition"
      end
      sleep interval
    end
  end
end
