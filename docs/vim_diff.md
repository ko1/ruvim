# RuVim と Vim の違い（現状）

この文書は、現時点の RuVim 実装と本家 Vim の違いをまとめたものです。

## 位置づけ

- RuVim は「Vim ライクな Ruby 製ターミナルエディタ」
- 現状は Vim 完全互換ではない
- Vim の操作感を優先して、一部を簡略化している

## 大きな違い（全体）

- Vim script 互換はない
  - 代わりに `:ruby` / `:rb`
- プラグイン互換はない
- split UI は簡易実装（等分割タイル）
  - `:split`, `:vsplit` はある
  - Vim の nested window tree / 高度な window 操作は未実装
- tabpage は最小実装
  - `:tabnew`, `:tabnext`, `:tabprev` はある
  - Vim の高度な tab 操作/コマンド群は未実装
- register は `unnamed` / `named` / `"_` / `0` / `1-9` / `"+` / `"*` の基礎を実装
- option system は基礎のみ（`:set`, `:setlocal`, `:setglobal`, `number`, `relativenumber`, `ignorecase`, `smartcase`, `hlsearch`, `tabstop`, `filetype`）
- filetype 検出 / ftplugin は基礎のみ（拡張子中心の簡易判定）
- Ex コマンドは一部のみ

## コマンドライン / Ex の違い

- `:w`, `:q`, `:wq`, `:e`, `:buffer`, `:bnext`, `:bprev`, `:ls` などはあるが一部のみ
- `:command` はあるが、現状は「Ex 文字列エイリアス展開」に近い簡易実装
- `:ruby` はあるが、Vim の `:ruby` 機能互換ではなく RuVim 独自の Ruby eval 入口
- `:w!` は現状 `:w` とほぼ同じ（権限昇格や readonly 強制保存の完全な意味は未実装）

## モード / 編集操作の違い

- Normal / Insert / Command-line / Visual（charwise, linewise）は実装済み
- Visual mode は最小実装
  - `y`, `d` 中心
  - Vim の細かい選択挙動や text object は一部未実装
- operator-pending は `d`, `y`, `c` の一部を実装
  - text object は `iw/aw`, `ip/ap`, `i"/a"`, ``i`/a` ``, `i)/a)`, `i]/a]`, `i}/a}` を実装（簡易）
  - Vim の text object 群全体は未実装
- word motion（`w`, `b`, `e`）は簡易定義
  - Vim の厳密な単語境界とは一致しない場合がある
- undo 粒度は簡略化
  - Insert mode は「入ってから出るまで」を 1 undo 単位
- `.` repeat は初版のみ
  - 現状は `x`, `dd`, `d{motion}`, `p/P`, `r<char>` を対象
  - insert/change の完全互換は未実装

## レジスタ / yank / paste の違い

- unnamed register（`"`）と named register（`"a`, `"A` append）を実装
- black hole（`"_`）、yank `0`、numbered delete `1-9`（簡易）を実装
- `"+`, `"*` は環境依存の system clipboard と連携（`pbcopy/pbpaste`, `wl-copy/wl-paste`, `xclip`, `xsel` のいずれか）
- small delete register `-` など Vim の全 register 種別は未実装
- paste の挙動は基本的な `charwise` / `linewise` 対応まで
- Vim の細かいカーソル位置ルールとは差がある可能性がある

## 画面描画 / 端末挙動の違い

- ANSI + raw mode の自前描画
- 行キャッシュによる簡易差分描画（Vim の描画最適化とは別実装）
- `SIGWINCH + self-pipe + IO.select` でリサイズ追従
- 文字幅対応は近似実装
  - タブ展開あり
  - 一部全角/emoji 幅2対応
  - 左右移動は grapheme cluster を考慮
  - East Asian Width / grapheme cluster 完全互換ではない

## スクリプト / 設定の違い

- XDG 設定ファイル（`$XDG_CONFIG_HOME/ruvim/init.rb` または `~/.config/ruvim/init.rb`）を Ruby DSL（`ConfigDSL`）で読む
- Vim script 互換設定ファイルではない
- CLI の `-u {path|NONE}` / `--clean` は一部実装済み（Vim 互換の全オプションは未実装）
- 現状の DSL 例:
  - `nmap`, `imap`, `map_global`
  - `command`
  - `ex_command`
  - `ex_command_call`

## CLI オプションの違い

- 実装済み（現状）
  - `--help`, `--version`
  - `--clean`
  - `-u {path|NONE}`
  - `-R`, `-M`, `-Z`, `-n`（`-n` は現状 no-op）
  - `-o[N]`, `-O[N]`, `-p[N]`（基礎）
  - `-V[N]`, `--verbose[=N]`（簡易）
  - `--startuptime FILE`（簡易）
  - `-c {cmd}`
  - `+{cmd}`, `+{line}`, `+`
- 未実装（Vim で定番だが RuVim は未対応）
  - `-R`, `-n`
  - `-o`, `-O`, `-p`
  - `-M`, `-Z`
  - `--cmd`, `-S`, `-q`, `-d` など
- 複数ファイル引数は `-o/-O/-p` 時のみ対応（通常起動の arglist 相当は未実装）

## option（設定）の違い

- 現状の実装済み option は少数（`number`, `relativenumber`, `ignorecase`, `smartcase`, `hlsearch`, `tabstop`, `filetype`）
- Vim の option 名短縮（例: `nu`, `ts`）は未対応
- `:set` の高度な構文（`+=`, `-=`, `^=`, `&`, `<` など）は未対応
- `:set all` や詳細な一覧表示は未対応（簡易表示のみ）

### Vim にあるが未実装の代表例（RuVim 現状）

- 表示系
  - `relativenumber`
  - `cursorline`
  - `wrap`
  - `list`, `listchars`
  - `colorcolumn`
  - `signcolumn`
  - `numberwidth`
  - `scrolloff`, `sidescrolloff`
- インデント/編集系
  - `shiftwidth`
  - `softtabstop`
  - `expandtab`
  - `autoindent`
  - `smartindent`
- 検索系
  - `ignorecase`
  - `smartcase`
  - `hlsearch`
  - `incsearch`
- split / window 系
  - `splitbelow`
  - `splitright`
  - `winfixheight`
  - `winfixwidth`
- ファイル / 永続化系
  - `swapfile`
  - `backup`
  - `writebackup`
  - `undofile`
  - `undodir`
- UI / 端末 / パフォーマンス系
  - `termguicolors`
  - `timeoutlen`
  - `ttimeoutlen`
  - `updatetime`

注記:
- これは網羅一覧ではなく、よく使われるものの代表例です。
- 実装済み option の一覧は `docs/config.md` を参照。

## 未実装（Vim との差分として大きいもの）

- text objects は一部のみ（`iw/aw`, `ip/ap`, `i"/a"`, ``i`/a` ``, `i)/a)`, `i]/a]`, `i}/a}`）
- change operator（`c` 系）は基礎のみ
- macros / replay は基礎のみ（`q{reg}`, `@{reg}`, `@@`）
- marks / jumps は基礎のみ（`m`, `'`, `` ` ``, `''`, `````, `<C-o>`, `<C-i>`）
- search regex 互換（現状は Ruby 正規表現）
- search は Ruby 正規表現ベース（Vim regex と非互換な点あり）
- substitute は最小実装（`:%s/.../.../g` のみ、Vim の置換フラグ群は未対応）
- folds
- syntax highlight は最小実装（regex ベース / `ruby`, `json` のみ）
- 補完は基礎のみ
  - Ex 補完（コマンド名 + 一部引数）
  - Insert mode buffer words 補完（`Ctrl-n` / `Ctrl-p`）
- LSP / diagnostics
- job/channel/terminal 連携

## 互換性の考え方（現状）

- Vim の「概念（buffer / window / mode / operator / Ex）」は寄せる
- 挙動の細部は MVP 実装として簡略化
- 後方互換性より、Ruby で拡張しやすい構造を優先
