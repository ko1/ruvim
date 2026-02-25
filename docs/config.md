# RuVim 設定（Config / Options）

この文書は、RuVim の設定方法と `:set` 系オプションの現状仕様をまとめたものです。

## 設定ファイル

- XDG 設定ファイル:
  - `$XDG_CONFIG_HOME/ruvim/init.rb`
  - `~/.config/ruvim/init.rb`（`XDG_CONFIG_HOME` 未設定時）
- filetype ごとの設定（ftplugin）:
  - `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
  - `~/.config/ruvim/ftplugin/<filetype>.rb`

設定ファイルは Ruby DSL（`ConfigDSL`）として評価されます。

### 起動オプションでの切替（CLI）

- `--clean`
  - user config と ftplugin を読まない
- `-u path/to/init.rb`
  - 指定ファイルを user config として読む
- `-u NONE`
  - user config を読まない（ftplugin は有効）
- `--cmd {cmd}`
  - user config 読み込み前に Ex コマンドを実行（複数回指定可）

## `:set` 系コマンド（現状）

- `:set`
  - 現在値の一覧（簡易）を表示
- `:set {name}`
  - boolean option を `on`
- `:set no{name}`
  - boolean option を `off`
- `:set inv{name}`
  - boolean option を反転
- `:set {name}?`
  - 値を表示
- `:set {name}={value}`
  - 値を設定
- `:setlocal ...`
  - local scope（現状は option 定義に応じて `window` or `buffer`）
- `:setglobal ...`
  - global scope

## ConfigDSL からの設定

`init.rb` / `ftplugin/*.rb` では DSL メソッドも使えます。

```ruby
set "number"
set "relativenumber"
set "ignorecase"
set "smartcase"
set "hlsearch"
setlocal "tabstop=4"
setglobal "tabstop=8"
```

## オプション一覧（現状実装）

実装の定義元は `lib/ruvim/editor.rb` の `RuVim::Editor::OPTION_DEFS` です。

補足:
- 実装済み option はこの文書の個別解説より多いです（`cursorline`, `scrolloff`, `incsearch`, `expandtab`,
  `autoindent`, `smartindent`, `splitbelow`, `splitright`, `list`, `listchars`, `colorcolumn`, `numberwidth`,
  `whichwrap`, `backspace`, `wildignore`, `wildignorecase`, `wildmode`, `wildmenu`, `completeopt`, `pumheight`,
  `wrap`, `linebreak`, `breakindent`, `showbreak`, `signcolumn`, `matchtime`（いずれも最小/部分実装を含む）など）
- 個別解説は利用頻度の高いものから順次追記しています

### `number`

- 型: `bool`
- 既定スコープ: `window-local`
- デフォルト: `false`
- 用途:
  - 行番号表示の ON/OFF
  - 描画（`Screen`）に反映
- 例:
  - `:set number`
  - `:set nonumber`
  - `:setlocal number`

### `relativenumber`

- 型: `bool`
- 既定スコープ: `window-local`
- デフォルト: `false`
- 用途:
  - 相対行番号表示
  - `number` 併用時は current line を絶対行番号、それ以外を相対行番号で表示
- 例:
  - `:set relativenumber`
  - `:set norelativenumber`
  - `:setlocal relativenumber`

### `tabstop`

- 型: `int`
- 既定スコープ: `buffer-local`
- デフォルト: `2`
- 用途:
  - タブ展開幅（表示幅計算・描画）
- 例:
  - `:set tabstop=4`
  - `:set tabstop?`
  - `:setlocal tabstop=2`
  - `:setglobal tabstop=8`

### `filetype`

- 型: `string`
- 既定スコープ: `buffer-local`
- デフォルト: `nil`
- 用途:
  - filetype-local keymap 解決
  - ftplugin ロード対象の決定
- 備考:
  - 通常は path から自動検出される
  - 手動で `:set filetype=ruby` も可能
  - 現状、手動変更時に ftplugin を再適用する仕組みはない

### `ignorecase`

- 型: `bool`
- 既定スコープ: `global`
- デフォルト: `false`
- 用途:
  - 検索・置換で大文字小文字を無視
- 例:
  - `:set ignorecase`
  - `:set noignorecase`

### `smartcase`

- 型: `bool`
- 既定スコープ: `global`
- デフォルト: `false`
- 用途:
  - `ignorecase` 有効時、検索パターンに大文字を含む場合は case-sensitive にする
- 例:
  - `:set smartcase`
  - `:set nosmartcase`

### `hlsearch`

- 型: `bool`
- 既定スコープ: `global`
- デフォルト: `true`
- 用途:
  - 検索マッチの画面ハイライト ON/OFF
- 例:
  - `:set hlsearch`
  - `:set nohlsearch`

## 制限（現状）

- Vim の option 全部は未実装（ごく一部のみ）
- `:set all` / `:setlocal` 一覧の整形表示は未実装（簡易表示）
- `+=`, `-=`, `^=` などの複合代入は未対応
- `&`（デフォルトへ戻す）や `<`（global 値に戻す）などは未対応
- option の短縮名（例: `nu`）は未対応
