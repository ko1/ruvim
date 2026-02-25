require_relative "test_helper"

class KeymapManagerTest < Minitest::Test
  def setup
    @km = RuVim::KeymapManager.new
    @editor = fresh_editor
  end

  def test_mode_local_beats_global
    @km.bind_global("x", "global.x")
    @km.bind(:normal, "x", "normal.x")

    match = @km.resolve_with_context(:normal, ["x"], editor: @editor)
    assert_equal :match, match.status
    assert_equal "normal.x", match.invocation.id
  end

  def test_buffer_local_beats_mode_local
    @km.bind(:normal, "x", "normal.x")
    @km.bind_buffer(@editor.current_buffer.id, "x", "buffer.x")

    match = @km.resolve_with_context(:normal, ["x"], editor: @editor)
    assert_equal "buffer.x", match.invocation.id
  end

  def test_prefix_pending_and_match
    @km.bind(:normal, "dd", "delete.line")

    pending = @km.resolve_with_context(:normal, ["d"], editor: @editor)
    assert_equal :pending, pending.status

    exact = @km.resolve_with_context(:normal, %w[d d], editor: @editor)
    assert_equal :match, exact.status
    assert_equal "delete.line", exact.invocation.id
  end

  def test_filetype_local_map_respects_mode
    @editor.current_buffer.options["filetype"] = "ruby"
    @km.bind(:normal, "x", "normal.x")
    @km.bind_filetype("ruby", "x", "ruby.insert.x", mode: :insert)

    normal = @km.resolve_with_context(:normal, ["x"], editor: @editor)
    assert_equal "normal.x", normal.invocation.id

    insert = @km.resolve_with_context(:insert, ["x"], editor: @editor)
    assert_equal "ruby.insert.x", insert.invocation.id
  end
end
