# RuVim 拡張 / Plugin メモ（現状）

この文書は、現状の RuVim で「拡張っぽいもの」をどう書くかをまとめたものです。

現時点では正式な plugin manager / plugin API はありません。  
実用上は、`init.rb` / `ftplugin/*.rb` に Ruby DSL で拡張を書きます。

重要:
- ここに書いている DSL / `ctx` API は、現状まだ未確定です
- 将来の整理で互換性なく変更される可能性があります
- 当面は「実験的な拡張 API」として扱ってください

## どこに書くか

- 全体設定 / 拡張:
  - `$XDG_CONFIG_HOME/ruvim/init.rb`
  - `~/.config/ruvim/init.rb`
- filetype ごとの拡張:
  - `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
  - `~/.config/ruvim/ftplugin/<filetype>.rb`

## 何ができるか（DSL）

`ConfigDSL` で主に次を定義できます。

- `nmap(seq, command_id=nil, ..., &block)`
- `imap(seq, command_id=nil, ..., &block)`
- `map_global(seq, command_id=nil, mode: ..., ..., &block)`
- `command(id, &block)`（内部コマンド）
- `ex_command(name, &block)`（Ex コマンド）
- `ex_command_call(name, command_id, ...)`（Ex -> 内部コマンドの中継）
- `set`, `setlocal`, `setglobal`

## DSL メソッドリファレンス（現状）

### `nmap(seq, command_id=nil, desc: ..., **opts, &block)`

- 用途:
  - Normal mode のキーバインドを定義
- 書き方:
  - `command_id` 指定版
  - block 版（推奨: 小さい拡張向け）
- 登録先:
  - `init.rb` では `mode map (:normal)`
  - `ftplugin/*.rb` では `filetype-local normal map`
- 主な引数:
  - `seq`: キー列（例: `"H"`, `"gh"`）
  - `command_id`: 内部コマンドID（例: `"user.hello"`）
  - `desc`: block 版で生成される内部コマンドの説明
  - `opts`: `argv:`, `kwargs:`, `bang:` を指定可能
- 例:

```ruby
nmap "H", "user.hello"
nmap "gH", "user.echo", kwargs: { text: "hi" }

nmap "K", desc: "Show buffer name" do |ctx, **|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

block 版の内部動作:
- 匿名の内部コマンドIDを自動生成して `CommandRegistry` に登録
- その command を keymap に bind

### `imap(seq, command_id=nil, desc: ..., **opts, &block)`

- 用途:
  - Insert mode のキーバインドを定義
- 登録先:
  - `init.rb` では `mode map (:insert)`
  - `ftplugin/*.rb` では `filetype-local insert map`
- 例:

```ruby
imap "jk", "ui.clear_message"
```

注記:
- 現状の Insert mode は通常文字入力が先に処理される経路もあるため、複合キーの期待通り動作には制限が出る場合があります。

### `map_global(seq, command_id=nil, mode: :normal, desc: ..., **opts, &block)`

- 用途:
  - 汎用のキーバインド定義
- 登録先:
  - `mode:` を指定した場合: その mode の map
  - `mode: nil` の場合: `global map`（最下位フォールバック）
- 例:

```ruby
map_global "Q", "app.quit", mode: :normal
map_global ["<C-w>", "x"], "window.focus_next", mode: nil

map_global "?", mode: :normal, desc: "Show file name" do |ctx, **|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

### `command(id, desc: ..., &block)`

- 用途:
  - 内部コマンド（command ID）を登録
- 登録先:
  - `RuVim::CommandRegistry`（source=`:user`）
- 使いどころ:
  - keymap から呼ぶ処理
  - `ex_command_call` の呼び先
- 例:

```ruby
command "user.show_path", desc: "Show current path" do |ctx, **|
  ctx.editor.echo(ctx.buffer.path || "[No Name]")
end
```

### `ex_command(name, desc: ..., aliases: [], nargs: :any, bang: false, &block)`

- 用途:
  - Ex コマンド（`:Name`）を登録
- 登録先:
  - `RuVim::ExCommandRegistry`（source=`:user`）
- 特徴:
  - 同名が既に存在する場合は置き換える（DSL 内で unregister -> register）
  - `aliases`, `nargs`, `bang` を指定できる
- `nargs`:
  - `0`, `1`, `:maybe_one`, `:any`
- 例:

```ruby
ex_command "BufName", desc: "Show current buffer name", nargs: 0 do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

### `ex_command_call(name, command_id, ...)`

- 用途:
  - 既存の内部コマンドを Ex コマンドとして公開する
- 中身:
  - `ex_command` を作り、`CommandRegistry` の `command_id` を呼ぶ薄い中継
- 例:

```ruby
command "user.hello" do |ctx, **|
  ctx.editor.echo("hello")
end

ex_command_call "Hello", "user.hello"
```

### `set(option_expr)`, `setlocal(option_expr)`, `setglobal(option_expr)`

- 用途:
  - option を Ruby DSL から設定
- `option_expr` の形式（現状）:
  - `"number"`（ON）
  - `"nonumber"`（OFF）
  - `"tabstop=4"`（値設定）
- スコープ:
  - `set`: option 定義に応じて自動（global / buffer / window）
  - `setlocal`: local 側（buffer または window）
  - `setglobal`: global 側
- 例:

```ruby
set "number"
set "relativenumber"
setlocal "tabstop=2"
setglobal "tabstop=8"
```

## 最小例

```ruby
# ~/.config/ruvim/init.rb

command "user.hello", desc: "Say hello" do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo("hello x#{count}")
end

nmap "H", "user.hello"
ex_command_call "Hello", "user.hello", desc: "Run hello"
```

これで:

- Normal mode で `H` -> `user.hello`
- `:Hello` -> `user.hello`

## `nmap` はどこに登録される？

`nmap` は「global map」ではなく、`Normal mode 用のマップ` に登録されます。

- `init.rb` での `nmap`
  - セッション全体の Normal map（app-wide）
- `ftplugin/*.rb` での `nmap`
  - `filetype-local` Normal map

### キーマップ解決順（優先順）

1. `filetype-local`
2. `buffer-local`（内部 API はある。DSL は未整備）
3. `mode map`（`nmap`, `imap` など）
4. `global map`（`map_global(..., mode: nil)`）

同じキーが複数定義されている場合、上にあるものが優先されます。

## `command` と `ex_command` の違い

### `command`

内部コマンド（command ID）を定義します。  
主に keymap から呼ぶ対象です。

```ruby
command "user.bufname" do |ctx, **|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

### `ex_command`

`:` で呼べる Ex コマンドを定義します。

```ruby
ex_command "BufName", desc: "Show current buffer name", nargs: 0 do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

### `ex_command_call`（おすすめ）

既存の内部コマンドを Ex から呼びたい時の薄い中継です。

```ruby
ex_command_call "Hello", "user.hello", desc: "Run hello"
```

## filetype ごとの拡張例

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb

setlocal "tabstop=2"

command "ruby.say_ft" do |ctx, **|
  ctx.editor.echo("ruby ftplugin")
end

nmap "K", "ruby.say_ft"
```

この `nmap "K", ...` は Ruby バッファでのみ有効です。

## 実行ブロックの引数

`command` / `ex_command` の block は、基本的に次の形で受けると扱いやすいです。

```ruby
do |ctx, argv:, kwargs:, bang:, count:|
  # ...
end
```

- `ctx.editor`
- `ctx.buffer`
- `ctx.window`
- `argv`（Ex 引数）
- `kwargs`（キーマップや内部呼び出しの named args）
- `bang`（Ex の `!`）
- `count`（Normal mode の count）

## `ctx` API リファレンス（現状）

block に渡される `ctx` は `RuVim::Context` です。

注意:
- この `ctx` API リファレンスは「現時点で使えるもの」の記録です
- 安定 API の宣言ではありません（名前・挙動・公開範囲が変わる可能性があります）

### `ctx.editor`

- 型: `RuVim::Editor`
- 用途:
  - 全体状態へのアクセス
  - message 表示（`echo`, `echo_error`）
  - mode / jump / buffer / window 操作

推奨:
- plugin からはまず `ctx.editor`, `ctx.buffer`, `ctx.window` を使う
- `Editor` の public メソッドは多いが、すべてが高水準 API とは限らない
- 下の「よく使う API」から使い始めるのが安全

#### `ctx.editor` よく使う API（推奨）

状態参照:
- `current_buffer` -> `RuVim::Buffer`
- `current_window` -> `RuVim::Window`
- `mode` / `mode=`
- `running?`
- `message`, `message_error?`

表示 / 通知:
- `echo(text)` : 通常メッセージ表示
- `echo_error(text)` : エラーメッセージ表示（下段・強調）
- `clear_message`

mode 操作:
- `enter_normal_mode`
- `enter_insert_mode`
- `enter_visual(mode)` (`:visual_char`, `:visual_line`, `:visual_block`)
- `enter_command_line_mode(prefix)` (`":"`, `"/"`, `"?"`)
- `cancel_command_line`

window / tab 操作:
- `split_current_window(layout: :horizontal|:vertical)`
- `close_current_window`
- `focus_next_window`, `focus_prev_window`
- `focus_window_direction(:left|:right|:up|:down)`
- `tabnew(path: nil)`, `tabnext(step=1)`, `tabprev(step=1)`

buffer 操作:
- `switch_to_buffer(buffer_id)`
- `open_path(path)`
- `buffers`（`{id => Buffer}`）
- `buffer_ids`
- `alternate_buffer_id`

option:
- `effective_option(name, window: ..., buffer: ...)`
- `set_option(name, value, scope: :auto|:global|:buffer|:window)`
- `get_option(name, window: ..., buffer: ...)`
- `global_options`

register:
- `get_register(name="\"")`
- `set_register(name="\"", text:, type: :charwise|:linewise)`
- `store_operator_register(name="\"", text:, type:, kind: :yank|:delete|:change)`
- `set_active_register(name)`, `active_register_name`, `consume_active_register`

jump / mark:
- `set_mark(name)`
- `mark_location(name, ...)`
- `push_jump_location(location=nil)`
- `jump_to_mark(name, linewise: false)`
- `jump_to_location(loc, linewise: false)`
- `jump_older(linewise: false)`, `jump_newer(linewise: false)`

search / find 状態:
- `last_search`, `set_last_search(pattern:, direction:)`
- `last_find`, `set_last_find(char:, direction:, till:)`

quickfix / location list:
- `set_quickfix_list(items)`, `quickfix_items`, `quickfix_index`, `current_quickfix_item`, `move_quickfix(step)`
- `set_location_list(items, window_id: ...)`, `location_items(window_id)`, `current_location_list_item(window_id)`, `move_location_list(step, window_id: ...)`

終了:
- `request_quit!`

#### `ctx.editor` の高度 / 内部寄り API（使うときは注意）

- `add_empty_buffer`, `add_buffer_from_file`, `add_virtual_buffer`
- `add_window`, `close_window(id)`, `focus_window(id)`
- `show_help_buffer!`, `show_intro_buffer_if_applicable!`, `materialize_intro_buffer!`
- `text_viewport_size`, `window_order`, `windows`, `tabpages`
- `option_def`, `option_default_scope`, `option_snapshot`

これらは便利ですが、UI 内部の都合と結びついているものもあります。

よく使う例:

```ruby
ctx.editor.echo("hello")
ctx.editor.echo_error("something wrong")
```

### `ctx.buffer`

- 型: `RuVim::Buffer`
- 意味:
  - current window に表示中の current buffer
- よく使う例:

```ruby
ctx.buffer.display_name
ctx.buffer.path
ctx.buffer.lines
ctx.buffer.modified?
```

注意:
- `ctx.buffer` を直接編集する場合は `readonly` / `modifiable` 制約に注意
- 低レベル API を呼ぶと undo 粒度の制御が必要になることがあります

#### `ctx.buffer` API リファレンス（用途別）

状態参照:
- `id`
- `path`, `path=`
- `display_name`
- `kind`（`:file`, `:help`, `:intro`, `:quickfix`, `:location_list` など）
- `name`
- `options`（buffer-local option ストレージ）
- `modified?`, `modified=`
- `readonly?`, `readonly=`
- `modifiable?`, `modifiable=`
- `file_buffer?`, `virtual_buffer?`, `intro_buffer?`

行アクセス:
- `lines`（配列そのもの）
- `line_count`
- `line_at(row)`
- `line_length(row)`

編集（低レベル）:
- `insert_char(row, col, char)`
- `insert_text(row, col, text)` -> `[row, col]`
- `insert_newline(row, col)` -> `[row, col]`
- `backspace(row, col)` -> `[row, col]`
- `delete_char(row, col)` -> `true/false`
- `delete_line(row)` -> `deleted_line`
- `delete_span(start_row, start_col, end_row, end_col)` -> `true/false`
- `insert_lines_at(index, new_lines)`
- `replace_all_lines!(new_lines)`

範囲の読み取り:
- `span_text(start_row, start_col, end_row, end_col)` : charwise 範囲文字列
- `line_block_text(start_row, count=1)` : linewise 範囲文字列（末尾 `\n` 付き）

undo / redo:
- `begin_change_group`
- `end_change_group`
- `can_undo?`, `can_redo?`
- `undo!`, `redo!`

ファイル I/O:
- `write_to(path=nil)` : 保存
- `reload_from_file!(path=nil)` : 再読込（undo/redo クリア）

特殊バッファ:
- `configure_special!(kind:, name: nil, readonly: true, modifiable: false)`
- `become_normal_empty_buffer!`

plugin で編集する時の基本パターン（推奨）:

```ruby
buf = ctx.buffer
win = ctx.window

buf.begin_change_group
begin
  buf.insert_text(win.cursor_y, win.cursor_x, "hello")
  win.cursor_x += 5
ensure
  buf.end_change_group
end
```

### `ctx.window`

- 型: `RuVim::Window`
- 意味:
  - current window
- よく使う例:

```ruby
row = ctx.window.cursor_y
col = ctx.window.cursor_x
```

#### `ctx.window` API リファレンス（用途別）

状態（attr）:
- `id`
- `buffer_id`, `buffer_id=`
- `cursor_x`, `cursor_x=`
- `cursor_y`, `cursor_y=`
- `row_offset`, `row_offset=`
- `col_offset`, `col_offset=`
- `options`（window-local option ストレージ）

移動 / 位置補正:
- `clamp_to_buffer(buffer)` : カーソルをバッファ範囲に収める
- `move_left(buffer, count=1)` : grapheme 境界を考慮して左移動
- `move_right(buffer, count=1)` : grapheme 境界を考慮して右移動
- `move_up(buffer, count=1)`
- `move_down(buffer, count=1)`
- `ensure_visible(buffer, height:, width:, tabstop: 2)` : スクロール位置を調整

plugin では通常:
- `cursor_x`, `cursor_y` を更新
- 最後に `clamp_to_buffer(ctx.buffer)` を呼ぶ

例:

```ruby
ctx.window.cursor_y += 10
ctx.window.clamp_to_buffer(ctx.buffer)
```

### `ctx.invocation`

- 型: `RuVim::CommandInvocation` または `nil`
- 意味:
  - 現在実行中のコマンド呼び出し情報
- 主な参照:
  - `ctx.invocation&.count`
  - `ctx.invocation&.bang`

## block で使う引数（`argv`, `kwargs`, `bang`, `count`）

block は `ctx` 以外にも keyword 引数を受け取れます。

```ruby
command "user.demo" do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo("argv=#{argv.inspect} kwargs=#{kwargs.inspect} bang=#{bang} count=#{count}")
end
```

- `argv`
  - Ex コマンド引数（配列）
- `kwargs`
  - keymap / 内部呼び出しの named args（Hash）
- `bang`
  - Ex コマンドが `!` 付きで呼ばれたかどうか
- `count`
  - Normal mode の count（なければ `1`）

## どこまで plugin と呼べる？

現状は「設定ファイルに書く Ruby 拡張」です。

- plugin manager: なし
- plugin の load order 制御: 最小
- 公開 hook API: 最小

ただし、`init.rb` から `require` して自分のファイル群に分割すれば、実用的なローカル plugin 構成は作れます。

```ruby
# ~/.config/ruvim/init.rb
require File.expand_path("plugins/my_tools", __dir__)
```

## 注意点

- 設定ファイルは Ruby として評価されます（任意コード実行）
- 信頼できるコードだけ読み込む前提です
- 将来 API が変わる可能性があります（現状は「育てる段階」）
