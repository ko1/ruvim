# RuVim DONE

完了した項目をカテゴリ別に整理した一覧です。

注記:
- 実装の詳細・制約は `docs/spec.md`, `docs/vim_diff.md`, `docs/command.md` を参照
- このファイルは「完了したことの棚卸し」、`docs/todo.md` は「未完了の作業」に分離して管理する

## コア編集 / Vim ライク基本機能

- `Undo/Redo`（`u`, `Ctrl-r`）
- 永続 undo（`undofile` / `undodir`）— `:set undofile` で有効化、Marshal シリアライズ、SHA256 パス
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
- `:substitute` の `c`（confirm）フラグ — `y/n/a/q/l/Esc` 対応
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
- `=` operator（自動インデント: `==`, `=j`, `=k`, `=G`, `=gg`, Visual `=`。Ruby filetype 対応）

## コマンド / 設計 / 拡張基盤

- `:command`（ユーザー定義 Ex コマンド）
- `:ruby` / `:rb`
- バッファ管理コマンド（`:ls`, `:buffers`, `:bnext`, `:bprev`, `:buffer`, `#`）
- arglist（引数リスト）管理コマンド（`:args`, `:next`, `:prev`, `:first`, `:last`）
- 複数ファイル起動時に全ファイルをバッファとして読み込む（`:ls` に表示）
- キーマップのレイヤー化（mode/global/buffer/filetype）
- option system（global / buffer-local / window-local, `:set` 系）
- ファイルタイプ検出と ftplugin
- 設定ファイル（XDG config, 起動時ロード, 拡張ポイント）
- 設定ファイルの場所を XDG ルールに変更
- `docs/plugin.md`（拡張 / plugin 的な書き方）
- block-based keymap DSL（`nmap/imap/map_global ... do |ctx, ...| end`）
- plugin 向け `ctx.editor / ctx.buffer / ctx.window` API リファレンス（未確定 API 注記つき）
- `:run` コマンド（PTY ストリーミング、`runprg` オプション、バッファごと実行履歴、`%` ファイル名展開、auto-save、Ctrl-C 停止、status line にコマンド表示）
- `path:line:col` 形式でのファイルオープン（CLI 引数 / `:e` / `gf` 対応、存在するファイルのみ解釈）
- `:global` / `:vglobal`（`:g/pattern/command`, `:v/pattern/command`）— マッチ行に Ex コマンドを実行、undo は一括
- Ex コマンド追加: `:print`/`:p`, `:number`/`:nu`, `:move`/`:m`, `:copy`/`:t`, `:join`/`:j`, `:>`/`:<`, `:normal`/`:norm`

## Rich mode / 構造化データ表示

- Rich View フレームワーク（filetype ごとのレンダラー登録）
- TSV/CSV テーブルレンダラー（列幅自動計算、CJK 対応、CSV quoted field パース）
- `:rich [format]` Ex コマンド（トグル）
- `gr` Normal mode キーバインド（トグル）
- filetype 検出に `.tsv` / `.csv` 追加
- Rich View → Rich mode へ変換（仮想バッファ方式から同一バッファ上のモード方式へ）
- Rich mode の横スクロール修正（`$` で行末に移動した際の縦揃えズレを解消）
- Markdown Rich mode（見出し・インライン装飾・テーブル罫線・コードブロック・HR・ブロック引用の ANSI レンダリング）
- `render_rich_view_line_sc` の ANSI エスケープシーケンス対応
- `ensure_visible_rich` の汎用化（`renderer.cursor_display_col` インターフェース）

## UI / 画面描画 / 端末挙動

- リサイズ対応（`SIGWINCH` + 即時再描画）
- 差分描画
- ステータスライン強化
- コマンドライン改善（履歴 / 補完 / エラー表示）
- カーソル位置の強調表示
- 複数 window / split UI（`:split`, `:vsplit`, window 間移動）
- `Ctrl-w` 拡張 — `c`(close), `o`(only), `=`(equalize), `+/-/</>` (resize)
- ネストしたウィンドウ分割（layout tree: vsplit→split でカラム内だけ上下分割）
- Tabpage（`:tabnew`, `:tabnext`, `:tabprev`）
- ヘルプ / コマンド一覧の read-only 仮想バッファ表示
- intro screen（Vim 風 welcome buffer）
- エラー表示の改善（最下段・強調表示）
- PageUp / PageDown 対応
- `:q` の window/tab/app クローズ挙動を Vim 寄りに調整
- hit-enter prompt（複数行メッセージ表示: `:ls`, `:args`, `:set`, `:command`）
- カーソル形状制御（DECSCUSR: Normal では非表示+セル反転、Insert ではバーカーソル）

## Unicode / 日本語 / 表示幅 / 座標系

- 文字幅対応（UTF-8 / 全角 / タブ幅と表示桁分離）
- Unicode 対応の精度向上（grapheme cluster, EAW, emoji/combining 整合）
- 内部座標の整理（char index / grapheme / screen column）
- エンコーディング方針の明文化と実装整理（UTF-8 decode/save）
- 表示幅ベース描画の共通化（`TextMetrics` 中心）
- 日本語/全角を含む操作の整合性確認（`w/b/e`, Visual yank, `p/P`）
- 描画回帰テストの追加（Unicode / wide char）
- `truncate` の表示幅計算を文字数ベースから `DisplayWidth` ベースに修正（全角文字を含むエラーメッセージでターミナルがスクロールするバグを修正）

## 品質 / テスト / CI / パフォーマンス

- テスト追加（Buffer / Dispatcher / Ex parser / KeymapManager）
- パフォーマンス改善（表示幅ベース水平スクロール / syntax cache）
- Insert mode ペースト高速化（stdin に pending input がある間はレンダリングをスキップしバッチ処理）
- rope/piece-table などのバッファ構造検討メモ（`docs/spec.md`）
- テスト基盤の拡張（結合テスト / snapshot / シナリオ）
- CI / 開発体験（GitHub Actions, `rake docs:check`, `rake ci`）
- シンタックスハイライト（最小）
- Markdown シンタックスハイライト（`Lang::Markdown` に抽出、通常モード + Rich mode で共有）
- C 言語モード（`Lang::C`）: シンタックスハイライト・スマートインデント・保存時 gcc チェック
- C++ 言語モード（`Lang::Cpp`）: C の全機能 + C++ 固有キーワード・アクセス指定子インデント・保存時 g++ チェック
- 補完基盤（Ex 補完 / Insert mode 補完）
- git/gh サブコマンドの Tab 補完（`git help -a` / `gh help` から動的取得、セッション内キャッシュ）
- 未知の `:git` / `:gh` サブコマンドのシェルフォールバック実行

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

## Vim 互換性の精度向上

- `:substitute` フラグ拡張（`g`, `i`, `I`, `n`, `e`, `c` 全対応）
- quickfix / location list バッファで `Enter` ジャンプ（qf 行フォーマット → location 解決、cursor 行の項目へ移動）
- スペルチェック（`spell` option）— Pure Ruby 実装、`/usr/share/dict/words` 辞書、赤下線ハイライト、`]s`/`[s` ナビゲーション
- `gitcommit` filetype — コメント行のシンタックスハイライト、`spell` デフォルト有効
- `Lang::Registry` に `buffer_defaults` 機構を追加（filetype ごとのデフォルト option 設定）

## セキュリティ修正

- `:grep` / `:lgrep` のシェルインジェクション対策（argv 配列実行 + `Dir.glob` 展開）
- Rich view レンダリング時のターミナルエスケープインジェクション対策（制御文字の無害化）
- Restricted mode (`-Z`) の網羅強化（`:grep`, `:lgrep`, `:git`, `:gh` を無効化）
- Git branch checkout の安全化（Enter で即時実行せずコマンドラインにプリセットして確認ステップを挟む）
- 非同期ファイルローダーの OOM 対策（`bulk_once` モード廃止、チャンク読み込み）
- 特殊ファイル（FIFO/デバイス/ソケット）の読み込み拒否（`Buffer.ensure_regular_file!` で統一ガード）

## Stream クラス階層化 / StreamMixer リネーム

- `@loading_state` を Stream に統合し、非同期ファイルロード状態を `Stream::FileLoad` で管理
- Stream を基底クラス + 5 サブクラス（`Stdin`, `Run`, `Follow`, `FileLoad`, `Git`）に分離
- fire-on-new パターン: `new` 時点でスレッド/ウォッチャーを即時起動
- `stop_handler` をコンストラクタで渡す（`attr_reader`）
- `StreamHandler` を `StreamMixer` にリネーム（責務を明確化: イベントキューの合流・分配）

## ドキュメント整理 / 仕様整備

- `docs/spec.md`, `docs/tutorial.md`, `docs/binding.md`, `docs/command.md`, `docs/config.md`, `docs/vim_diff.md` の継続更新
- `docs/config.md`（設定一覧）
- `docs/vim_diff.md`（Vim との差分）
- `docs/todo.md` の P0-P2 項目の消化

## リファクタリング

- `global_commands.rb`（3931行）を7つのドメイン別モジュールに分割
  - `commands/motion.rb` — カーソル移動、スクロール、ワード移動、括弧マッチ
  - `commands/edit.rb` — 挿入モード、削除、変更、結合、置換、インデント、undo/redo、テキストオブジェクト
  - `commands/yank_paste.rb` — ヤンク、ペースト、ビジュアルヤンク/削除、レジスタ操作
  - `commands/search.rb` — 検索、置換、global、フィルタ、grep
  - `commands/window.rb` — ウィンドウ分割/フォーカス/クローズ/リサイズ、タブ操作
  - `commands/buffer_file.rb` — バッファ管理、ファイルI/O、終了、マーク、ジャンプ、arglist、リッチビュー
  - `commands/runtime.rb` — ランタイム/メタコマンド（help, set, bindings, ruby, run, shell, define command, normal exec）
  - Git::Handler と同じ mixin パターンを横展開
- `commands/ex.rb` を廃止し、ドメイン別モジュールに再配置
  - `ex_` プレフィックスを全コマンドメソッドから除去（ドメイン名に変更）
  - quickfix/location list/spell/vimgrep → `commands/search.rb`
  - 範囲操作（delete/yank/print/number/move/copy/join/shift） → `commands/edit.rb`
  - read → `commands/buffer_file.rb`
  - help/set/bindings/ruby/run/shell/command/normal → `commands/runtime.rb`（新規）
  - `ex_git`/`ex_gh` → `git_dispatch`/`gh_dispatch`（`git/handler.rb`）
  - `ex_follow_toggle` → `follow_toggle`（`stream_mixer.rb`）
- `editor.rb`（1769行→1176行）から5つのモジュールを抽出
  - `editor/options.rb` — オプションシステム（OPTION_DEFS、get/set/effective、型変換）
  - `editor/registers.rb` — レジスタ管理（名前付き、番号付き、クリップボード連携）
  - `editor/marks_jumps.rb` — マーク、ジャンプリスト、jump_to_location
  - `editor/quickfix.rb` — quickfix / location list 管理
  - `editor/layout_tree.rb` — レイアウトツリーヘルパー（split, remove, rects, leaves）
- `key_handler.rb`（1510行→816行）から3つのモジュールを抽出
  - `key_handler/pending_state.rb` — 保留状態マシン（operator, register, mark, jump, replace, find）
  - `key_handler/macro_dot.rb` — マクロ録音/再生、ドットリピート
  - `key_handler/insert_mode.rb` — 挿入モードキー処理、オートインデント、バックスペース、タブ
- `git/` → `commands/git/`、`gh/link.rb` → `commands/gh.rb` に移動
  - 名前空間を `RuVim::Git` → `RuVim::Commands::Git`、`RuVim::Gh::Link` → `RuVim::Commands::Gh` に変更
  - `gh/` ディレクトリ（単一ファイル）を `commands/gh.rb` にフラット化
  - `repo_root` を `Commands::Git.repo_root` として `module_function` で公開

