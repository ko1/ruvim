# RuVim DONE

完了した項目をカテゴリ別に整理した一覧です。

注記:
- 実装の詳細・制約は `docs/spec.md`, `docs/vim_diff.md`, `docs/command.md` を参照
- このファイルは「完了したことの棚卸し」、`docs/todo.md` は「未完了の作業」に分離して管理する

## コア編集 / Vim ライク基本機能

- `Undo/Redo`（`u`, `Ctrl-r`）
- 検索（`/`, `?`, `n`, `N`）
- 複数キー解釈の拡張（operator-pending 基礎）
- 移動コマンド追加（`gg`, `G`, `w`, `b`, `e`, `$`, `^`）
- 挿入系コマンド追加（`a`, `A`, `I`, `o`, `O`）
- 編集系コマンド追加（`p`, `P`, `r`, `yy`, `yw`）
- Visual mode（charwise / linewise）
- レジスタ基礎（unnamed + delete/yank 保存）
- text object 実装（`iw`, `aw`, quote/bracket 系など）
- `c` operator と change 系コマンド（`cw`, `cc`, `c$` など）
- 検索の強化（regex, highlight, `* # g* g#`, 最小 substitute）
- named register / clipboard 対応（`"a`, `"A`, `"+`, `"*`）
- マーク / ジャンプリスト
- マクロ（`q{reg}`, `@{reg}`）
- `.`（直前変更の repeat）初版
- `f/F/t/T`, `;`, `,`（行内文字移動）
- `%`（対応括弧ジャンプ）
- register 強化（`"_`, `0`, `1-9`）
- text object 拡充（`ip/ap`, `i]`, `a}`, ``i` ``, など）
- quickfix / location list（最小）
- Visual block（`Ctrl-v`、最小）
- `.` repeat の精度向上（operator + text object + macro 連携）

## コマンド / 設計 / 拡張基盤

- `:command`（ユーザー定義 Ex コマンド）
- `:ruby` / `:rb`
- バッファ管理コマンド（`:ls`, `:buffers`, `:bnext`, `:bprev`, `:buffer`, `#`）
- キーマップのレイヤー化（mode/global/buffer/filetype）
- option system（global / buffer-local / window-local, `:set` 系）
- ファイルタイプ検出と ftplugin
- 設定ファイル（XDG config, 起動時ロード, 拡張ポイント）
- 設定ファイルの場所を XDG ルールに変更
- `docs/plugin.md`（拡張 / plugin 的な書き方）
- block-based keymap DSL（`nmap/imap/map_global ... do |ctx, ...| end`）
- plugin 向け `ctx.editor / ctx.buffer / ctx.window` API リファレンス（未確定 API 注記つき）

## UI / 画面描画 / 端末挙動

- リサイズ対応（`SIGWINCH` + 即時再描画）
- 差分描画
- ステータスライン強化
- コマンドライン改善（履歴 / 補完 / エラー表示）
- カーソル位置の強調表示
- 複数 window / split UI（`:split`, `:vsplit`, window 間移動）
- Tabpage（`:tabnew`, `:tabnext`, `:tabprev`）
- ヘルプ / コマンド一覧の read-only 仮想バッファ表示
- intro screen（Vim 風 welcome buffer）
- エラー表示の改善（最下段・強調表示）
- PageUp / PageDown 対応
- `:q` の window/tab/app クローズ挙動を Vim 寄りに調整

## Unicode / 日本語 / 表示幅 / 座標系

- 文字幅対応（UTF-8 / 全角 / タブ幅と表示桁分離）
- Unicode 対応の精度向上（grapheme cluster, EAW, emoji/combining 整合）
- 内部座標の整理（char index / grapheme / screen column）
- エンコーディング方針の明文化と実装整理（UTF-8 decode/save）
- 表示幅ベース描画の共通化（`TextMetrics` 中心）
- 日本語/全角を含む操作の整合性確認（`w/b/e`, Visual yank, `p/P`）
- 描画回帰テストの追加（Unicode / wide char）

## 品質 / テスト / CI / パフォーマンス

- テスト追加（Buffer / Dispatcher / Ex parser / KeymapManager）
- パフォーマンス改善（表示幅ベース水平スクロール / syntax cache）
- rope/piece-table などのバッファ構造検討メモ（`docs/spec.md`）
- テスト基盤の拡張（結合テスト / snapshot / シナリオ）
- CI / 開発体験（GitHub Actions, `rake docs:check`, `rake ci`）
- シンタックスハイライト（最小）
- 補完基盤（Ex 補完 / Insert mode 補完）

## CLI オプション（Vim 風・実装済み / placeholder 含む）

### 実用寄り（実装済み）

- `--help`, `--version`
- `--clean`
- `+{cmd}` / `-c {cmd}`
- `-u {vimrc}` 相当（`-u path`, `-u NONE`）
- `-R`
- `-n`（現状 no-op, 互換予約）
- `-o[N]`, `-O[N]`, `-p[N]`
- `-M`
- `-Z`
- `-V[N]` / `--verbose`
- `--startuptime {file}`
- `--cmd {cmd}`

### 互換 placeholder として受理（名前確保）

- `-d`（diff mode）
- `-q {errorfile}`（quickfix 読み込み起動）
- `-S [session]`（session 読み込み）

## ドキュメント整理 / 仕様整備

- `docs/spec.md`, `docs/tutorial.md`, `docs/binding.md`, `docs/command.md`, `docs/config.md`, `docs/vim_diff.md` の継続更新
- `docs/config.md`（設定一覧）
- `docs/vim_diff.md`（Vim との差分）
- `docs/todo.md` の P0-P2 項目の消化

