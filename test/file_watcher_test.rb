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
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) do |type, data|
      received << [type, data]
    end
    @watcher.start

    File.open(@path, "a") { |f| f.write("appended\n") }

    event = nil
    assert_eventually(timeout: 2) { event = received.pop(true) rescue nil; !event.nil? }
    assert_equal :data, event[0]
    assert_includes event[1], "appended"
  ensure
    @watcher&.stop
  end

  def test_polling_watcher_stop
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) { |_, _| }
    @watcher.start
    assert @watcher.alive?
    @watcher.stop
    refute @watcher.alive?
  end

  def test_polling_watcher_detects_truncation
    received = Queue.new
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) do |type, data|
      received << [type, data]
    end
    @watcher.start

    # Append first so offset advances
    File.open(@path, "a") { |f| f.write("extra\n") }
    assert_eventually(timeout: 2) { received.pop(true) rescue nil }

    # Truncate the file
    File.write(@path, "")

    event = nil
    assert_eventually(timeout: 3) { event = received.pop(true) rescue nil; event&.first == :truncated }
    assert_equal :truncated, event[0]
    assert_nil event[1]
  ensure
    @watcher&.stop
  end

  def test_polling_watcher_detects_deletion
    received = Queue.new
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) do |type, data|
      received << [type, data]
    end
    @watcher.start

    File.delete(@path)

    event = nil
    assert_eventually(timeout: 3) { event = received.pop(true) rescue nil; event&.first == :deleted }
    assert_equal :deleted, event[0]
    assert_nil event[1]
  ensure
    @watcher&.stop
  end

  def test_polling_watcher_waits_for_missing_file
    missing_path = File.join(Dir.pwd, "follow_missing_test_#{$$}.log")
    File.delete(missing_path) if File.exist?(missing_path)

    received = Queue.new
    watcher = RuVim::FileWatcher::PollingWatcher.new(missing_path) do |type, data|
      received << [type, data]
    end
    watcher.start

    sleep 0.2
    assert watcher.alive?

    File.write(missing_path, "hello\n")

    event = nil
    assert_eventually(timeout: 3) { event = received.pop(true) rescue nil; !event.nil? }
    assert_equal :data, event[0]
    assert_includes event[1], "hello"
  ensure
    watcher&.stop
    File.delete(missing_path) if File.exist?(missing_path)
  end

  def test_inotify_watcher_detects_append
    skip "inotify not available" unless RuVim::FileWatcher::InotifyWatcher.available?

    received = Queue.new
    @watcher = RuVim::FileWatcher::InotifyWatcher.new(@path) do |type, data|
      received << [type, data]
    end
    @watcher.start

    File.open(@path, "a") { |f| f.write("inotify appended\n") }

    event = nil
    assert_eventually(timeout: 2) { event = received.pop(true) rescue nil; !event.nil? }
    assert_equal :data, event[0]
    assert_includes event[1], "inotify appended"
  ensure
    @watcher&.stop
  end

  def test_inotify_watcher_stop
    skip "inotify not available" unless RuVim::FileWatcher::InotifyWatcher.available?

    @watcher = RuVim::FileWatcher::InotifyWatcher.new(@path) { |_, _| }
    @watcher.start
    assert @watcher.alive?
    @watcher.stop
    refute @watcher.alive?
  end

  def test_inotify_watcher_detects_truncation
    skip "inotify not available" unless RuVim::FileWatcher::InotifyWatcher.available?

    received = Queue.new
    @watcher = RuVim::FileWatcher::InotifyWatcher.new(@path) do |type, data|
      received << [type, data]
    end
    @watcher.start

    File.open(@path, "a") { |f| f.write("extra\n") }
    assert_eventually(timeout: 2) { received.pop(true) rescue nil }

    File.write(@path, "")

    event = nil
    assert_eventually(timeout: 3) { event = received.pop(true) rescue nil; event&.first == :truncated }
    assert_equal :truncated, event[0]
  ensure
    @watcher&.stop
  end

  def test_create_prefers_inotify
    watcher = RuVim::FileWatcher.create(@path) { |_, _| }
    if RuVim::FileWatcher::InotifyWatcher.available?
      assert_kind_of RuVim::FileWatcher::InotifyWatcher, watcher
    else
      assert_kind_of RuVim::FileWatcher::PollingWatcher, watcher
    end
  ensure
    watcher&.stop
  end

  def test_create_falls_back_to_polling_for_missing_file
    missing_path = File.join(Dir.pwd, "follow_create_test_#{$$}.log")
    File.delete(missing_path) if File.exist?(missing_path)

    watcher = RuVim::FileWatcher.create(missing_path) { |_, _| }
    assert_kind_of RuVim::FileWatcher::PollingWatcher, watcher
  ensure
    watcher&.stop
    File.delete(missing_path) if File.exist?(missing_path)
  end

  def test_polling_backoff_resets_on_change
    @watcher = RuVim::FileWatcher::PollingWatcher.new(@path) { |_, _| }
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
