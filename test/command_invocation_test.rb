require_relative "test_helper"

class CommandInvocationTest < Minitest::Test
  def test_bang_defaults_to_false
    inv = RuVim::CommandInvocation.new(id: "test")
    assert_equal false, inv.bang
  end

  def test_bang_true
    inv = RuVim::CommandInvocation.new(id: "test", bang: true)
    assert_equal true, inv.bang
  end

  def test_bang_false
    inv = RuVim::CommandInvocation.new(id: "test", bang: false)
    assert_equal false, inv.bang
  end

  def test_argv_defaults_to_empty_array
    inv = RuVim::CommandInvocation.new(id: "test")
    assert_equal [], inv.argv
  end

  def test_kwargs_defaults_to_empty_hash
    inv = RuVim::CommandInvocation.new(id: "test")
    assert_equal({}, inv.kwargs)
  end

  def test_count_defaults_to_nil
    inv = RuVim::CommandInvocation.new(id: "test")
    assert_nil inv.count
  end
end
