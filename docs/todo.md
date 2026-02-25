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

## 直近の優先順（推奨）

1. Vim 互換性の精度向上（word/paste/visual/scroll 細部）
2. 永続化（`undofile` / session）
3. option system の残件（P0/P1 の `PARTIAL` を詰める）
4. P2 option（永続化/外部連携系）
5. P3 長期機能（LSP / fuzzy finder）

## 次の1週間の実装順（提案・改訂版）

### Day 1: quickfix を「使える入口」までつなぐ

- `[DONE]` `quickfix` / `location list` バッファで `Enter` ジャンプ
  - qf 行フォーマット -> location 解決
  - cursor 行の項目へ移動（window 復帰含む）
- docs 更新
  - `docs/command.md`, `docs/vim_diff.md`

### Day 2: quickfix 入口コマンド（P0）

- `:grep`, `:lgrep`（外部 grep -> qf/loclist）
- `:cfile`, `:lfile`（ファイルから qf/loclist 読み込み）
- `:make` は `makeprg/errorformat` 最小の雛形まで（全部入りは後回し）
- まずは「動く最小」優先（精度は P2 option 実装と一緒に詰める）

### Day 3: Ex 基盤（range + substitute flags の前段）

- Ex 範囲指定（address / range）の基礎
  - `.` / `%` / 行番号
  - `:1,10d`, `:%y`, `:.,$...`
- `:substitute` の range 連携準備（既存 `:%s` パーサの拡張）

### Day 4: `:substitute` フラグ拡張 + scroll 細部

- `:substitute` フラグ（`i`, `I`, `n`, `e`, `c` の主要）
- `Ctrl-e` / `Ctrl-y` / `Ctrl-d` / `Ctrl-u` の細部調整
  - count, 端での挙動, row_offset/cursor_y の整合
- docs 更新
  - `docs/command.md`, `docs/binding.md`

### Day 5: paste / visual の互換性詰め

- `p`, `P` のカーソル位置ルール調整（charwise / linewise）
- Visual mode の端点/inclusive ルール整理
- Visual block の最小 blockwise paste（`p`）
- テスト追加（操作シナリオ + snapshot）

### Day 6: word motion 精度 + `iskeyword` 連携の詰め

- `w`, `b`, `e` の境界判定を Vim に寄せる
- `iskeyword` との整合（word motion / text object / `*`）
- 日本語/記号混在ケースの回帰テスト追加

### Day 7: 永続化の第一段（undofile 先行）

- `undofile`, `undodir` option 実体化
- 保存時/終了時の undo dump（最小）
- ファイル再オープン時の undo restore（path ベース）
- エラー時の degrade（読めない/壊れた undo file は無視してメッセージ）
- docs 更新
  - `docs/config.md`, `docs/spec.md`, `docs/vim_diff.md`

### 次の週に回す候補（この週の続き）

- session file（`-S [session]` placeholder 実体化）
- `wrap` / `linebreak` / `breakindent` / `showbreak` の整合性
- `wildmenu` / `completeopt` / `pumheight` の UI コンポーネント寄せ
- arglist（複数ファイル通常起動 + `:args/:next/:prev`）

### この順番の理由（依存）

- `quickfix` は既に内部モデルがあるので、入口（`Enter`, `:grep` 系）を先に作ると体験改善が大きい
- Ex range と `:substitute` flags は同じパーサ/Dispatcher 周辺を触るので連続でやる方が安全
- `paste/visual/word motion` は互換性テストをまとめて増やしやすい
- `undofile` は session より独立度が高く、先に基盤化するとその後の作業でも安全

## TODO Vim 互換性の精度向上（精度・挙動の詰め）

- Vim 互換性の精度向上（word motion / paste / visual 挙動）
  - `w`, `b`, `e` の境界判定を Vim に寄せる
  - `p`, `P` のカーソル位置ルールを調整
  - Visual mode の端点/inclusive ルールを整理
  - Visual block の blockwise paste / text object
  - `Ctrl-e` / `Ctrl-y` / `Ctrl-d` / `Ctrl-u` の細部挙動（Vim との差分詰め）

## TODO Vim 差分で実用上効く追加機能（未着手）

### P0: すぐ効く（既存機能の入口/使い勝手を補う）

- quickfix / location list の入口コマンド拡張
  - `:grep`, `:lgrep`（外部 grep -> qf/loclist）
  - `:make`（`makeprg` + `errorformat` の最小連携）
  - `:cfile`, `:lfile`（ファイルから qf/loclist 読み込み）
- Ex 範囲指定（address / range）の基礎
  - `:1,10d`, `:%y`, `:.,$s/.../.../` など
  - まずは行範囲 + 現在行 (`.`) + 全体 (`%`) を優先
- `:substitute` フラグ拡張（Ruby regex 方針のまま）
  - `c`, `i`, `I`, `n`, `e` などの主要フラグ
  - range 指定との組み合わせ

### P1: Vim 運用でよく触る基盤（あると詰まりにくい）

- arglist（複数ファイル通常起動 + 操作）
  - 複数ファイル引数（通常起動）
  - `:args`, `:next`, `:prev`, `:first`, `:last`
  - `alternate buffer (#)` との整合
- `Ctrl-w` window 操作の拡張
  - `Ctrl-w c`（window close）
  - `Ctrl-w o`（only / 他 window を閉じる）
  - `Ctrl-w =`（equalize）
  - resize 系（`+`, `-`, `<`, `>`, `_`, `|` の最小）
- `:set` 構文の拡張
  - `+=`, `-=`, `^=`, `&`, `<`
  - option 名短縮（例: `nu`, `ts`）
  - `:set all` / もう少し見やすい一覧表示
- register 拡張（実用寄り）
  - `"-`（small delete register）
  - delete/yank の register 更新ルールを Vim に寄せる

### P2: 中長期で効くが依存が広い

- tags / tag jump（最小）
  - `Ctrl-]`, `Ctrl-t`, `:tag`, `:tselect`
  - tags file 読み込み + jump stack
- Ex の追加制御コマンド
  - `:global` / `:vglobal`
  - `:normal` / `:normal!`
- folds（最小）
  - `za`, `zc`, `zo`
  - 表示・カーソル移動・検索の整合

## TODO 永続化

- 永続 undo / セッション
  - `undofile` / `undodir` 実体（保存・復元）
  - session file（開いている buffer / cursor 位置 / tab/window レイアウト）
  - `-S [session]` の実体化（現在 placeholder）

## TODO 長期（規模大）

### P3: 長期（人気はあるが規模大）

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

## TODO option system 拡張（残件のみ）

注記:
- 実装済みの `number`, `relativenumber`, `ignorecase`, `smartcase`, `hlsearch`, `tabstop`, `filetype` は除外
- 完了済みの option 実装は `docs/done.md` と `docs/config.md` を参照
- ここには `PARTIAL` / 未着手のみを残す

### P0: 日常編集の体験差が大きい（残件）

- `[PARTIAL]` `wrap`（長い行を折り返す）
- `[PARTIAL]` `linebreak`（単語境界寄りで折り返す）
- `[PARTIAL]` `breakindent`（折り返し行のインデント）
  - 折り返し時の検索ハイライト/Visual/カーソル表示の整合性
  - `showbreak` / `breakindent` との組み合わせ挙動

### P1: 使う人が多い / UI と編集体験を整える（残件）

- `[PARTIAL]` `showbreak`（折り返し行の先頭表示）
- `[PARTIAL]` `signcolumn`（サイン列の表示: `yes` の幅予約のみ）
- `[PARTIAL]` `matchtime`（`showmatch` のメッセージ表示時間に反映）
- `[PARTIAL]` `backspace`（Insert mode での BS 挙動: `start/eol` 最小）
- `[PARTIAL]` `whichwrap`（左右移動が行をまたぐ条件: `h/l` 最小）
- `[PARTIAL]` `virtualedit`（`onemore`, `all` の最小: 左右移動と描画）
- `[PARTIAL]` `iskeyword`（単語境界の定義: word motion / 補完 / 一部 textobj）
- `[PARTIAL]` `completeopt`（補完 UI の挙動: `menu/menuone/noselect` の最小）
- `[PARTIAL]` `pumheight`（補完候補 UI の高さ: メッセージ表示件数に反映）
- `[PARTIAL]` `wildmode`（コマンドライン補完の挙動: `list/full/longest` の最小）
- `[PARTIAL]` `wildmenu`（コマンドライン補完 UI: メッセージ行ベースの簡易表示）
- `[PARTIAL]` `path`（`gf` の最小パス探索）
- `[PARTIAL]` `suffixesadd`（`gf` の拡張子補完）

補足（P1 実装の観点）:
- `PARTIAL` の定義は `docs/config.md` 側で詳細化する
- `signcolumn` は diagnostics/LSP と一緒に拡張する方が効率がよい
- `wildmenu` / `completeopt` / `pumheight` は UI コンポーネント化でまとめて詰める

### P2: 実用性は高いが依存が増えやすい / 実装範囲が広い

- `undofile`（永続 undo の ON/OFF）
- `undodir`（永続 undo の保存先）
- `updatetime`（アイドル更新間隔。診断/自動処理にも関係）
- `swapfile`（swap file の ON/OFF）
- `backup`（バックアップ保存）
- `writebackup`（書き込み時バックアップ）
- `autoread`（外部更新の再読込）
- `[PARTIAL]` `autowrite`（特定コマンド時の自動保存: buffer切替/`:e`/`gf`/`:tabnew` の最小）
- `confirm`（確認ダイアログ相当の確認フロー）
- `grepprg`（外部 grep コマンド）
- `grepformat`（grep 結果のパース形式）
- `makeprg`（外部 build コマンド）
- `errorformat`（quickfix のパース形式）
- `formatoptions`（自動整形/コメント継続の挙動）
- `textwidth`（自動改行幅）
- `spell`（スペルチェック ON/OFF）
- `spelllang`（スペルチェック言語）
- `[PARTIAL]` `termguicolors`（検索/`cursorline`/`colorcolumn` 背景色の最小 truecolor 対応）

## メモ（実装方針）

- Vim 完全互換の CLI を目指すより、よく使うフラグから互換寄りに実装する
- Ruby DSL 前提なので、Vim の `-u NONE` / `-U NONE` は RuVim 向けに意味を再定義してよい
- UI/Unicode/折り返し系は `TextMetrics` と `Screen` の責務を増やしすぎないように分割する
