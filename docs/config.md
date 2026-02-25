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
- `DONE` / `PARTIAL` / `定義のみ` は、RuVim 内での実装の反映度を示します（Vim 完全互換度ではありません）
- `PARTIAL` は「主要な場面では効くが、Vim の細部互換までは未実装」の意味です

### Window-local options

- `number` (`bool`, default `false`) [`DONE`]
  - 行番号表示を有効化します。
  - `Screen` の行番号ガター描画に反映されます。

- `relativenumber` (`bool`, default `false`) [`DONE`]
  - 相対行番号を表示します。
  - `number` 併用時は current line を絶対行番号で表示します。

- `wrap` (`bool`, default `false`) [`PARTIAL`]
  - 長い行を画面幅で折り返して表示します。
  - 最小実装として描画ベースで折り返します。Vim のスクロール/カーソル互換は未完成です。

- `linebreak` (`bool`, default `false`) [`PARTIAL`]
  - `wrap` 時に空白位置を優先して折り返します。
  - 現状は簡易な空白ベース判定です。

- `breakindent` (`bool`, default `false`) [`PARTIAL`]
  - `wrap` の継続行に元行のインデントを反映します。
  - 現状は先頭空白の簡易再利用です。

- `cursorline` (`bool`, default `false`) [`DONE`]
  - 現在行の背景ハイライトを有効化します。
  - 検索/選択/カーソル反転より優先度は低く描画されます。

- `scrolloff` (`int`, default `0`) [`DONE`]
  - 縦スクロール時にカーソル上下の余白行数を維持します。
  - `Window#ensure_visible` に反映されます。

- `sidescrolloff` (`int`, default `0`) [`DONE`]
  - 横スクロール時にカーソル左右の余白桁数を維持します。
  - 表示幅ベースで計算されます（全角/タブを考慮）。

- `numberwidth` (`int`, default `4`) [`DONE`]
  - 行番号列の最小幅を指定します。
  - `number` / `relativenumber` のガター幅計算に反映されます。

- `colorcolumn` (`string`, default `nil`) [`DONE`]
  - 桁ガイド列を背景色で表示します。
  - 現状は `80` や `80,100` のような数値列指定のみ対応です。

- `signcolumn` (`string`, default `"auto"`) [`PARTIAL`]
  - サイン列の表示方針を指定します。
  - 現状は `yes` / `yes:N` の幅予約に対応する最小実装です（サイン自体の描画は未実装）。

- `list` (`bool`, default `false`) [`PARTIAL`]
  - 不可視文字を可視化します。
  - 現状は `listchars` と組み合わせた描画の最小対応です。

- `listchars` (`string`, default `"tab:>-,trail:-,nbsp:+"`) [`PARTIAL`]
  - 不可視文字の表示記号を指定します。
  - 現状は `tab`, `trail`, `nbsp` のみ使用します。

- `showbreak` (`string`, default `">"`) [`PARTIAL`]
  - `wrap` 継続行の先頭に表示する文字列です。
  - 現状は描画にのみ反映されます。

### Global options

- `showmatch` (`bool`, default `false`) [`PARTIAL`]
  - 閉じ括弧入力時に対応括弧のフィードバックを出します。
  - 現状は Vim の一時ジャンプ/点滅ではなく、`match` メッセージ表示です。

- `matchtime` (`int`, default `5`) [`PARTIAL`]
  - `showmatch` の一時メッセージ表示時間（0.1秒単位）です。
  - 現状は `match` メッセージの自動消去時間に反映されます。

- `whichwrap` (`string`, default `""`) [`PARTIAL`]
  - 左右移動が行をまたぐ条件を指定します。
  - 現状は `h` / `l`、左右矢印（`left` / `right`、`<` / `>`）の最小対応です。

- `virtualedit` (`string`, default `""`) [`PARTIAL`]
  - 実文字のない位置へのカーソル移動可否を指定します。
  - 現状は `onemore` と `all` の最小対応（主に左右移動と描画）です。

- `ignorecase` (`bool`, default `false`) [`DONE`]
  - 検索/置換の大文字小文字を無視します。
  - `smartcase` と組み合わせて挙動が変わります。

- `smartcase` (`bool`, default `false`) [`DONE`]
  - `ignorecase` 有効時に、パターンに大文字を含む場合だけ case-sensitive にします。

- `hlsearch` (`bool`, default `true`) [`DONE`]
  - 直前検索パターンのマッチを画面上でハイライトします。

- `incsearch` (`bool`, default `false`) [`PARTIAL`]
  - `/` `?` の入力中に逐次検索プレビューを行います。
  - 現状はカーソル移動中心の最小実装で、Esc で元位置に戻ります。

- `splitbelow` (`bool`, default `false`) [`DONE`]
  - `:split` 時に現在 window の下側へ分割を挿入します。

- `splitright` (`bool`, default `false`) [`DONE`]
  - `:vsplit` 時に現在 window の右側へ分割を挿入します。

- `hidden` (`bool`, default `false`) [`PARTIAL`]
  - 未保存バッファを残したまま別バッファへ移動できるようにします。
  - 現状は `:e`, `:buffer`, `:bnext`, `:bprev`, `:tabnew`, `gf` の主要経路で参照します。

- `clipboard` (`string`, default `""`) [`PARTIAL`]
  - unnamed register を `*` / `+` に連携する方針を指定します。
  - 現状は `unnamed`, `unnamedplus` の基本連携のみ対応です。

- `timeoutlen` (`int`, default `1000`) [`DONE`]
  - キーマップの保留入力待ち時間（ms）です。
  - 曖昧なキーマップ解決のタイムアウトに使います。

- `ttimeoutlen` (`int`, default `50`) [`DONE`]
  - 端末の ESC シーケンス待ち時間（ms）です。
  - 矢印キー等の読み取りタイムアウトに使います。

- `backspace` (`string`, default `"indent,eol,start"`) [`PARTIAL`]
  - Insert mode の Backspace が越えてよい境界を指定します。
  - 現状は `start`, `eol`, `indent`, `2` の最小判定です（Vim 完全互換ではありません）。

- `completeopt` (`string`, default `"menu,menuone,noselect"`) [`PARTIAL`]
  - Insert mode 補完 UI/選択挙動を指定します。
  - 現状は `menu`, `menuone`, `noselect`, `noinsert` をメッセージ行ベースの簡易 UI に反映します。

- `pumheight` (`int`, default `10`) [`PARTIAL`]
  - 補完候補 UI の最大表示件数です。
  - 現状はメッセージ行ベースの補完候補表示件数に使います。

- `wildmode` (`string`, default `"full"`) [`PARTIAL`]
  - コマンドライン補完の Tab 挙動を指定します。
  - 現状は `longest`, `list`, `full` の最小対応です（`list:full` 形式も可）。

- `wildignore` (`string`, default `""`) [`DONE`]
  - コマンドライン path 補完から除外するパターンを指定します。
  - `File.fnmatch?` ベースで判定します。

- `wildignorecase` (`bool`, default `false`) [`DONE`]
  - `wildignore` のパターンマッチを大文字小文字無視にします。

- `wildmenu` (`bool`, default `false`) [`PARTIAL`]
  - コマンドライン補完候補の一覧表示 UI を有効化します。
  - 現状はメッセージ行への簡易表示です（Vim の下部メニュー UI ではない）。

### Buffer-local options

- `path` (`string`, default `nil`) [`PARTIAL`]
  - `gf` などのファイル探索ディレクトリを指定します（`,` 区切り）。
  - 現状は `gf` の最小探索に利用します。
  - `lib/**` のような再帰探索（簡易）に対応します。

- `suffixesadd` (`string`, default `nil`) [`PARTIAL`]
  - `gf` などで補完する拡張子候補を指定します（`,` 区切り）。
  - 現状は `gf` の最小探索に利用します。

- `textwidth` (`int`, default `0`) [`定義のみ`]
  - 自動改行幅の指定です。
  - 現状は値を保持できるだけで、自動整形には未接続です。

- `formatoptions` (`string`, default `nil`) [`定義のみ`]
  - 自動整形/コメント継続の挙動を指定します。
  - 現状は値を保持できるだけで、編集処理には未接続です。

- `expandtab` (`bool`, default `false`) [`DONE`]
  - Insert mode の Tab 入力を空白に変換します。
  - `softtabstop` / `tabstop` と組み合わせて空白数を決めます。

- `shiftwidth` (`int`, default `2`) [`PARTIAL`]
  - インデント幅の基準です。
  - 現状は `smartindent` の追加インデント幅で使用します。

- `softtabstop` (`int`, default `0`) [`PARTIAL`]
  - Tab 入力/削除時の編集幅を指定します。
  - 現状は Insert mode の Tab 入力と、`expandtab` 時の空白 Backspace（最小）で使用します。

- `autoindent` (`bool`, default `false`) [`DONE`]
  - 改行時に前行の先頭インデントを引き継ぎます。
  - Insert mode `Enter`、`o`/`O` に反映されます。

- `smartindent` (`bool`, default `false`) [`PARTIAL`]
  - 簡易な自動インデントを行います。
  - 現状は前行が `{` `[` `(` で終わる場合に `shiftwidth` 分の空白を追加します。

- `iskeyword` (`string`, default `nil`) [`PARTIAL`]
  - 単語境界の定義を指定します。
  - 現状は `w/b/e`、一部 text object、Insert 補完の単語抽出に反映します。

- `tabstop` (`int`, default `2`) [`DONE`]
  - タブの表示幅です。
  - 表示幅計算、描画、一部編集処理に使います。

- `filetype` (`string`, default `nil`) [`DONE`]
  - filetype を示します。
  - ftplugin 読み込み対象、filetype-local keymap、簡易 syntax highlight の判定に使います。
  - 手動で変更した場合の ftplugin 再適用は現状未対応です。

## 制限（現状）

- Vim の option 全部は未実装（ごく一部のみ）
- `:set all` / `:setlocal` 一覧の整形表示は未実装（簡易表示）
- `+=`, `-=`, `^=` などの複合代入は未対応
- `&`（デフォルトへ戻す）や `<`（global 値に戻す）などは未対応
- option の短縮名（例: `nu`）は未対応
