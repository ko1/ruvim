# frozen_string_literal: true

require_relative "test_helper"

class ExCommandRegistryTest < Minitest::Test
  def setup
    @registry = RuVim::ExCommandRegistry.instance
    @saved_specs = @registry.instance_variable_get(:@specs).dup
    @saved_lookup = @registry.instance_variable_get(:@lookup).dup
  end

  def teardown
    @registry.instance_variable_set(:@specs, @saved_specs)
    @registry.instance_variable_set(:@lookup, @saved_lookup)
  end

  def test_register_and_resolve
    @registry.clear!
    spec = @registry.register("testcmd", call: ->(_ctx) {}, desc: "test")
    assert_equal "testcmd", spec.name

    resolved = @registry.resolve("testcmd")
    assert_equal spec, resolved
  end

  def test_register_with_aliases
    @registry.clear!
    spec = @registry.register("testcmd", call: ->(_ctx) {}, aliases: ["tc", "tcmd"])

    assert_equal @registry.resolve("tc"), spec
    assert_equal @registry.resolve("tcmd"), spec
  end

  def test_register_duplicate_raises
    @registry.clear!
    @registry.register("testcmd", call: ->(_ctx) {})

    assert_raises(RuVim::CommandError) do
      @registry.register("testcmd", call: ->(_ctx) {})
    end
  end

  def test_register_alias_collision_raises
    @registry.clear!
    @registry.register("cmd1", call: ->(_ctx) {}, aliases: ["shared"])

    assert_raises(RuVim::CommandError) do
      @registry.register("cmd2", call: ->(_ctx) {}, aliases: ["shared"])
    end
  end

  def test_resolve_returns_nil_for_unknown
    @registry.clear!
    assert_nil @registry.resolve("nonexistent")
  end

  def test_fetch_raises_for_unknown
    @registry.clear!
    assert_raises(RuVim::CommandError) do
      @registry.fetch("nonexistent")
    end
  end

  def test_fetch_returns_spec
    @registry.clear!
    spec = @registry.register("testcmd", call: ->(_ctx) {})
    assert_equal spec, @registry.fetch("testcmd")
  end

  def test_registered?
    @registry.clear!
    refute @registry.registered?("testcmd")
    @registry.register("testcmd", call: ->(_ctx) {})
    assert @registry.registered?("testcmd")
  end

  def test_all_returns_sorted
    @registry.clear!
    @registry.register("beta", call: ->(_ctx) {})
    @registry.register("alpha", call: ->(_ctx) {})
    names = @registry.all.map(&:name)
    assert_equal ["alpha", "beta"], names
  end

  def test_unregister
    @registry.clear!
    @registry.register("testcmd", call: ->(_ctx) {}, aliases: ["tc"])

    removed = @registry.unregister("testcmd")
    assert_equal "testcmd", removed.name
    assert_nil @registry.resolve("testcmd")
    assert_nil @registry.resolve("tc")
  end

  def test_unregister_unknown_returns_nil
    @registry.clear!
    assert_nil @registry.unregister("nonexistent")
  end

  def test_clear!
    @registry.clear!
    @registry.register("testcmd", call: ->(_ctx) {})
    @registry.clear!
    assert_equal [], @registry.all
  end
end
