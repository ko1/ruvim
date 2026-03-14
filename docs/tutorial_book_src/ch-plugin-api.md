# Plugin API

> "Any sufficiently advanced technology is indistinguishable from magic." — Arthur C. Clarke

## この章で学ぶこと

- `command` / `ex_command` の定義
- `nmap` / `imap` の定義
- `ctx` API の使い方
- `:ruby` による対話的な Ruby 実行

RuVim の真骨頂は Ruby で書かれたエディタであるという点です。Plugin API を使えば、エディタの内部状態に直接アクセスして、自分だけのコマンドやキーバインドを定義できます。Vim script を覚える必要はありません — Ruby の知識がそのまま活かせます。

## 内部コマンドの定義

```ruby
command "user.hello", desc: "Say hello" do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo("Hello\! count=#{count}")
end
```

## Ex コマンドの定義

```ruby
ex_command "BufInfo", desc: "Show buffer info", nargs: 0 do |ctx, argv:, kwargs:, bang:, count:|
  buf = ctx.buffer
  ctx.editor.echo("#{buf.display_name} (#{buf.line_count} lines, modified=#{buf.modified?})")
end
```

## Ex → 内部コマンドの中継

```ruby
command "user.hello" do |ctx, **|
  ctx.editor.echo("hello")
end

ex_command_call "Hello", "user.hello", desc: "Run hello"
```

これで `H` キーでも `:Hello` でも同じ処理を呼べます。

## キーバインドのブロック版

```ruby
nmap "K", desc: "Show buffer name" do |ctx, **|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

## `ctx` API

ブロックに渡される `ctx` は `RuVim::Context` です。

主なアクセス先:

```ruby
ctx.editor          # エディタ全体の状態
ctx.buffer          # 現在バッファ（RuVim::Buffer）
ctx.window          # 現在ウィンドウ（RuVim::Window）
```

## `ctx.editor` の主要メソッド

```ruby
# 表示
ctx.editor.echo("message")
ctx.editor.echo_error("error message")

# モード操作
ctx.editor.enter_normal_mode
ctx.editor.enter_insert_mode

# バッファ操作
ctx.editor.open_path("file.txt")
ctx.editor.switch_to_buffer(buffer_id)
ctx.editor.buffers  # {id => Buffer}

# オプション
ctx.editor.effective_option("tabstop")
ctx.editor.set_option("number", true)

# レジスタ
ctx.editor.get_register("a")
ctx.editor.set_register("a", text: "hello", type: :charwise)

# マーク / ジャンプ
ctx.editor.set_mark("a")
ctx.editor.jump_to_mark("a")
```

## `ctx.buffer` の主要メソッド

```ruby
ctx.buffer.path           # ファイルパス
ctx.buffer.display_name   # 表示名
ctx.buffer.lines          # 行配列
ctx.buffer.line_count     # 行数
ctx.buffer.modified?      # 変更あり?
ctx.buffer.line_at(row)   # 指定行の内容

# 編集（undo グループで囲む）
ctx.buffer.begin_change_group
ctx.buffer.insert_text(row, col, "text")
ctx.buffer.end_change_group
```

## `ctx.window` の主要メソッド

```ruby
ctx.window.cursor_x       # カーソル列
ctx.window.cursor_y       # カーソル行
ctx.window.cursor_y += 10
ctx.window.clamp_to_buffer(ctx.buffer)
```

## `:ruby` — 対話的な Ruby 実行

```
:ruby buffer.line_count
:rb [window.cursor_y, window.cursor_x]
:ruby editor.echo("hello from :ruby")
```

`ctx`, `editor`, `buffer`, `window` を参照できます。stdout/stderr の出力は `[Ruby Output]` バッファに表示されます。

実践例 — バッファ内の行をソート:

```
:ruby lines = buffer.lines.sort; lines.each_with_index { |l, i| buffer.replace_line(i, l) }
```

## ファイル分割

```ruby
# ~/.config/ruvim/init.rb
require File.expand_path("plugins/my_tools", __dir__)
```

`~/.config/ruvim/plugins/my_tools.rb` に分離できます。
