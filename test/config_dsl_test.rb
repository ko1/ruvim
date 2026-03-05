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

  def test_nmap_with_command_id_string
    @command_registry.register("test.cmd", call: ->(_ctx, **) {}, desc: "test", source: :builtin)
    @dsl.nmap("T", "test.cmd")
    match = @keymaps.resolve(:normal, ["T"])
    assert_equal :match, match.status
    assert_equal "test.cmd", match.invocation.id
  end

  def test_nmap_without_command_id_or_block_raises
    # ConfigDSL < BasicObject, so raise becomes NoMethodError for ::ArgumentError
    assert_raises(NoMethodError, ArgumentError) { @dsl.nmap("T") }
  end

  def test_imap_without_block_or_id_raises
    assert_raises(NoMethodError, ArgumentError) { @dsl.imap("T") }
  end

  def test_command_registers_user_command
    @dsl.command("my.cmd", desc: "custom") { |_ctx, **| }
    spec = @command_registry.fetch("my.cmd")
    assert_equal :user, spec.source
    assert_equal "custom", spec.desc
  end

  def test_command_without_block_raises
    assert_raises(NoMethodError, ArgumentError) { @dsl.command("my.cmd") }
  end

  def test_nmap_with_filetype
    dsl = RuVim::ConfigDSL.new(
      command_registry: @command_registry,
      ex_registry: @ex_registry,
      keymaps: @keymaps,
      command_host: RuVim::GlobalCommands.instance,
      filetype: "ruby"
    )
    dsl.nmap("K", desc: "ft test") { |_ctx, **| }
    editor = fresh_editor
    editor.current_buffer.options["filetype"] = "ruby"
    match = @keymaps.resolve_with_context(:normal, ["K"], editor: editor)
    assert_equal :match, match.status
  end

  def test_set_option_requires_editor
    assert_raises(NoMethodError, ArgumentError) { @dsl.set("number") }
  end

  def test_set_boolean_option
    editor = fresh_editor
    dsl = RuVim::ConfigDSL.new(
      command_registry: @command_registry,
      ex_registry: @ex_registry,
      keymaps: @keymaps,
      command_host: RuVim::GlobalCommands.instance,
      editor: editor
    )
    dsl.set("number")
    assert editor.get_option("number")
  end

  def test_set_no_prefix_disables_option
    editor = fresh_editor
    dsl = RuVim::ConfigDSL.new(
      command_registry: @command_registry,
      ex_registry: @ex_registry,
      keymaps: @keymaps,
      command_host: RuVim::GlobalCommands.instance,
      editor: editor
    )
    dsl.set("number")
    dsl.set("nonumber")
    refute editor.get_option("number")
  end

  def test_set_with_value
    editor = fresh_editor
    dsl = RuVim::ConfigDSL.new(
      command_registry: @command_registry,
      ex_registry: @ex_registry,
      keymaps: @keymaps,
      command_host: RuVim::GlobalCommands.instance,
      editor: editor
    )
    dsl.set("tabstop=4")
    assert_equal 4, editor.get_option("tabstop")
  end
end
