# オプション設定

> "Give me six hours to chop down a tree and I will spend the first four sharpening the axe." — Abraham Lincoln

## この章で学ぶこと

- `:set` の構文
- 主要オプションの解説

道具は自分の手に合うように調整してこそ真価を発揮します。RuVim のオプション設定を使いこなせば、行番号の表示、インデント幅、検索の挙動など、自分の作業スタイルに合ったエディタ環境を構築できます。一度設定すれば init.rb に書いて永続化できるので、繰り返し手動で設定する必要もありません。

## `:set` の構文

```
:set                     現在の設定一覧を表示
:set {name}              boolean オプションを ON
:set no{name}            boolean オプションを OFF
:set inv{name}           boolean オプションを反転
:set {name}?             値を表示
:set {name}={value}      値を設定
:setlocal {name}={value} ローカルスコープで設定
:setglobal {name}={value} グローバルスコープで設定
```

## 表示系オプション（Window-local）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `number` | bool | false | 行番号表示 |
| `relativenumber` | bool | false | 相対行番号（number 併用時は現在行が絶対番号） |
| `wrap` | bool | true | 長い行を画面幅で折り返し |
| `linebreak` | bool | false | wrap 時に空白位置で折り返し |
| `breakindent` | bool | false | wrap 継続行にインデントを反映 |
| `cursorline` | bool | false | 現在行の背景ハイライト |
| `scrolloff` | int | 0 | カーソル上下の余白行数 |
| `sidescrolloff` | int | 0 | カーソル左右の余白桁数 |
| `numberwidth` | int | 4 | 行番号列の最小幅 |
| `colorcolumn` | string | nil | 桁ガイド列（例: "80" や "80,100"） |
| `signcolumn` | string | "auto" | サイン列の表示方針 |
| `list` | bool | false | 不可視文字の可視化 |
| `listchars` | string | "tab:>-,trail:-,nbsp:+" | 不可視文字の表示記号 |
| `showbreak` | string | "" | wrap 継続行の先頭文字列 |

## 編集系オプション（Buffer-local）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `tabstop` | int | 2 | タブの表示幅 |
| `expandtab` | bool | false | Tab をスペースに変換 |
| `shiftwidth` | int | 2 | インデント幅 |
| `softtabstop` | int | 0 | Tab 入力/削除時の編集幅 |
| `autoindent` | bool | true | 改行時にインデントを引き継ぐ |
| `smartindent` | bool | true | 簡易自動インデント |
| `filetype` | string | nil | ファイルタイプ |
| `iskeyword` | string | nil | 単語境界の定義 |
| `spell` | bool | false | スペルチェック |
| `path` | string | nil | gf 用ファイル探索ディレクトリ |
| `suffixesadd` | string | nil | gf 用拡張子補完候補 |
| `onsavehook` | bool | true | 保存時の lang フック |

## 検索系オプション（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `ignorecase` | bool | false | 大文字小文字を無視 |
| `smartcase` | bool | false | 大文字を含むときだけ case-sensitive |
| `hlsearch` | bool | true | 検索ハイライト |
| `incsearch` | bool | false | インクリメンタル検索 |

## ウィンドウ/バッファ管理（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `splitbelow` | bool | false | split を下に |
| `splitright` | bool | false | vsplit を右に |
| `hidden` | bool | false | 未保存バッファの切替を許可 |
| `autowrite` | bool | false | 切替時に自動保存 |
| `clipboard` | string | "" | "unnamed" で `*`、"unnamedplus" で `+` と連携 |

## 入力・補完系（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `timeoutlen` | int | 1000 | キーマップの保留待ち時間(ms) |
| `ttimeoutlen` | int | 50 | ESC シーケンス待ち時間(ms) |
| `backspace` | string | "indent,eol,start" | Backspace が越えてよい境界 |
| `completeopt` | string | "menu,menuone,noselect" | 補完 UI の挙動 |
| `pumheight` | int | 10 | 補完候補の最大表示件数 |
| `wildmode` | string | "full" | コマンドライン補完の挙動 |
| `wildmenu` | bool | false | コマンドライン補完候補の一覧表示 |
| `wildignore` | string | "" | path 補完から除外するパターン |
| `wildignorecase` | bool | false | wildignore を case-insensitive に |
| `showmatch` | bool | false | 閉じ括弧入力時のフィードバック |
| `whichwrap` | string | "" | 左右移動の行またぎ条件 |
| `virtualedit` | string | "" | 実文字のない位置へのカーソル移動 |
| `termguicolors` | bool | false | truecolor 描画 |

## Undo / Grep 系（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `undofile` | bool | true | undo 履歴の永続化 |
| `undodir` | string | nil | undo ファイルの保存先 |
| `syncload` | bool | false | 大ファイルの同期ロード |
| `grepprg` | string | "grep -nH" | 外部 grep コマンド |
| `grepformat` | string | "%f:%l:%m" | grep 出力のパース書式 |

## sixel（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `sixel` | string | "auto" | sixel 出力制御（auto/on/off） |
