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

## 優先順

1. Vim 互換性の精度向上（word/paste/visual/scroll 細部）
2. 永続化（session）
3. option system の残件（`PARTIAL` を詰める）
4. P2 option（永続化/外部連携系）
5. P3 長期機能（LSP / fuzzy finder）

---

## Vim 互換性の精度向上

### word motion / paste / visual の挙動

- `w`, `b`, `e` の境界判定を Vim に寄せる
- `iskeyword` との整合（word motion / text object / `*`）
- 日本語/記号混在ケースの回帰テスト追加
- `p`, `P` のカーソル位置ルール調整（charwise / linewise）
- Visual mode の端点/inclusive ルール整理
- Visual block の blockwise paste / text object

### scroll 細部

- `Ctrl-e` / `Ctrl-y` / `Ctrl-d` / `Ctrl-u` の細部挙動
  - count, 端での挙動, row_offset/cursor_y の整合

### Ctrl-w window 操作の残件

- `_`（maximize height）, `|`（maximize width）

---

## quickfix / location list の入口コマンド

- `:grep`, `:lgrep`（外部 grep → qf/loclist）
- `:make`（`makeprg` + `errorformat` の最小連携）
- `:cfile`, `:lfile`（ファイルから qf/loclist 読み込み）

## Ex コマンド拡張

### 範囲指定（address / range）の基礎

- `:1,10d`, `:%y`, `:.,$s/.../.../` など
- まずは行範囲 + 現在行 (`.`) + 全体 (`%`) を優先

### `:set` 構文の拡張

- `+=`, `-=`, `^=`, `&`, `<`
- option 名短縮（例: `nu`, `ts`）
- `:set all` / 見やすい一覧表示

## register 拡張

- `"-`（small delete register）
- delete/yank の register 更新ルールを Vim に寄せる

---

## 永続化

- session file（開いている buffer / cursor 位置 / tab/window レイアウト）
- `-S [session]` の実体化（現在 placeholder）

---

## option system（残件のみ）

注記:
- 実装済み option は `docs/done.md` と `docs/config.md` を参照
- ここには `PARTIAL` / 未着手のみを残す

### P0: 日常編集の体験差が大きい

- `[PARTIAL]` `wrap`（長い行を折り返す）
- `[PARTIAL]` `linebreak`（単語境界寄りで折り返す）
- `[PARTIAL]` `breakindent`（折り返し行のインデント）
  - 折り返し時の検索ハイライト/Visual/カーソル表示の整合性
  - `showbreak` / `breakindent` との組み合わせ挙動

### P1: UI と編集体験を整える

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

補足:
- `signcolumn` は diagnostics/LSP と一緒に拡張する方が効率がよい
- `wildmenu` / `completeopt` / `pumheight` は UI コンポーネント化でまとめて詰める

### P2: 依存が広い / 実装範囲が広い

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
- `[PARTIAL]` `spelllang`（スペルチェック言語: 値は保持するが辞書切り替え未対応）
- `[PARTIAL]` `termguicolors`（検索/`cursorline`/`colorcolumn` 背景色の最小 truecolor 対応）

---

## 中長期機能

### tags / tag jump（最小）

- `Ctrl-]`, `Ctrl-t`, `:tag`, `:tselect`
- tags file 読み込み + jump stack

### folds（最小）

- `za`, `zc`, `zo`
- 表示・カーソル移動・検索の整合

### LSP diagnostics + jump（最小）

- 効果: 高 / コスト: 高
- 依存: job/process 管理, diagnostics モデル, 画面表示（sign/underline/一覧）

### fuzzy finder（file/buffer/grep）

- 効果: 高 / コスト: 高
- 依存: picker UI, grep/検索基盤, preview（任意）

---

## 非同期ファイルロードの残件

- `-c` で渡したコマンドが非同期ロード中の不完全なバッファに対して実行される
  - startup actions をロード完了後に遅延実行するコールバックを `finish_async_file_load!` に追加する
  - ユーザーの対話操作は制限しない（`-c` 起動コマンドのみ遅延）
- 非同期ロードの性能改善（現状は同期パスの約3倍遅い）
  - `Array<String>` ベースのバッファ構造が根本原因（split + GC 負荷）
  - rope / lazy split 等のデータ構造変更が必要（大きな変更）

---

## メモ（実装方針）

- Vim 完全互換の CLI を目指すより、よく使うフラグから互換寄りに実装する
- Ruby DSL 前提なので、Vim の `-u NONE` / `-U NONE` は RuVim 向けに意味を再定義してよい
- UI/Unicode/折り返し系は `TextMetrics` と `Screen` の責務を増やしすぎないように分割する
