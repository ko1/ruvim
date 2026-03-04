This project is RuVim, a Vim-like editor written in Ruby. Always run the full test suite (`rake test` or equivalent) after making code changes and confirm all tests pass before committing.

* check docs/ to understand the specification
  * docs/spec.md
  * docs/todo.md
* When modifying the source code
  * write tests first, then implement (test-first)
  * update docs/
    * catch up changes
    * move completed tasks to done.md
  * update CLAUDE.md Source Tree section if files were added, removed, or renamed
  * commit it
* After committing, show the commit message

## Source Tree

### Architecture

```
CLI (exe/ruvim) → CLI.parse() → App.new() → App.run_ui_loop()
  Input.read_key() → KeymapManager.resolve() → Dispatcher.dispatch()
  → GlobalCommands.<method>() → Editor state update → Screen.render() → Terminal.write()
```

### Core (lib/ruvim/)

| File | Description |
|------|-------------|
| `app.rb` | Main application loop, input handling, startup |
| `editor.rb` | Editor state: buffers, windows, options, registers, marks, modes |
| `buffer.rb` | Text buffer (lines, file I/O, encoding) |
| `window.rb` | View of a buffer (cursor, scroll, grapheme-aware movement) |
| `global_commands.rb` | All built-in command implementations (cursor, edit, search, visual, etc.) |
| `screen.rb` | Rendering: window layout, syntax highlight, line numbers, status line, wrap |
| `dispatcher.rb` | Routes commands; parses Ex ranges/substitute; shell execution |
| `keymap_manager.rb` | Key-to-command mapping with layers (filetype > buffer > mode > global) |
| `input.rb` | Raw keyboard input, ANSI escape sequence parsing |
| `terminal.rb` | Terminal I/O: raw mode, alternate screen, winsize |
| `command_line.rb` | Command-line text/cursor state |
| `command_registry.rb` | Normal/insert mode command registry (singleton) |
| `ex_command_registry.rb` | Ex command registry (singleton) |
| `cli.rb` | CLI argument parsing, `--help`, `--version` |
| `config_loader.rb` | Load `~/.config/ruvim/init.rb` and ftplugin |
| `config_dsl.rb` | User config DSL: `nmap`, `imap`, `set`, `command`, `colorscheme` |
| `display_width.rb` | Character display width (CJK, emoji, combining marks) |
| `text_metrics.rb` | Grapheme-aware text measurement and navigation |
| `keyword_chars.rb` | Word character definition (iskeyword) |
| `highlighter.rb` | Syntax highlighting via Prism (Ruby) |
| `clipboard.rb` | System clipboard access (xclip, pbpaste, etc.) |
| `context.rb` | Command handler context (editor, window, buffer, invocation) |
| `command_invocation.rb` | Single command invocation (id, argv, count, bang) |
| `rich_view.rb` | Rich view mode (TSV/CSV table rendering) |
| `rich_view/table_renderer.rb` | Table formatting with display-width-aware column alignment |

### Tests (test/)

- Unit: `buffer_test`, `window_test`, `editor_test`, `screen_test`, `display_width_test`, `text_metrics_test`, `keymap_manager_test`, `highlighter_test`, `dispatcher_test`, `config_*_test`
- Integration: `app_scenario_test`, `app_motion_test`, `app_text_object_test`, `app_register_test`, `app_dot_repeat_test`, `app_completion_test`, `app_unicode_behavior_test`, `render_snapshot_test`
- Helper: `test_helper.rb` (fresh_editor, Minitest)

### Docs (docs/)

`spec.md` (feature spec), `command.md`, `binding.md`, `config.md`, `tutorial.md`, `vim_diff.md`, `plugin.md`, `todo.md`, `done.md`

## Debugging (Lumitrace)

lumitrace is a tool that records runtime values of each Ruby expression.
When a test fails, read `lumitrace help` first, then use it.
Basic: `lumitrace -t exec rake test`

When fixing bugs, do NOT assume the first fix attempt is correct. After applying a fix, re-read the relevant code paths to verify the fix addresses the actual root cause, not a symptom. If the user says 'it hasn't changed' or equivalent, start fresh analysis from the failing behavior.

## misc

The user communicates in both English and Japanese. Respond in the same language the user uses. When the user gives feedback like 変わってないですよ ('it hasn't changed'), treat it as a bug report requiring re-analysis.

