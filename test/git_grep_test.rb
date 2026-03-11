# frozen_string_literal: true

require_relative "test_helper"

class GitGrepTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @key_handler = @app.instance_variable_get(:@key_handler)
    @editor.materialize_intro_buffer!
  end

  def feed(*keys)
    keys.each { |k| @key_handler.handle(k) }
  end

  # --- Parsing ---

  def test_parse_location_basic
    line = "lib/ruvim/app.rb:42:    def run"
    result = RuVim::Commands::Git::Grep.parse_location(line)
    assert_equal ["lib/ruvim/app.rb", 42], result
  end

  def test_parse_location_no_line_number
    line = "lib/ruvim/app.rb:    def run"
    result = RuVim::Commands::Git::Grep.parse_location(line)
    assert_nil result
  end

  def test_parse_location_empty
    result = RuVim::Commands::Git::Grep.parse_location("")
    assert_nil result
  end

  def test_parse_location_separator_line
    result = RuVim::Commands::Git::Grep.parse_location("--")
    assert_nil result
  end

  def test_parse_location_with_colon_in_content
    line = "config.rb:10:  url = \"http://example.com\""
    result = RuVim::Commands::Git::Grep.parse_location(line)
    assert_equal ["config.rb", 10], result
  end

  def test_parse_location_windows_style_path
    line = "src/main.rb:5:hello"
    result = RuVim::Commands::Git::Grep.parse_location(line)
    assert_equal ["src/main.rb", 5], result
  end

  # --- Command registration ---

  def test_git_grep_subcommand_registered
    assert RuVim::Commands::Git::Handler::GIT_SUBCOMMANDS.key?("grep")
  end

  def test_git_grep_open_file_command_registered
    cmd = RuVim::CommandRegistry.instance
    assert cmd.registered?("git.grep.open_file")
  end
end
