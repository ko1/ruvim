# RuVim

Ruby で実装した Vim ライクなターミナルエディタです。

- raw mode + ANSI 描画
- Normal / Insert / Command-line / Visual
- Ex コマンド（`:w`, `:q`, `:e`, `:help`, `:set` など）
- split / vsplit / tab（最小実装）
- Ruby DSL 設定（XDG）

## 起動

起動:

```bash
ruvim
```

ファイルを開いて起動:

```bash
ruvim path/to/file.txt
```

主な CLI オプション:

- `ruvim --help`
  - ヘルプを表示して終了
- `ruvim --version`
  - バージョンを表示して終了
- `ruvim --clean`
  - ユーザー設定 / ftplugin を読まずに起動
- `ruvim -R file.txt`
  - readonly モードで開く（`w` を拒否）
- `ruvim -M file.txt`
  - modifiable off 相当（編集操作を拒否、readonly も有効化）
- `ruvim -Z file.txt`
  - restricted mode（config/ftplugin 無効、`:ruby` 無効）
- `ruvim -u /tmp/init.rb`
  - 設定ファイルを指定
- `ruvim -u NONE`
  - ユーザー設定を読まない（ftplugin は有効）
- `ruvim --cmd 'set number' file.txt`
  - user config 読み込み前に Ex コマンドを実行
- `ruvim -c 'set number' file.txt`
  - 起動後に Ex コマンドを実行
- `ruvim +10 file.txt`
  - 起動後に 10 行目へ移動
- `ruvim + file.txt`
  - 起動後に最終行へ移動
- `ruvim -o a.rb b.rb`
  - 複数ファイルを水平 split で開く（最小実装）
- `ruvim -O a.rb b.rb`
  - 複数ファイルを垂直 split で開く（最小実装）
- `ruvim -p a.rb b.rb`
  - 複数ファイルを tab で開く（最小実装）
- `ruvim -d file.txt`
  - diff mode placeholder（現状は未実装メッセージのみ）
- `ruvim -q errors.log`
  - quickfix startup placeholder（現状は未実装メッセージのみ）
- `ruvim -S Session.vim`
  - session startup placeholder（現状は未実装メッセージのみ）

開発環境で gem 未インストールのまま試す場合:

```bash
ruby -Ilib exe/ruvim
```

## 主な操作（抜粋）

- 移動: `h j k l`, `w b e`, `0 ^ $`, `gg`, `G`
- 挿入: `i`, `a`, `A`, `I`, `o`, `O`
- 編集: `x`, `dd`, `d{motion}`, `c{motion}`, `yy`, `yw`, `p`, `P`, `r<char>`
- 検索: `/`, `?`, `n`, `N`, `*`, `#`, `g*`, `g#`
- Visual: `v`, `V`, `y`, `d`
- Undo/Redo: `u`, `Ctrl-r`
- Ex: `:w`, `:q`, `:e`, `:help`, `:commands`, `:set`

詳しくは `docs/tutorial.md` を参照してください。

## 設定

設定ファイルは Ruby DSL です。

- `$XDG_CONFIG_HOME/ruvim/init.rb`
- `~/.config/ruvim/init.rb`

filetype ごとの設定:

- `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
- `~/.config/ruvim/ftplugin/<filetype>.rb`

`--clean` で user config / ftplugin を無効化できます。

詳しくは `docs/config.md` を参照してください。

## ドキュメント

- `docs/tutorial.md` - 使い方
- `docs/spec.md` - 実装仕様 / 設計
- `docs/command.md` - コマンド一覧
- `docs/binding.md` - キーバインド
- `docs/config.md` - 設定
- `docs/plugin.md` - 拡張 / plugin 的な書き方（現状）
- `docs/vim_diff.md` - Vim との差分
- `docs/todo.md` - TODO / 次フェーズ案

## 開発

テスト実行:

```bash
rake test
```

CI 相当（test + docs 整合チェック）:

```bash
rake ci
```

lint / format 方針（現状）:

- `rubocop` / 自動 formatter は未導入
- 変更時は `rake test` と必要に応じて `ruby -c` で構文確認
- docs を触ったときは `rake docs:check`（`rake ci` に含まれる）
```

## 注意（現状）

- Vim 完全互換ではありません
- 正規表現は Vim regex ではなく Ruby `Regexp` を使います
- 文字幅 / Unicode は改善済みですが、完全互換ではありません
- 複数ファイル引数や一部 Vim CLI オプションは未実装です
