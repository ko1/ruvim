require_relative "test_helper"
require "stringio"
require "tempfile"

class CLITest < Minitest::Test
  def test_parse_clean_and_u_none
    opts = RuVim::CLI.parse(["--clean", "-u", "NONE"])

    assert_equal true, opts.clean
    assert_equal true, opts.skip_user_config
    assert_nil opts.config_path
  end

  def test_parse_startup_actions_preserves_order
    opts = RuVim::CLI.parse(["+10", "-c", "set number", "+", "file.txt"])

    assert_equal ["file.txt"], opts.files
    assert_equal [
      { type: :line, value: 10 },
      { type: :ex, value: "set number" },
      { type: :line_end }
    ], opts.startup_actions
  end

  def test_parse_pre_config_cmd_option
    opts = RuVim::CLI.parse(["--cmd", "set number", "--cmd=set relativenumber", "file.txt"])

    assert_equal ["file.txt"], opts.files
    assert_equal [
      { type: :ex, value: "set number" },
      { type: :ex, value: "set relativenumber" }
    ], opts.pre_config_actions
    assert_equal [], opts.startup_actions
  end

  def test_parse_custom_config_path
    opts = RuVim::CLI.parse(["-u", "/tmp/ruvimrc.rb"])

    assert_equal false, opts.skip_user_config
    assert_equal "/tmp/ruvimrc.rb", opts.config_path
  end

  def test_parse_readonly_option
    opts = RuVim::CLI.parse(["-R", "file.txt"])

    assert_equal true, opts.readonly
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_diff_mode_option
    opts = RuVim::CLI.parse(["-d", "file.txt"])

    assert_equal true, opts.diff_mode
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_quickfix_option
    opts = RuVim::CLI.parse(["-q", "errors.log", "file.txt"])

    assert_equal "errors.log", opts.quickfix_errorfile
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_session_option_with_and_without_argument
    opts1 = RuVim::CLI.parse(["-S", "Session.ruvim", "file.txt"])
    assert_equal "Session.ruvim", opts1.session_file
    assert_equal ["file.txt"], opts1.files

    opts2 = RuVim::CLI.parse(["-S"])
    assert_equal "Session.vim", opts2.session_file
  end

  def test_parse_nomodifiable_option
    opts = RuVim::CLI.parse(["-M", "file.txt"])

    assert_equal true, opts.nomodifiable
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_restricted_option
    opts = RuVim::CLI.parse(["-Z", "file.txt"])

    assert_equal true, opts.restricted_mode
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_verbose_options
    v1 = RuVim::CLI.parse(["-V", "file.txt"])
    assert_equal 1, v1.verbose_level

    v2 = RuVim::CLI.parse(["-V2", "file.txt"])
    assert_equal 2, v2.verbose_level

    v3 = RuVim::CLI.parse(["--verbose=3", "file.txt"])
    assert_equal 3, v3.verbose_level
  end

  def test_parse_startuptime_option
    opts = RuVim::CLI.parse(["--startuptime", "/tmp/ruvim-startup.log", "file.txt"])

    assert_equal "/tmp/ruvim-startup.log", opts.startup_time_path
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_n_option_as_accepted_no_op
    opts = RuVim::CLI.parse(["-n", "file.txt"])

    assert_equal true, opts.no_swap
    assert_equal ["file.txt"], opts.files
  end

  def test_parse_split_and_tab_layout_options
    o = RuVim::CLI.parse(["-o", "a", "b"])
    assert_equal :horizontal, o.startup_open_layout
    assert_nil o.startup_open_count

    ov = RuVim::CLI.parse(["-O3", "a", "b"])
    assert_equal :vertical, ov.startup_open_layout
    assert_equal 3, ov.startup_open_count

    p = RuVim::CLI.parse(["-p2", "a", "b"])
    assert_equal :tab, p.startup_open_layout
    assert_equal 2, p.startup_open_count
  end

  def test_help_and_version_return_without_starting_ui
    out = StringIO.new
    err = StringIO.new

    code = RuVim::CLI.run(["--version"], stdout: out, stderr: err, stdin: StringIO.new)
    assert_equal 0, code
    assert_match(/RuVim /, out.string)
    assert_equal "", err.string

    out = StringIO.new
    err = StringIO.new
    code = RuVim::CLI.run(["--help"], stdout: out, stderr: err, stdin: StringIO.new)
    assert_equal 0, code
    assert_match(/Usage: ruvim/, out.string)
    assert_match(/-R\s+Open file readonly/, out.string)
    assert_match(/-d\s+Diff mode requested/, out.string)
    assert_match(/-q \{errorfile\}\s+Quickfix startup placeholder/, out.string)
    assert_match(/-S \[session\]\s+Session startup placeholder/, out.string)
    assert_match(/-M\s+Open file unmodifiable/, out.string)
    assert_match(/-Z\s+Restricted mode/, out.string)
    assert_match(/-V\[N\], --verbose/, out.string)
    assert_match(/--startuptime FILE/, out.string)
    assert_match(/--cmd \{cmd\}/, out.string)
    assert_match(/-n\s+No-op/, out.string)
    assert_match(/-o\[N\]/, out.string)
    assert_match(/-O\[N\]/, out.string)
    assert_match(/-p\[N\]/, out.string)
    assert_equal "", err.string
  end

  def test_run_returns_error_for_missing_config_file
    out = StringIO.new
    err = StringIO.new

    code = RuVim::CLI.run(["-u", "/tmp/ruvim/no-such-config.rb"], stdout: out, stderr: err, stdin: StringIO.new)

    assert_equal 2, code
    assert_match(/config file not found/, err.string)
  end
end
