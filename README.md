<p align="center">
  <img src="docs/logo.svg" alt="RuVim" width="480">
</p>

# RuVim

Ruby で実装した Vim ライクなターミナルエディタです。

Vim の操作感をベースに、Ruby ならではの、もしくは ko1 が欲しい拡張性と独自機能を加えています。

## Vim にない独自機能

- **Rich View (`gr`)** — TSV / CSV / Markdown をテーブル整形して閲覧。CJK 幅を考慮したカラム揃え
- **`g/` 検索フィルタ** — 検索にマッチする行だけを集めたバッファを作成。再帰的に絞り込み可能。ログ解析に便利
- **ストリーム統合** — データを非同期にバッファへ流し込む仕組み。4種類のソースに対応
  - **大きなファイル** — 巨大ファイルを少しずつ非同期ロード。読み込み中も操作可能
  - **Stdin パイプ** — `ls -la | ruvim` のようにパイプの出力をそのままバッファで閲覧・編集
  - **`:run` コマンド** — `:run make` で外部プロセスを実行し、出力をリアルタイムにバッファへ表示。PTY 対応
  - **Follow mode (`-f` / `:follow`)** — 外部ファイルを監視して変更を自動反映。`tail -f` 相当。inotify 対応
- **Git / GitHub 統合** — `:git blame`, `:git status`, `:git diff`, `:git log`, `:git branch`, `:git commit`, `:git grep` をエディタ内で実行。`:gh link` で GitHub URL をクリップボードにコピー、`:gh browse` でブラウザで開く
- Ruby related:
  - **Ruby DSL 設定** — `~/.config/ruvim/init.rb` に Ruby で `nmap`, `set`, `command` を記述。Vim script 不要
  - **Ruby 正規表現** — 検索・置換は Ruby `Regexp`。Ruby ユーザーにそのまま馴染む
  - **`:ruby` eval** — 実行中に任意の Ruby コードを評価。`ctx.editor` / `ctx.buffer` API でエディタを操作

## 概要

- raw mode + ANSI 描画
- Normal / Insert / Command-line / Visual（char / line / block）
- Ex コマンド（`:w`, `:q`, `:e`, `:help`, `:set`, `:git`, `:gh` など）
- split / vsplit / tab
- quickfix / location list（`:vimgrep`, `:grep`, `:copen` など）
- シェル連携（`:!cmd`, `:r !cmd`, `:w !cmd`）
- Ruby DSL 設定（XDG）

## ドキュメント

Web で読みやすい形式のドキュメントは https://ko1.github.io/ruvim/ で公開しています。

### はじめに

| ドキュメント | 内容 |
|---|---|
| [tutorial.md](docs/tutorial.md) | 基本操作のチュートリアル。起動・移動・編集・保存の流れをひと通り学べます |
| [tutorial_book.md](docs/tutorial_book.md) | 完全ガイド（チュートリアルブック）。基本から応用・カスタマイズまで網羅した一冊。[HTML 版](docs/tutorial_book.html)もあります |

### リファレンス

| ドキュメント | 内容 |
|---|---|
| [command.md](docs/command.md) | コマンド一覧。Normal / Insert / Ex の全コマンドを分類ごとに掲載 |
| [binding.md](docs/binding.md) | キーバインディング一覧。モード別・レイヤー別に全バインドを掲載 |
| [config.md](docs/config.md) | 設定リファレンス。`init.rb` の書き方と `:set` オプションの全項目 |
| [plugin.md](docs/plugin.md) | 拡張の書き方。正式な plugin API はまだありませんが、`init.rb` でできることをまとめています |

### Vim ユーザー向け

| ドキュメント | 内容 |
|---|---|
| [vim_diff.md](docs/vim_diff.md) | Vim との違い。RuVim 独自の機能や挙動の差分をまとめています |

### 開発者向け

| ドキュメント | 内容 |
|---|---|
| [spec.md](docs/spec.md) | 仕様書。アーキテクチャ・設計方針・各サブシステムの詳細 |
| [implementation.md](docs/implementation.md) | 実装解説記事。「Ruby でテキストエディタを作る」をテーマに内部設計を解説 |
| [todo.md](docs/todo.md) | TODO リスト。今後の開発予定と検討中の機能 |
| [done.md](docs/done.md) | 完了項目。実装済みの機能をカテゴリ別に記録 |

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
- `ruvim -f log.txt`
  - follow mode（`tail -f` 相当）で起動
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

- 移動: `h j k l`, `w b e`, `0 ^ $`, `gg`, `G`, `f/F/t/T`, `%`
- 挿入: `i`, `a`, `A`, `I`, `o`, `O`
- 編集: `x`, `dd`, `d{motion}`, `c{motion}`, `yy`, `yw`, `p`, `P`, `r<char>`
- text object: `iw`, `aw`, `i"`, `a"`, `i)`, `a)`, `ip`, `ap` など
- 検索: `/`, `?`, `n`, `N`, `*`, `#`, `g*`, `g#`
- Visual: `v`, `V`, `Ctrl-v`, `y`, `d`
- Undo/Redo: `u`, `Ctrl-r`
- マクロ: `q{reg}`, `@{reg}`, `@@`
- Ex: `:w`, `:q`, `:e`, `:help`, `:set`, `:git`, `:gh`
- Git: `Ctrl-g` で `:git` プリセット入力。blame / status / diff / log / branch / commit / grep
- シェル: `:!cmd`, `:r !cmd`（出力を挿入）, `:w !cmd`（バッファをパイプ）

詳しくは [docs/tutorial.md](docs/tutorial.md) を参照してください。

## 設定

設定ファイルは Ruby DSL です。

- `$XDG_CONFIG_HOME/ruvim/init.rb`
- `~/.config/ruvim/init.rb`

filetype ごとの設定:

- `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
- `~/.config/ruvim/ftplugin/<filetype>.rb`

`--clean` で user config / ftplugin を無効化できます。

詳しくは [docs/config.md](docs/config.md) を参照してください。

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