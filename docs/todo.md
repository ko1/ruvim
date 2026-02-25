# RuVim TODO

## 方針

- まずは「日常的に触れる Vim ライク編集体験」を優先
- その次に「拡張性（`:command`, `:ruby`, keymap layering）」を強化
- 最後に「性能・互換性・品質」を詰める
- このファイルの項目を上から順に進める
  - ## TODO ... とあるものは、未着手
  - ## DOING ... とあるものは、着手中
  - ## DONE ... とあるものは、終了
- 各タスクに着手し、完了させるときに、次のようにすること
  - 着手するときは、このファイルを編集すること（DOING にする）
  - `docs/spec.md` を実装に追従させる
  - `docs/tutorial.md` に新機能の操作方法を追記
  - `docs/binding.md` にキーバインディングをまとめる
  - `docs/command.md` にコマンド一覧をまとめる
  - `docs/config.md` に設定一覧をまとめる
  - `docs/vim_diff.md` に vim との違いをまとる

## TODO Vimっぽさの向上

- [DONE] `Undo/Redo`
  - `u`, `Ctrl-r`
  - Buffer 操作を履歴イベントとして記録
  - 挿入連続入力の undo 粒度をどう切るか決める

- [DONE] 検索
  - `/` と `?` で command-line 入力
  - `n`, `N` で次/前へ
  - 検索結果のカーソル移動

- [DONE] 複数キー解釈の拡張（operator-pending）
  - `d` + motion（`dw`, `dj`, `d$` など）
  - 将来 `y`, `c` にも拡張できる形にする

## TODO 設計の核

- [DONE] `:command`（ユーザー定義 Ex コマンド）
  - global command 定義
  - 将来の buffer-local command のための設計余地
  - `:commands` 表示への統合

- [DONE] `:ruby` / `:rb`
  - Ex 行で Ruby 実行
  - `ctx` を入口にした API
  - 例外ハンドリングとエラーメッセージ表示

- [DONE] バッファ管理コマンド
  - `:ls` / `:buffers`
  - `:bnext`, `:bprev`, `:buffer`
  - alternate buffer (`#`) の基礎

- [DONE] キーマップのレイヤー化
  - mode-local（現状）
  - global
  - buffer-local
  - filetype-local（将来）

## TODO UI / 画面描画

- [DONE] リサイズ対応
  - `SIGWINCH`
  - 画面サイズ再計算

- [DONE] 差分描画
  - 毎キー全再描画から段階的に改善

- [DONE] ステータスライン強化
  - filetype
  - modified/read-only 表示
  - mode ごとの表示改善

- [DONE] コマンドライン改善
  - 履歴
  - 補完
  - エラー表示の見やすさ

- [DONE] カーソル位置の強調表示（任意）
  - 端末カーソル依存で見づらい場合の代替表示

## TODO Vimっぽさの向上

- [DONE] 移動コマンド追加
  - `gg`, `G`
  - `w`, `b`, `e`
  - `$`, `^`

- [DONE] 挿入系コマンド追加
  - `a`, `A`, `I`
  - `o`, `O`

- [DONE] 編集系コマンド追加
  - `p`, `P`
  - `r`
  - `yy`, `yw`（register 実装後）

## TODO Vim っぽさの向上

- [DONE] Visual mode
  - characterwise
  - linewise
  - 選択範囲に対する delete/yank

- [DONE] レジスタ
  - unnamed register
  - delete/yank の保存
  - 将来 named register へ拡張

## TODO ファイル / 互換性 / 品質

- [DONE] 保存/読込の挙動強化
  - `:e!`
  - `:w!` の意味整理（現状はメタ情報のみ）
  - 未保存変更時の確認フロー

- [DONE] 文字幅対応
  - UTF-8
  - 全角文字
  - タブ幅と表示桁の分離

- [DONE] テスト追加
  - `Buffer`（挿入/削除/改行/保存）
  - `Dispatcher` / Ex parser
  - `KeymapManager`

- [DONE] 設定ファイル
  - XDG config (`~/.config/ruvim/init.rb`) 相当
  - 起動時ロード
  - 安全な拡張ポイント設計

## TODO 次フェーズ案（アイディア）

- [DONE] 複数 window / split UI
  - `:split`, `:vsplit`
  - window 間移動
  - 各 window の cursor/scroll を独立管理

- [DONE] Tabpage
  - tab レイアウト管理
  - `:tabnew`, `:tabnext`, `:tabprev`

- [DONE] Unicode 対応の精度向上
  - grapheme cluster 単位のカーソル移動
  - East Asian Width / ambiguous width 設定
  - combining mark / emoji 表示の整合

- Vim 互換性の精度向上（word motion / paste / visual 挙動）
  - `w`, `b`, `e` の境界判定を Vim に寄せる
  - `p`, `P` のカーソル位置ルールを調整
  - Visual mode の端点/inclusive ルールを整理

- [DONE] 設定ファイルの場所を XDG のルールに変更
  - 過去の互換性は気にしなくてよい

- [DONE] text object 実装
  - `iw`, `aw`
  - `i"`, `a"`, `i)`, `a)` など
  - operator / Visual と共通利用できる設計

- [DONE] `c` operator と change 系コマンド
  - `cw`, `cc`, `c$`
  - delete + insert への自然な接続

- [DONE] 検索の強化
  - 正規表現対応
  - ハイライト表示
  - `*`, `#`, `g*`, `g#`
  - `:%s/foo/bar/g` など substitute

- [DONE] named register / clipboard 対応
  - `"a` など named register
  - append register（`"A`）
  - system clipboard 連携（`"+`, `"*` / 環境依存で切替）

- [DONE] マーク / ジャンプリスト
  - local mark / global mark
  - jump list (`''`, `````, `<C-o>`, `<C-i>`)

- [DONE] マクロ
  - `q{reg}` 記録
  - `@{reg}` 再生
  - 繰り返しと再帰防止

- [DONE] option system
  - global / buffer-local / window-local option ストア
  - `:set`, `:setlocal`, `:setglobal`
  - 既存 UI 設定（number 等）へ接続

- [DONE] ファイルタイプ検出と ftplugin
  - filetype 検出の精度向上
  - filetype-local keymap / command / option 読み込み
  - `$XDG_CONFIG_HOME/ruvim/ftplugin/*.rb` / `~/.config/ruvim/ftplugin/*.rb`

- [DONE] シンタックスハイライト（最小）
  - 正規表現ベースの token coloring
  - filetype ごとの highlighter
  - 描画差分との整合

- [DONE] 補完基盤
  - command-line 補完の文脈化（Ex 引数単位）
  - Insert mode 補完（buffer words）
  - 将来 LSP 補完に繋げる API

## これからやること

- 永続 undo / セッション
  - undo history 保存
  - session file（開いている buffer / cursor 位置）

- パフォーマンス改善
  - [DONE] 表示幅ベースの水平スクロール
    - `Window#ensure_visible` を screen column ベース化済み（`TextMetrics` 利用）
    - 全角文字を含む行の横スクロールを `test/window_test.rb` で確認済み
  - [DONE] 大きいファイルでの redraw 最適化
    - 既存の差分描画に加え、`Screen` で syntax highlight 結果をキャッシュ
    - 同一 `filetype + line text` の再描画時に regex スキャンを再利用
  - [DONE] rope/piece-table などのバッファ構造検討
    - `docs/spec.md` に現状（行配列）/ `piece table` / `rope` の比較メモを追加
    - `永続 undo` 実装タイミングで `piece table` 再評価、という方針で整理

- [DONE] テスト基盤の拡張
  - terminal/input/screen の結合テスト（`test/input_screen_integration_test.rb`）
  - golden snapshot テスト（描画, `test/render_snapshot_test.rb` + fixture）
  - 操作シナリオテスト（キーストローク列, `test/app_scenario_test.rb`）

- CI / 開発体験
  - GitHub Actions 等で test 実行
  - lint / format 方針
  - 変更時の docs 整合チェック

- 内部座標の整理（byte index / character index / grapheme index）
  - 現状どの API がどの単位かを明文化
  - Buffer / Window / Screen / Search で単位混在を減らす

- エンコーディング方針の明文化と実装整理
  - 読み込み時の decode 戦略（UTF-8 / default_external / scrub）の仕様化
  - 保存時の encoding 方針（常に UTF-8 か、元 encoding を保持するか）
  - 不正バイト列を含むファイルの表示・編集・保存の挙動テスト

- 表示幅ベース描画の共通化
  - 文字列の切り詰め/パディングを ANSI 付きでも安全に扱う helper を整理
  - tabstop を表示幅計算 helper 全体で一貫利用
  - number / syntax highlight / search highlight 併用時の幅ズレ確認

- 日本語/全角を含む操作の整合性確認
  - `w`, `b`, `e` / search / visual selection / replace の挙動を多バイト文字で検証
  - `p`, `P` 後のカーソル位置を全角文字行で確認

- 描画回帰テストの追加（Unicode / wide char）
  - 日本語を含む行でのスクロール・カーソル移動の snapshot テスト
  - 行番号表示（`number`）ON/OFF での描画テスト
  - ANSI 色付き行（cursor/search/highlight）での折り返し回避テスト

- [DONE] `.`（直前変更の repeat）
  - 効果: 高（Vim の編集テンポに直結）
  - コスト: 中
  - 依存:
    - 変更コマンドの「再実行可能表現」を記録する仕組み
    - operator / insert / replace の repeat 粒度整理
  - メモ:
    - 初版として `x`, `dd`, `d{motion}`, `p/P`, `r<char>` を対応（DONE）

- [DONE] `f/F/t/T`, `;`, `,`（行内文字移動）
  - 効果: 高（移動効率が一気に上がる）
  - コスト: 低?中
  - 依存:
    - 直前検索文字/方向/種別（f/t）状態の保持
    - `;`, `,` repeat の状態機械
  - メモ:
    - 日本語/全角文字での挙動確認が必要

- [DONE] `%`（対応括弧ジャンプ）
  - 効果: 高（コード編集の基本動作）
  - コスト: 中
  - 依存:
    - 括弧走査ロジック
    - jump list 連携（できれば）
  - メモ:
    - まず `()[]{}` のみでよい

- [DONE] `relativenumber`（option）
  - 効果: 中?高（移動 count と相性が良い）
  - コスト: 低
  - 依存:
    - option system (`number` 済み)
    - `Screen#line_number_prefix` 拡張

- [DONE] 検索 option（`ignorecase`, `smartcase`, `hlsearch`）
  - 効果: 高（検索 UX 改善）
  - コスト: 中
  - 依存:
    - option system（済）
    - 検索/ハイライト処理の option 参照
  - メモ:
    - `incsearch` は別タスクに分けるのがよい

- [DONE] register 強化（`"_`, `0`, `1-9`）
  - 効果: 中?高（削除/yank の運用が楽になる）
  - コスト: 中
  - 依存:
    - register 更新ルールの整理
    - delete/yank/put の経路統一
  - メモ:
    - black hole (`"_`) と yank register `0` から着手が効果的

- [DONE] text object 拡充（`ip/ap`, `i]`, `a}`, ``i` ``, など）
  - 効果: 高（operator/visual の表現力向上）
  - コスト: 中
  - 依存:
    - 既存 text object 基盤（済）
  - メモ:
    - quote/bracket 系は優先度高め

### P2: モダン実用性（人気だが土台が必要）

- quickfix / location list
  - 効果: 高（検索/LSP 診断の受け皿）
  - コスト: 中〜高
  - 依存:
    - list モデル
    - UI 表示/移動コマンド
    - `:grep` / diagnostics 連携（将来）

- Visual block（`Ctrl-v`）
  - 効果: 中〜高（Vim ユーザーの期待値が高い）
  - コスト: 高
  - 依存:
    - visual selection モデル拡張（矩形）
    - 全角/タブを含む列計算の精度

- `.` repeat の精度向上（operator + text object + macro 連携）
  - 効果: 高
  - コスト: 高
  - 依存:
    - `.` 初版の導入
    - 変更表現モデルの整理

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

## TODO 追加候補（コマンドラインオプション / Vim 風）

### P0: まず欲しい（起動フロー・検証でよく使う）

- [DONE] `+{cmd}` / `-c {cmd}`（起動時 Ex コマンド実行）
  - 例: `ruvim +10 file`, `ruvim -c 'set number' file`
  - 効果: 高
  - コスト: 中
  - 依存:
    - 起動時に Ex 実行できるフック
    - 引数パーサ

- [DONE] `-R`（readonly で開く）
  - 効果: 中〜高
  - コスト: 低
  - 依存:
    - buffer/window/editor の readonly 既存機構（基礎あり）

- [DONE] `-u {vimrc}` 相当（設定ファイルパス指定）
  - 効果: 高（再現・テストに便利）
  - コスト: 中
  - 依存:
    - `ConfigLoader` の path 指定 API（ほぼある）
  - メモ:
    - `-u NONE` 的な「設定無効化」も一緒に入れると便利（DONE）

- [DONE] `--clean`（ユーザー設定なしで起動）
  - 効果: 高（バグ再現・検証に便利）
  - コスト: 低
  - 依存:
    - 起動時 config/ftplugin ロードの抑制フラグ

- [DONE] `-n`（swap/永続系を使わない、将来互換の先行予約）
  - 効果: 低〜中（今は意味が薄いが Vim 互換の定番）
  - コスト: 低
  - 依存:
    - 将来の swap/undo/session 実装
  - メモ:
    - 現時点では no-op + ヘルプ表示でもよい（DONE）

### P1: window / tab 起動レイアウト

- [DONE] `-o[N]`（水平 split で複数ファイルを開く）
  - 効果: 中〜高
  - コスト: 中
  - 依存:
    - 既存 split UI（済）
    - 複数ファイル引数処理

- [DONE] `-O[N]`（垂直 split で複数ファイルを開く）
  - 効果: 中〜高
  - コスト: 中
  - 依存:
    - 既存 vsplit UI（済）

- [DONE] `-p[N]`（tabpage で複数ファイルを開く）
  - 効果: 中〜高
  - コスト: 中
  - 依存:
    - 既存 tabpage（済）

### P1: 操作モード / 制約系（Vim ユーザーが期待しやすい）

- [DONE] `-M`（modifiable off 相当 / 書き換え抑止）
  - 効果: 中
  - コスト: 中
  - 依存:
    - option/buffer 属性との接続整理

- [DONE] `-Z`（restricted mode 相当の簡易版）
  - 効果: 低〜中
  - コスト: 中
  - 依存:
    - `:ruby`, `:!`（将来）, config 実行などの制限設計
  - メモ:
    - RuVim では「Ruby eval/設定を無効化する safe mode」の方が実用的かも（DONE: `:ruby` と config/ftplugin を抑止）

### P2: デバッグ・開発向け（あると嬉しい）

- [DONE] `-V[N]` / `--verbose`（起動/設定/コマンドログ）
  - 効果: 中（開発・バグ報告で有用）
  - コスト: 中
  - 依存:
    - logger / trace 出力先

- [DONE] `--startuptime {file}`（起動時間計測ログ）
  - 効果: 低〜中（最適化時に有用）
  - コスト: 低〜中
  - 依存:
    - 起動フェーズの計測フック

- [DONE] `--cmd {cmd}`（通常 config 読み込み前に実行）
  - 効果: 中
  - コスト: 中
  - 依存:
    - 起動順制御（pre-config / post-config）

### P2: 互換性として名前だけ先に確保してもよいもの

- [DONE] `-d`（diff mode）
  - 効果: 中（将来 diff UI で効く）
  - コスト: 高
  - 依存:
    - diff 表示/アルゴリズム/UI
  - メモ:
    - 現状は CLI 互換 placeholder として受理し、起動時に未実装メッセージを表示

- [DONE] `-q {errorfile}`（quickfix 読み込み起動）
  - 効果: 中
  - コスト: 高
  - 依存:
    - quickfix 実装
  - メモ:
    - 現状は CLI 互換 placeholder として受理し、起動時に未実装メッセージを表示

- [DONE] `-S [session]`（session 読み込み）
  - 効果: 中
  - コスト: 高
  - 依存:
    - session 実装
  - メモ:
    - 現状は CLI 互換 placeholder として受理し、起動時に未実装メッセージを表示

### 仕様メモ（RuVim 方針）

- Vim 完全互換の CLI を目指すより、よく使うフラグから互換寄りに実装する
- [DONE] `--help` / `--version` / `--clean` / `-u` / `-c` / `+cmd` を先に揃えると実用性が高い
- Ruby DSL 前提なので、Vim の `-u NONE` / `-U NONE` は RuVim 向けに意味を再定義してよい
