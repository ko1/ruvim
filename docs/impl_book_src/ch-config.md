# 設定システム — Ruby DSL による拡張

> 「型があるから型破りができる」 — 中村勘三郎

RuVim の設定ファイルは、そのまま Ruby コードだ。`~/.config/ruvim/init.rb` に以下のように書ける。

```ruby
# キーバインド
nmap "K", "buffer.scroll_up"
nmap " ff", "meta.fuzzy_find"

# インラインコマンド定義
nmap "gf" do |ctx|
  word = ctx.buffer.current_word
  ctx.editor.open_path(word)
end

# Ex コマンド
ex_command "hello", desc: "Say hello" do |ctx, **|
  ctx.editor.echo("Hello, World!")
end

# オプション
set "number"
set "tabstop=4"
```

## ConfigDSL — BasicObject による安全なサンドボックス

```ruby
class ConfigDSL < BasicObject
  def initialize(command_registry:, ex_registry:, keymaps:, command_host:, ...)
    @command_registry = command_registry
    @ex_registry = ex_registry
    @keymaps = keymaps
    @command_host = command_host
  end

  def nmap(seq, command_id = nil, desc: "user keymap", **opts, &block)
    command_id = inline_map_command_id(:normal, seq, desc:, &block) if block
    if @filetype
      @keymaps.bind_filetype(@filetype, seq, command_id.to_s, mode: :normal, **opts)
    else
      @keymaps.bind(:normal, seq, command_id.to_s, **opts)
    end
  end
end
```

[`ConfigDSL`](#index:ConfigDSL) は `BasicObject` を継承している。`BasicObject` は `Object` のメソッド（`puts`, `require` など）を持たないため、DSL のメソッド名が衝突しにくい。ユーザーが定義した `nmap` や `set` だけが使える、クリーンな名前空間を提供する。

> [!NOTE]
> `BasicObject` を継承する理由は、`Object` のメソッド（`puts`, `require`, `class` など 60 以上）と DSL メソッドの名前衝突を防ぐためだ。ただし、DSL ブロック内で `require` や `puts` を使いたい場合は `::Kernel.require` のように修飾が必要になる。

## ファイルタイプ別設定

ファイルタイプ固有の設定は `~/.config/ruvim/ftplugin/<filetype>.rb` に置く。

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb
set "tabstop=2"
set "shiftwidth=2"
nmap "<C-r>", "meta.run_current"
```

ファイルタイプ名はバリデーションされ、パストラバーサルを防いでいる。

> [!CAUTION]
> ftplugin のファイル名にはファイルタイプ名がそのまま使われる。`../` を含むファイルタイプ名を受け付けるとパストラバーサル攻撃が可能になるため、英数字とアンダースコアのみを許可するバリデーションが入っている。

## ブロック付きキーマップ

`nmap` にブロックを渡すと、自動的にコマンド ID が生成されて登録される。

```ruby
def inline_map_command_id(mode, seq, desc:, &block)
  @inline_map_command_seq += 1
  id = "user.keymap.#{mode}.#{sanitize_seq_label(seq)}.#{@inline_map_command_seq}"
  command(id, desc:, &block)
  id
end
```

生成される ID は `user.keymap.normal.gf.1` のような形式で、一意性が保証される。
