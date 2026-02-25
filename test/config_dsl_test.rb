require_relative "test_helper"

class ConfigDSLTest < Minitest::Test
  FakeCommandSpec = Struct.new(:id, :call, :desc, :source, keyword_init: true)

  class FakeCommandRegistry
    attr_reader :specs

    def initialize
      @specs = {}
    end

    def register(id, call:, desc:, source:)
      @specs[id.to_s] = FakeCommandSpec.new(id: id.to_s, call:, desc:, source:)
    end

    def fetch(id)
      @specs.fetch(id.to_s)
    end
  end

  class FakeExRegistry
    def registered?(_name)
      false
    end

    def unregister(_name)
      nil
    end

    def register(*)
      nil
    end
  end

  def setup
    @command_registry = FakeCommandRegistry.new
    @ex_registry = FakeExRegistry.new
    @keymaps = RuVim::KeymapManager.new
    @dsl = RuVim::ConfigDSL.new(
      command_registry: @command_registry,
      ex_registry: @ex_registry,
      keymaps: @keymaps,
      command_host: RuVim::GlobalCommands.instance
    )
  end

  def test_nmap_block_registers_inline_command_and_binds_key
    @dsl.nmap("K", desc: "Show name") { |ctx, **| ctx.editor.echo(ctx.buffer.display_name) }

    match = @keymaps.resolve(:normal, ["K"])
    assert_equal :match, match.status
    refute_nil match.invocation
    assert match.invocation.id.start_with?("user.keymap.normal.")

    spec = @command_registry.fetch(match.invocation.id)
    assert_equal :user, spec.source
    assert_equal "Show name", spec.desc
    assert_respond_to spec.call, :call
  end

  def test_imap_block_registers_insert_mode_binding
    @dsl.imap("Q", desc: "Insert helper") { |_ctx, **| }

    match = @keymaps.resolve(:insert, ["Q"])
    assert_equal :match, match.status
    assert match.invocation.id.start_with?("user.keymap.insert.")
  end

  def test_map_global_block_binds_fallback_layer_when_mode_nil
    @dsl.map_global("Z", mode: nil, desc: "Global fallback") { |_ctx, **| }

    editor = fresh_editor
    match = @keymaps.resolve_with_context(:normal, ["Z"], editor: editor)
    assert_equal :match, match.status
    assert match.invocation.id.start_with?("user.keymap.global.")
  end
end
