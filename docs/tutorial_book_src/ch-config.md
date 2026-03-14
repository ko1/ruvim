# 設定ファイル

> "We shape our tools, and thereafter our tools shape us." — Marshall McLuhan

## この章で学ぶこと

- init.rb の場所と書き方
- ftplugin の仕組み
- ConfigDSL
- CLI オプションとの組み合わせ

[設定ファイル](#index:設定/init.rb)は「あなた専用のエディタ」を作るための設計図です。一度 init.rb を書いておけば、どのマシンでも同じ環境を再現できます。キーバインドの追加や[オプション](ch-options.md)の永続化はもちろん、Ruby の力を借りて独自のコマンドを定義することもできます。

> [!TIP]
> より高度なカスタマイズ（独自コマンドの定義など）は [Plugin API](ch-plugin-api.md) の章で詳しく解説しています。

## 設定ファイルの場所

```
$XDG_CONFIG_HOME/ruvim/init.rb
~/.config/ruvim/init.rb          （XDG_CONFIG_HOME 未設定時）
```

ftplugin（ファイルタイプごとの設定）:

```
~/.config/ruvim/ftplugin/<filetype>.rb
```

## init.rb の例

```ruby
# ~/.config/ruvim/init.rb

# オプション設定
set "number"
set "relativenumber"
set "ignorecase"
set "smartcase"
set "scrolloff=5"
set "splitbelow"
set "splitright"

# キーバインド
nmap "H", "cursor.line_start"
nmap "L", "cursor.line_end"

# カスタムコマンド
command "user.show_path", desc: "Show current file path" do |ctx, **|
  ctx.editor.echo(ctx.buffer.path || "[No Name]")
end

nmap "gp", "user.show_path"

# Ex コマンドとして公開
ex_command_call "ShowPath", "user.show_path"
```

## ftplugin の例

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb

setlocal "tabstop=2"
setlocal "expandtab"
setlocal "shiftwidth=2"

# Ruby ファイルでだけ有効なキーバインド
nmap "K", desc: "Show method name" do |ctx, **|
  line = ctx.buffer.line_at(ctx.window.cursor_y)
  if line =~ /def (\w+)/
    ctx.editor.echo("Method: #{$1}")
  end
end
```

> [!NOTE]
> [ftplugin](#index:設定/ftplugin) の `nmap`/`imap` は filetype-local として登録され、その[ファイルタイプ](ch-syntax-languages.md#filetype-検出)のバッファでのみ有効です。

## ConfigDSL メソッド一覧

| メソッド | 説明 |
|---------|------|
| `set "option"` | オプション設定 |
| `setlocal "option"` | ローカルスコープで設定 |
| `setglobal "option"` | グローバルスコープで設定 |
| `nmap seq, cmd_id` | Normal mode キーバインド |
| `imap seq, cmd_id` | Insert mode キーバインド |
| `map_global seq, cmd_id, mode:` | 汎用キーバインド |
| `command id, &block` | 内部コマンド定義 |
| `ex_command name, &block` | Ex コマンド定義 |
| `ex_command_call name, cmd_id` | Ex → 内部コマンドの中継 |

## CLI オプションとの組み合わせ

```bash
ruvim --clean file.txt                 # 設定を読まない
ruvim -u /path/to/custom_init.rb       # 別の設定ファイル
ruvim -u NONE                          # user config を読まない（ftplugin は有効）
ruvim --cmd 'set number' file.txt      # config 読み込み前に実行
ruvim -c 'set number' file.txt         # 起動後に実行
```
