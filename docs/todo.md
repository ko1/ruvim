# RuVim TODO

## 方針

- まずは「日常的に触れる Vim ライク編集体験」を優先
- その次に「拡張性（`:command`, `:ruby`, keymap layering）」を強化
- 最後に「性能・互換性・品質」を詰める
- このファイルは未完了項目を管理する
- 完了済みの項目は `docs/done.md` に移動して管理する

作業時のルール:
- 着手時にこのファイルを編集する（`DOING` にするなど）
- 実装に合わせて docs を更新する
  - `docs/spec.md`
  - `docs/tutorial.md`
  - `docs/binding.md`
  - `docs/command.md`
  - `docs/config.md`
  - `docs/vim_diff.md`

## TODO Vim 互換性の精度向上

- Vim 互換性の精度向上（word motion / paste / visual 挙動）
  - `w`, `b`, `e` の境界判定を Vim に寄せる
  - `p`, `P` のカーソル位置ルールを調整
  - Visual mode の端点/inclusive ルールを整理

## TODO 永続化

- 永続 undo / セッション
  - undo history 保存
  - session file（開いている buffer / cursor 位置）

## TODO 長期（規模大）

### P3: 長期（人気はあるが規模大）

- LSP / diagnostics（中長期）
  - language server 起動管理
  - diagnostics 表示
  - definition / references ジャンプ

- LSP diagnostics + jump（最小）
  - 効果: 高
  - コスト: 高
  - 依存:
    - job/process 管理
    - diagnostics モデル
    - 画面表示（sign/underline/一覧）

- fuzzy finder（file/buffer/grep）
  - 効果: 高
  - コスト: 高
  - 依存:
    - picker UI
    - grep/検索基盤
    - preview（任意）

## TODO option system 拡張（Vim でよく使われる未実装設定）

注記:
- 実装済みの `number`, `relativenumber`, `ignorecase`, `smartcase`, `hlsearch`, `tabstop`, `filetype` は除外
- まずは「option 名を受理して挙動に反映する」範囲から進める

### P0: 日常編集の体験差が大きい（優先）

- `[PARTIAL]` `wrap`（長い行を折り返す）
- `[PARTIAL]` `linebreak`（単語境界寄りで折り返す）
- `[PARTIAL]` `breakindent`（折り返し行のインデント）
- `[DONE]` `cursorline`（現在行ハイライト）
- `[DONE]` `scrolloff`（上下マージン行数）
- `[DONE]` `sidescrolloff`（左右マージン桁数）
- `[DONE]` `expandtab`（Tab 入力を空白化）
- `[DONE]` `shiftwidth`（`>`/`<` やインデント幅の基準）
- `[DONE]` `softtabstop`（Tab/BS 時の編集幅）
- `[DONE]` `autoindent`（改行時に前行インデントを引き継ぐ）
- `[DONE]` `smartindent`（言語非依存の簡易インデント）
- `[DONE]` `incsearch`（検索入力中の逐次移動/ハイライト）
- `[DONE]` `splitbelow`（`:split` の配置方向）
- `[DONE]` `splitright`（`:vsplit` の配置方向）
- `[DONE]` `hidden`（未保存バッファ切替の挙動）
- `[DONE]` `clipboard`（unnamed/unnamedplus 連携方針）
- `[DONE]` `timeoutlen`（マップ待ち時間）
- `[DONE]` `ttimeoutlen`（端末キーコード待ち時間）

### P1: 使う人が多い / UI と編集体験を整える

- `[DONE]` `list`（不可視文字の表示、最小）
- `[DONE]` `listchars`（不可視文字の表示内容、`tab/trail/nbsp` 最小）
- `[PARTIAL]` `showbreak`（折り返し行の先頭表示）
- `[DONE]` `colorcolumn`（桁ガイド）
- `[PARTIAL]` `signcolumn`（サイン列の表示: `yes` の幅予約のみ）
- `[DONE]` `numberwidth`（行番号列の幅）
- `[DONE]` `showmatch`（対応括弧を一時強調、最小）
- `[PARTIAL]` `matchtime`（`showmatch` のメッセージ表示時間に反映）
- `[PARTIAL]` `backspace`（Insert mode での BS 挙動: `start/eol` 最小）
- `[PARTIAL]` `whichwrap`（左右移動が行をまたぐ条件: `h/l` 最小）
- `[PARTIAL]` `virtualedit`（`onemore`, `all` の最小: 左右移動と描画）
- `[PARTIAL]` `iskeyword`（単語境界の定義: word motion / 補完 / 一部 textobj）
- `[PARTIAL]` `completeopt`（補完 UI の挙動: `menu/menuone/noselect` の最小）
- `[PARTIAL]` `pumheight`（補完候補 UI の高さ: メッセージ表示件数に反映）
- `[PARTIAL]` `wildmode`（コマンドライン補完の挙動: `list/full/longest` の最小）
- `[DONE]` `wildignore`（補完から除外するパターン）
- `[DONE]` `wildignorecase`（補完の大文字小文字）
- `[PARTIAL]` `wildmenu`（コマンドライン補完 UI: メッセージ行ベースの簡易表示）
- `[PARTIAL]` `path`（`gf` の最小パス探索）
- `[PARTIAL]` `suffixesadd`（`gf` の拡張子補完）

### P2: 実用性は高いが依存が増えやすい / 実装範囲が広い

- `undofile`（永続 undo の ON/OFF）
- `undodir`（永続 undo の保存先）
- `updatetime`（アイドル更新間隔。診断/自動処理にも関係）
- `swapfile`（swap file の ON/OFF）
- `backup`（バックアップ保存）
- `writebackup`（書き込み時バックアップ）
- `autoread`（外部更新の再読込）
- `autowrite`（特定コマンド時の自動保存）
- `confirm`（確認ダイアログ相当の確認フロー）
- `grepprg`（外部 grep コマンド）
- `grepformat`（grep 結果のパース形式）
- `makeprg`（外部 build コマンド）
- `errorformat`（quickfix のパース形式）
- `formatoptions`（自動整形/コメント継続の挙動）
- `textwidth`（自動改行幅）
- `spell`（スペルチェック ON/OFF）
- `spelllang`（スペルチェック言語）
- `termguicolors`（true color 前提の配色）

## メモ（方針）

- Vim 完全互換の CLI を目指すより、よく使うフラグから互換寄りに実装する
- Ruby DSL 前提なので、Vim の `-u NONE` / `-U NONE` は RuVim 向けに意味を再定義してよい
