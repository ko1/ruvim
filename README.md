# RuVim

Ruby で実装した Vim ライクなターミナルエディタです。

- raw mode + ANSI 描画
- Normal / Insert / Command-line / Visual
- Ex コマンド（`:w`, `:q`, `:e`, `:help`, `:set` など）
- split / vsplit / tab（最小実装）
- Ruby DSL 設定（XDG）

## 起動

開発環境で直接起動:

```bash
ruby -Ilib exe/ruvim
```

ファイルを開いて起動:

```bash
ruby -Ilib exe/ruvim path/to/file.txt
```

主な CLI オプション:

```bash
ruby -Ilib exe/ruvim --help
ruby -Ilib exe/ruvim --version
ruby -Ilib exe/ruvim --clean
ruby -Ilib exe/ruvim -u /tmp/init.rb
ruby -Ilib exe/ruvim -c 'set number' file.txt
ruby -Ilib exe/ruvim +10 file.txt
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
- `docs/vim_diff.md` - Vim との差分
- `docs/todo.md` - TODO / 次フェーズ案

## 開発

テスト実行:

```bash
ruby -Ilib:test -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
```

## 注意（現状）

- Vim 完全互換ではありません
- 正規表現は Vim regex ではなく Ruby `Regexp` を使います
- 文字幅 / Unicode は改善済みですが、完全互換ではありません
- 複数ファイル引数や一部 Vim CLI オプションは未実装です
