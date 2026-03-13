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
    * note that CLAUDE.md is a symbolic link to AGENTS.md. Commit AGENTS.md if modify CLAUDE.md
  * commit it
* After committing, show the commit message

## Source Tree

### Architecture

```
CLI (exe/ruvim) → CLI.parse() → App.new() → App.run_ui_loop()
  Input.read_key() → KeymapManager.resolve() → Dispatcher.dispatch()
  → GlobalCommands.<method>() → Editor state update → Screen.render() → Terminal.write()
```

### Class Hierarchy

```
RuVim::Stream
├── Stream::Stdin
├── Stream::Run
├── Stream::Follow
└── Stream::FileLoad

RuVim::Lang::Base
├── Lang::Ruby
├── Lang::Markdown
├── Lang::Json
├── Lang::Scheme
├── Lang::C
│   └── Lang::Cpp
├── Lang::Javascript
│   └── Lang::Typescript
├── Lang::Diff
├── Lang::Yaml
├── Lang::Sh
├── Lang::Python
├── Lang::Html
├── Lang::Toml
├── Lang::Go
├── Lang::Rust
├── Lang::Makefile
├── Lang::Dockerfile
├── Lang::Sql
├── Lang::Elixir
├── Lang::Perl
├── Lang::Lua
├── Lang::Ocaml
├── Lang::Erb
└── Lang::Gitcommit

RuVim::ConfigDSL < BasicObject
```

### Module Inclusions

```
Editor
  includes: Options, Registers, MarksJumps, Quickfix, LayoutTree, Filetype

KeyHandler
  includes: PendingState, MacroDot, InsertMode

GlobalCommands (singleton)
  includes: Commands::Motion, Commands::Edit, Commands::Register,
            Commands::Search, Commands::Window, Commands::Buffer, Commands::Meta
  lazy-loads: Commands::Git::Handler, Commands::Gh::Handler (via method_missing)
```

### Singletons

- `CommandRegistry` — normal/insert mode command specs (`include Singleton`)
- `ExCommandRegistry` — Ex command specs and alias lookup (`include Singleton`)
- `GlobalCommands` — command handler host (`include Singleton`)
- `SpellChecker` — spell checking (`include Singleton`)
- `Lang::Base` — frozen instance pattern (`.instance`)

### Object Dependency Graph

```
App
├── Terminal ─────────────────────────────────── stdin/stdout I/O
├── Input ────────────────────────────────────── keyboard parsing (reads from Terminal)
├── Screen ───────────────────────────────────── rendering (writes to Terminal)
├── KeymapManager ────────────────────────────── key-to-command resolution (LayerMap)
├── Dispatcher
│   ├── CommandRegistry (singleton)
│   ├── ExCommandRegistry (singleton)
│   └── GlobalCommands (singleton)
├── Editor
│   ├── Buffer[] ─────── @lang_module (Lang::*), @stream (Stream::*), @options
│   ├── Window[] ─────── @buffer_id → Buffer, @options
│   ├── CommandLine
│   ├── @keymap_manager ← injected by App
│   └── @stream_mixer ── injected by App
├── StreamMixer
│   ├── @editor ───────── injected by App
│   └── Stream::* ─────── managed stream instances
├── KeyHandler
│   ├── @editor ───────── injected by App
│   ├── @dispatcher ───── injected by App
│   └── CompletionManager
│       └── @editor ───── injected
└── ConfigLoader
    ├── CommandRegistry
    ├── ExCommandRegistry
    ├── KeymapManager
    └── GlobalCommands
    (creates ConfigDSL for eval context)
```

### Key Design Patterns

- **Dependency Injection**: App creates and wires all subsystems; Editor receives keymaps, stream_mixer, callbacks
- **Lazy Loading**: autoload for Clipboard, Browser, SpellChecker, FileWatcher, Git::Handler, Gh::Handler, all Lang::* modules
- **Dual Implementation**: DisplayWidth and TextMetrics have C extension + Pure Ruby fallback
- **State Machines**: KeyHandler manages pending states (operator, register, mark, jump, find, replace, macro)
- **Layered Resolution**: KeymapManager resolves keys via filetype > buffer > mode > global layers with prefix index

### Core (lib/ruvim/)

| File | Description |
|------|-------------|
| `app.rb` | Main application: initialization, run loop, config, startup; autoloads Clipboard, Browser, SpellChecker, FileWatcher |
| `key_handler.rb` | Key input dispatch, mode handling, normal/visual/command-line/rich modes |
| `key_handler/pending_state.rb` | Pending state machines (operator, register, mark, jump, replace, find) |
| `key_handler/macro_dot.rb` | Macro recording/playback, dot repeat |
| `key_handler/insert_mode.rb` | Insert mode key handling, autoindent, backspace, tab |
| `completion_manager.rb` | Command-line/insert completion, history, incsearch preview |
| `stream_mixer.rb` | Stream coordinator: event queue, drain, editor integration |
| `stream.rb` | Stream base class (state, live?, status, stop!) |
| `stream/stdin.rb` | Stream::Stdin — reads from stdin pipe |
| `stream/run.rb` | Stream::Run — command execution (PTY or IO.popen with chdir) |
| `stream/follow.rb` | Stream::Follow — file watcher (inotify/polling) |
| `stream/file_load.rb` | Stream::FileLoad — async large file loading |
| `editor.rb` | Editor state: buffers, windows, modes, visual, rich, tabpages, filetype |
| `editor/options.rb` | Option system (OPTION_DEFS, get/set/effective, coercion) |
| `editor/registers.rb` | Register management (named, numbered, clipboard integration) |
| `editor/marks_jumps.rb` | Marks, jump list, jump_to_location |
| `editor/quickfix.rb` | Quickfix and location list management |
| `editor/layout_tree.rb` | Layout tree helpers (split, remove, rects, leaves) |
| `editor/filetype.rb` | Filetype detection (basename, extension, shebang) and assignment |
| `buffer.rb` | Text buffer (lines, file I/O, encoding) |
| `window.rb` | View of a buffer (cursor, scroll, grapheme-aware movement) |
| `global_commands.rb` | Command host (singleton, includes command modules, lazy-loads Git::Handler/Gh::Handler via method_missing) |
| `commands/motion.rb` | Cursor movement, scrolling, word movement, bracket matching |
| `commands/edit.rb` | Insert mode, delete, change, join, replace, indent, undo/redo, text objects, range operations |
| `commands/register.rb` | Yank, paste, visual yank/delete, register operations |
| `commands/search.rb` | Search, substitute, global, filter, grep, quickfix/location list, spell, vimgrep |
| `commands/window.rb` | Window split/focus/close/resize, tab operations |
| `commands/buffer.rb` | Buffer management, file I/O, quit, marks, jumps, arglist, rich view, read |
| `commands/meta.rb` | Meta commands (help, set, bindings, ruby eval, run, shell, define command, normal exec) |
| `screen.rb` | Rendering: window layout, syntax highlight, line numbers, status line, wrap |
| `dispatcher.rb` | Routes commands; parses Ex ranges/substitute; shell execution |
| `keymap_manager.rb` | Key-to-command mapping with layers (filetype > buffer > mode > global) |
| `input.rb` | Raw keyboard input, ANSI escape sequence parsing |
| `terminal.rb` | Terminal I/O: raw mode, alternate screen, winsize |
| `editor/command_line.rb` | Command-line text/cursor state |
| `command_registry.rb` | Normal/insert mode command registry (singleton) |
| `ex_command_registry.rb` | Ex command registry (singleton) |
| `cli.rb` | CLI argument parsing, `--help`, `--version` |
| `config/config_loader.rb` | Load `~/.config/ruvim/init.rb` and ftplugin |
| `config/config_dsl.rb` | User config DSL: `nmap`, `imap`, `set`, `command`, `colorscheme` |
| `config/defaults.rb` | Built-in command/Ex registration and default key bindings |
| `display_width.rb` | Character display width (CJK, emoji, combining marks) |
| `text_metrics.rb` | Grapheme-aware text measurement and navigation |
| `keyword_chars.rb` | Word character definition (iskeyword) |
| `spell_checker.rb` | Spell checking (Pure Ruby, /usr/share/dict/words dictionary, singleton) |
| `lang/registry.rb` | Central lang registry (filetype detection, buffer_defaults lookup); autoloads all lang/* modules on demand |
| `lang/base.rb` | Base lang class: apply_regex, color constants, no-op indent/dedent/on_save instance method defaults |
| `lang/markdown.rb` | Markdown parsing, detection helpers, and syntax highlight colors |
| `lang/ruby.rb` | Ruby syntax highlighting via Prism lexer; auto-indent calculation |
| `lang/json.rb` | JSON syntax highlighting via regex; auto-indent |
| `lang/scheme.rb` | Scheme syntax highlighting via regex |
| `lang/c.rb` | C syntax highlighting, smart indent, on_save gcc check |
| `lang/cpp.rb` | C++ syntax highlighting (inherits C), access specifier indent, on_save g++ check |
| `lang/diff.rb` | Diff syntax highlighting (add/delete/hunk/header colors) |
| `lang/yaml.rb` | YAML syntax highlighting, auto-indent |
| `lang/sh.rb` | Shell/Bash syntax highlighting, auto-indent |
| `lang/python.rb` | Python syntax highlighting (builtins, decorators), auto-indent |
| `lang/javascript.rb` | JavaScript syntax highlighting, auto-indent |
| `lang/typescript.rb` | TypeScript syntax highlighting (inherits Javascript), auto-indent |
| `lang/html.rb` | HTML syntax highlighting (tags, attributes, entities) |
| `lang/toml.rb` | TOML syntax highlighting (tables, keys, datetime) |
| `lang/go.rb` | Go syntax highlighting, auto-indent |
| `lang/rust.rb` | Rust syntax highlighting (lifetimes, macros, attributes), auto-indent |
| `lang/makefile.rb` | Makefile syntax highlighting (targets, variables, directives) |
| `lang/dockerfile.rb` | Dockerfile syntax highlighting (instructions, variables) |
| `lang/sql.rb` | SQL syntax highlighting (case-insensitive keywords) |
| `lang/elixir.rb` | Elixir syntax highlighting (atoms, modules, sigils), auto-indent |
| `lang/perl.rb` | Perl syntax highlighting (sigils, POD), auto-indent |
| `lang/lua.rb` | Lua syntax highlighting (builtins), auto-indent |
| `lang/ocaml.rb` | OCaml syntax highlighting (type vars, block comments), auto-indent |
| `lang/erb.rb` | ERB syntax highlighting (HTML + Ruby delimiters/comments) |
| `lang/gitcommit.rb` | Git commit message syntax highlighting, spell default |
| `lang/tsv.rb` | TSV detection and RichView renderer registration |
| `lang/csv.rb` | CSV detection and RichView renderer registration |
| `commands/git/blame.rb` | Git blame: parser, runner, command handlers |
| `commands/git/status.rb` | Git status: runner, filename parser, command handlers |
| `commands/git/diff.rb` | Git diff: runner, command handlers |
| `commands/git/log.rb` | Git log: runner, command handlers |
| `commands/git/branch.rb` | Git branch: listing, checkout, command handlers |
| `commands/git/commit.rb` | Git commit: message buffer, execute, command handlers |
| `commands/git/grep.rb` | Git grep: search, location parser, command handlers |
| `commands/git/handler.rb` | Git module (repo_root), dispatcher, close, shared helpers; requires all git/* submodules |
| `commands/gh.rb` | GitHub link/browse/PR: URL generation, OSC 52 clipboard, dispatcher, command handlers |
| `file_watcher.rb` | File change monitoring (inotify with fiddle fallback to polling) |
| `clipboard.rb` | System clipboard access (xclip, pbpaste, etc.) |
| `browser.rb` | URL open (open/xdg-open/wslview/PowerShell) |
| `context.rb` | Command handler context (editor, window, buffer, invocation) |
| `command_invocation.rb` | Single command invocation (id, argv, count, bang) |
| `rich_view.rb` | Rich view mode (TSV/CSV/Markdown rendering); requires lang/tsv and lang/csv |
| `rich_view/table_renderer.rb` | Table formatting with display-width-aware column alignment |
| `rich_view/markdown_renderer.rb` | Markdown rendering (headings, inline, tables, code blocks, HR, image tags) |
| `rich_view/json_renderer.rb` | JSON pretty-print into virtual buffer |
| `rich_view/jsonl_renderer.rb` | JSONL per-line pretty-print into virtual buffer |
| `sixel.rb` | Pure Ruby PNG→Sixel encoder (PNG decoder, resize, quantize, encode, cache) |

### C Extension (ext/ruvim/)

| File | Description |
|------|-------------|
| `extconf.rb` | Build configuration for C extension |
| `ruvim_ext.c` | C implementation of DisplayWidth and TextMetrics hot paths |

### Benchmarks (benchmark/)

| File | Description |
|------|-------------|
| `hotspots.rb` | Profile individual function hotspots (pure Ruby) |
| `cext_compare.rb` | Compare Ruby vs C extension performance |
| `chunked_load.rb` | Compare file loading strategies |
| `file_load.rb` | Profile large file loading bottlenecks |
| `resolve_layers.rb` | Benchmark KeymapManager resolve with prefix index |
| `load_history.rb` | Benchmark CompletionManager load_history! |

### Tests (test/)

- Unit: `buffer_test`, `window_test`, `editor_test`, `screen_test`, `display_width_test`, `text_metrics_test`, `keymap_manager_test`, `highlighter_test`, `dispatcher_test`, `config_*_test`, `indent_test`, `file_watcher_test`, `clipboard_test`, `browser_test`, `command_line_test`, `keyword_chars_test`, `ex_command_registry_test`, `command_invocation_test`, `undo_file_test`, `spell_checker_test`, `quickfix_test`, `filetype_test`, `sixel_test`
- Lang: `lang_test` (syntax highlighting & filetype detection for all 23 languages)
- Integration: `app_scenario_test`, `app_motion_test`, `app_text_object_test`, `app_register_test`, `app_dot_repeat_test`, `app_completion_test`, `app_unicode_behavior_test`, `app_command_test`, `app_ex_command_test`, `render_snapshot_test`, `on_save_hook_test`, `follow_test`, `git_blame_test`, `git_grep_test`, `gh_link_test`, `run_command_test`, `stream_test`
- Helper: `test_helper.rb` (fresh_editor, Minitest)

### Docs (docs/)

`spec.md` (feature spec), `command.md`, `binding.md`, `config.md`, `tutorial.md`, `vim_diff.md`, `plugin.md`, `todo.md`, `done.md`

## Debugging (Lumitrace)

lumitrace is a tool that records runtime values of each Ruby expression.
When a test fails, read `lumitrace help` first, then use it.
Basic: `lumitrace -j exec rake test`
This also provides coverage information for the test run.

When fixing bugs, do NOT assume the first fix attempt is correct. After applying a fix, re-read the relevant code paths to verify the fix addresses the actual root cause, not a symptom. If the user says 'it hasn't changed' or equivalent, start fresh analysis from the failing behavior.

## misc

The user communicates in both English and Japanese. Respond in the same language the user uses. When the user gives feedback like 変わってないですよ ('it hasn't changed'), treat it as a bug report requiring re-analysis.