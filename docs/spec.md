# RuVim 仕様（現状実装 + 設計方針）

## 目的

RuVim は Ruby で実装する Vim ライクなターミナルエディタです。

- 生ターミナル入力（raw mode）
- モード（Normal / Insert / Command-line）
- `:` Ex 風コマンド
- キーバインドからコマンド実行
- コマンド定義と UI 入力経路の分離

この文書は「現状の実装」と「今後の拡張前提の設計」をまとめた仕様です。

## 基本概念

### 1. Buffer

テキスト本体を保持する単位です。

- 行配列 `lines`
- ファイルパス `path`
- 変更フラグ `modified?`

`Buffer` は表示状態（カーソル位置・スクロール）を持ちません。

### 2. Window

`Buffer` をどの位置で表示するかを持つビューです。

- `buffer_id`
- `cursor_x`, `cursor_y`
- `row_offset`, `col_offset`

同一 buffer を複数 window で表示できる前提の設計です（現状 UI は単一 window）。
同一 buffer を複数 window で表示できる前提の設計です（現状 UI は simple split 対応）。

### 3. Editor

エディタ全体の実行状態です。

- buffers / windows 管理
- window order / split layout（`single` / `horizontal` / `vertical`）
- tabpages 管理（タブごとに window set / current window / layout を保持）
- current window の管理
- mode 管理（`:normal`, `:insert`, `:command_line`）
- ステータスメッセージ
- コマンドライン状態

## コマンドモデル

### 方針

- コマンドは「呼び出し可能な処理」として定義
- キーバインド入力と Ex 入力は最終的に同じ実行系へ流す
- builtin は Symbol ベース、拡張は Proc も使える

### 内部コマンド (`CommandRegistry`)

内部コマンドは ID で管理します（例: `cursor.left`, `buffer.delete_line`）。

- 登録先: `RuVim::CommandRegistry.instance`
- 定義値: `call:` に `Symbol` または `Proc`
- 実行先: `RuVim::GlobalCommands.instance`

例:

```ruby
RuVim::CommandRegistry.instance.register(
  "cursor.left",
  call: :cursor_left,
  desc: "Move cursor left"
)
```

### Ex コマンド (`ExCommandRegistry`)

ユーザーが `:` 行で入力するコマンド名を管理します。

- 登録先: `RuVim::ExCommandRegistry.instance`
- canonical name + `aliases`
- `nargs`, `bang`, `desc` を保持

例:

```ruby
RuVim::ExCommandRegistry.instance.register(
  "w",
  call: :file_write,
  aliases: %w[write],
  nargs: :maybe_one,
  bang: true,
  desc: "Write current buffer"
)
```

`alias_for` は持ちません。`aliases` を登録時に展開し、同じ spec を参照させます。

### コマンド実装 (`GlobalCommands`)

コマンド本体は `RuVim::GlobalCommands.instance` のメソッドで実装します。

- `Symbol` 指定時は `public_send`
- `Proc` 指定時は `call`

想定の引数形:

- `ctx` (`RuVim::Context`)
- `argv: []`
- `kwargs: {}`
- `bang: false`
- `count: 1`

## 入力と実行の流れ

1. `RuVim::Input` が raw mode のキー入力を読む
2. `RuVim::App` が mode ごとに処理を分岐
3. Normal mode のキーは `RuVim::KeymapManager` で解決
4. `RuVim::Dispatcher` が内部コマンド or Ex コマンドを実行
5. `RuVim::Screen` が再描画

## 起動オプション（CLI, 現状）

`exe/ruvim` は `RuVim::CLI` を通して起動オプションを解釈します（`bin/ruvim` は互換ラッパー）。

- `--help`, `--version`
- `--clean`
  - user config と ftplugin の読み込みを抑止
- `-R`
  - 起動時に開いた current buffer を readonly にする（現状は保存禁止の意味）
- `-M`
  - 起動時に開いた file buffer を `modifiable=false` + `readonly=true` にする
- `-Z`
  - restricted mode（現状）
  - user config / ftplugin を読み込まない
  - `:ruby` を禁止する
- `-n`
  - 現状は no-op（将来の swap / 永続 undo / session 互換の先行予約）
- `-o[N]`, `-O[N]`, `-p[N]`
  - 複数ファイルを水平 split / 垂直 split / tab で開く
  - `N` は現状受理するがレイアウト数の厳密制御には未使用（将来拡張用）
- `-u {path|NONE}`
  - `path`: 指定ファイルを設定として読み込む
  - `NONE`: user config のみ無効化（ftplugin は有効）
- `-c {cmd}`
  - 起動後に Ex コマンドを実行（複数回指定可）
- `+{cmd}`, `+{line}`, `+`
  - 起動後の Ex 実行 / 行ジャンプ / 最終行ジャンプ

起動時コマンド（`-c`, `+...`）は、初期 buffer / file open / intro screen 構築の後に実行します。

### Keymap layering（現状）

`RuVim::KeymapManager` は以下の優先順で解決します（高 -> 低）。

1. filetype-local
2. buffer-local
3. mode-local
4. global

現状の標準バインドは mode-local のみですが、内部 API として各レイヤーの登録を持っています。

## モード仕様（現状）

### Normal mode

- `h/j/k/l`: 移動
- `0`: 行頭へ移動
- `$`: 行末へ移動
- `^`: 行頭の最初の非空白へ移動
- `w/b/e`: 単語移動
- `f/F/t/T` + 文字: 行内文字移動
- `;`, `,`: 直前の行内文字移動を繰り返し / 逆方向
- `%`: 対応括弧ジャンプ（`()[]{}`）
- `gg`: 先頭へ移動
- `G`: 末尾へ移動
- `i`: Insert mode
- `a`, `A`, `I`: 挿入開始位置を変えて Insert mode
- `o`, `O`: 下/上に行を開いて Insert mode
- `:`: Command-line mode
- `/`: 前方検索の command-line mode
- `?`: 後方検索の command-line mode
- `x`: カーソル位置の文字削除
- `dd`: 現在行削除
- `d` + motion: operator-pending delete（例: `dw`, `dj`, `dk`, `d$`, `dh`, `dl`）
- text object（`iw`, `aw`, `ip`, `ap`, `i"`, `a"`, ``i` ``, ``a` ``, `i)`, `a)`, `i]`, `a]`, `i}`, `a}`）を `d/y/c` と Visual で一部利用可
- `yy`, `yw`: yank
- `p`, `P`: paste
- `r<char>`: 1文字置換
- `c` + motion / `cc`: change（削除して Insert mode）
- `v`: Visual (characterwise)
- `V`: Visual (linewise)
- `u`: Undo
- `Ctrl-r`: Redo
- `.`: 直前変更の repeat（初版。`x`, `dd`, `d{motion}`, `p/P`, `r<char>`）
- `n`: 直前検索を同方向に繰り返し
- `N`: 直前検索を逆方向に繰り返し
- `1..9` + 動作: count（例: `3j`, `2x`）
- 矢印キー: 移動

### Insert mode

- 通常文字: 挿入
- `Enter`: 改行
- `Backspace`: 1文字削除 / 行結合
- `Ctrl-n` / `Ctrl-p`: buffer words 補完（次/前）
- `Esc`: Normal mode に戻る
- `Ctrl-c`: Normal mode に戻る（終了しない）
- 矢印キー: 移動

### Visual mode（現状）

- `v`: characterwise Visual の開始 / 終了
- `V`: linewise Visual の開始 / 切替
- 移動キー: `h/j/k/l`, `w/b/e`, `0/$/^`, `gg/G`, 矢印キー
- `y`: 選択範囲を yank
- `d`: 選択範囲を delete
- `i`/`a` + object: text object を選択（`iw`, `aw`, `ip`, `ap`, `i"`, `a"`, ``i` ``, ``a` ``, `i)`, `a)`, `i]`, `a]`, `i}`, `a}`）
- `Esc` / `Ctrl-c`: Normal mode に戻る

### Command-line mode

- `:` で入る
- `/` `?` でも入る（検索用）
- 文字入力 / `Backspace`
- `Enter` で Ex 実行
- `Esc` でキャンセル
- `Left` / `Right` でカーソル移動
- `Tab` (`Ctrl-i`) で Ex 補完
  - コマンド名
  - 一部引数（path / buffer / option）

## Ex コマンド仕様（現状 builtin）

- `:w [path]` / `:write [path]`
- `:q[!]` / `:quit[!]`
- `:wq[!] [path]`
- `:e <path>` / `:edit <path>`
- `:e[!] [path]` / `:edit[!] [path]`
- `:help [topic]`
- `:commands`
- `:command[!] <Name> <ex-body>`
- `:ruby <code>` / `:rb <code>`
- `:ls` / `:buffers`
- `:bnext` / `:bn`
- `:bprev` / `:bp`
- `:buffer <id|name|#>` / `:b <id|name|#>`
- `:split`
- `:vsplit`
- `:tabnew [path]`
- `:tabnext` / `:tabn`
- `:tabprev` / `:tabp`

## 検索仕様（現状）

- `/pattern` : 前方検索
- `?pattern` : 後方検索
- `n` : 直前検索を同方向に繰り返し
- `N` : 直前検索を逆方向に繰り返し
- `*`, `#` : カーソル下の単語を前/後方検索（単語境界つき）
- `g*`, `g#` : カーソル下の単語を前/後方検索（部分一致）
- `:%s/pat/repl/g` : バッファ全体 substitute（最小実装）

### 仕様メモ

- 検索文字列は Ruby 正規表現として扱う
- 末尾/先頭でラップ検索する
- 空の検索文字列は直前検索を再利用（直前がなければエラー）
- 検索開始位置は現在カーソルの次文字/前文字
- 可視範囲の検索ハイライトを表示（簡易）

補足:

- `:q` は未保存変更があると拒否
- `:q!` は強制終了
- `:e` は未保存変更があると拒否（`!` で破棄可）
- `:e!`（引数なし）は現在ファイルの再読込（undo/redo クリア）
- `:buffer!`, `:bnext!`, `:bprev!` は未保存変更があっても切替
- `:w!` は現状 `:w` と同等に受理（権限昇格などは未実装）

### `:command`（現状仕様）

- `:command Name ex_body` でユーザー定義 Ex コマンドを追加
- `:command! Name ex_body` で上書き
- `:command`（引数なし）でユーザー定義コマンド名一覧表示
- 定義されたコマンドは Ex コマンドとして `:Name` で実行
- 現状は「Ex コマンド文字列のエイリアス展開」に近い仕様

### `:ruby` / `:rb`（現状仕様）

- Ex 行から Ruby コードを評価する
- 評価スコープで利用可能なローカル:
  - `ctx`
  - `editor`
  - `buffer`
  - `window`
- 返り値はステータスラインに表示（`inspect`）

### バッファ管理 Ex コマンド（現状仕様）

- `:ls` / `:buffers` : バッファ一覧表示
- `:bnext` / `:bn` : 次バッファへ
- `:bprev` / `:bp` : 前バッファへ
- `:buffer` / `:b` : バッファ切替
  - 数値ID
  - パス名 / basename
  - `#`（alternate buffer）

### alternate buffer（`#`）

- `Editor#alternate_buffer_id` を保持
- バッファ切替時に直前バッファを更新
- `:buffer #` で切替可能

## 画面描画仕様（現状）

ANSI エスケープシーケンスによる再描画です。

- 代替スクリーン (`?1049h / ?1049l`)
- カーソル非表示/表示 (`?25l / ?25h`)
- 行キャッシュによる簡易差分描画（同サイズ時）
- 最下段: status line
- Command-line mode 時は最下段を command-line、1つ上を status line
- ファイル未指定起動時は Vim 風 intro screen を表示（RuVim では intro 用の read-only 特殊バッファ）
- カーソル位置の文字を反転表示（見やすさ向上）

### split UI（現状）

- `:split` / `:vsplit` で複数 window を作成
- レイアウトは簡易タイル（等分割）
  - `horizontal`: 上下分割
  - `vertical`: 左右分割
- nested split / Vim の厳密な window tree は未実装
- 各 window は cursor / scroll を独立して保持

### Tabpage（現状）

- `:tabnew [path]` で新しいタブを作成
- `:tabnext`, `:tabprev` で移動
- 各タブは以下を独立に保持
  - window list（表示中 window 群）
  - current window
  - split layout（horizontal / vertical / single）

### リサイズ対応

- `SIGWINCH` を trap して `Screen` キャッシュを無効化
- self-pipe (`IO.pipe`) で resize 通知を `select` 待ちへ伝播
- 入力待機は `stdin + resize通知` を `IO.select` で待つ
- 描画ごとに `winsize` を再取得して viewport を再計算

### Command-line 改善（現状）

- prefix ごとの履歴保持（`:` `/` `?`）
- `Up/Down` で履歴移動
- `Tab` で Ex コマンド名補完（prefix `:` のとき）

### 文字幅対応（現状ベースライン）

- UTF-8 文字列はそのまま保持・表示
- タブは描画時にスペース展開（`TABSTOP=2`）
- カーソル列計算に簡易 display width 計算を使用
- 一部の全角文字を幅2として扱う近似実装
- `RUVIM_AMBIGUOUS_WIDTH=2` で曖昧幅文字を幅2として扱える
- variation selector / ZWJ は幅0扱い
- 一部 emoji range を幅2として扱う

制約:

- 左右移動（`h/l`・矢印左右）は grapheme cluster を考慮するが、他の移動は未統一
- 完全な Unicode grapheme / East Asian Width 互換ではない
- スクロール幅判定は文字数ベースのまま（表示幅ベース最適化は未実装）

## Undo / Redo 仕様（現状）

- 実装単位: `RuVim::Buffer` ごとの undo / redo stack
- `u`: undo
- `Ctrl-r`: redo
- undo 対象:
  - 文字挿入
  - 改行
  - backspace
  - `x`
  - `dd`

### undo 粒度（現状）

- Normal mode の編集コマンドは原則 1 コマンド = 1 undo 単位
  - 例: `3x`, `3dd` はそれぞれ 1 undo
- Insert mode は「Insert mode に入ってから抜けるまで」を 1 undo 単位
  - `i` で入り、複数文字入力して `Esc`/`Ctrl-c` で抜けると 1 回の `u` で戻る

Vim 完全互換ではなく、まずは扱いやすい粒度を優先した仕様です。

## Operator-pending 仕様（現状）

- `d` を押すと delete operator pending 状態に入る
- 次のキーを motion として解釈して削除を実行

対応している `d + motion`:

- `dd` : 行削除
- `dh` : 左方向に文字削除
- `dl` : 右方向に文字削除
- `dj` : 下方向行を含めて行削除
- `dk` : 上方向行を含めて行削除
- `d$` : 行末まで削除
- `dw` : 次の単語先頭まで削除（簡易 word 定義）
- `diw`, `daw` : text object word（簡易）
- `di"`, `da"`, `di)`, `da)` : delimiter text object（簡易・同一行中心）

設計上は operator-pending 状態機械を導入しており、`d/y/c` を同じ流れで扱います。

補足:

- 現状 `y` operator も実装済み（`yy`, `yw`）
- 現状 `c` operator も実装済み（`cw`, `cc`, `c$`, `ciw`, `caw` など）

### text object（現状）

- 対応:
  - `iw`, `aw`
  - `i"`, `a"`
  - `i)`, `a)`
- 利用先:
  - operator-pending `d/y/c`
  - Visual mode（選択更新）
- 制約:
  - `i"` / `a"` / `i)` / `a)` は簡易実装（主に同一行）

## レジスタ仕様（現状の基礎）

- unnamed register (`"`) を実装
- named register（`"a`..`"z`）を実装
- append register（`"A`..`"Z`）を実装（小文字 register へ追記）
- black hole register（`"_`）を実装
- yank register `0` を実装（yank 操作で更新）
- numbered delete register `1-9` を簡易実装（delete/change 操作で回転）
- `"+`, `"*` は system clipboard register として扱う（利用可能 backend がある場合）
- delete / yank 操作で指定 register と unnamed register を更新
- `p`, `P` は指定 register（なければ unnamed）を paste
- register type:
  - `:charwise`
  - `:linewise`
- `yy`, `yw`, Visual `y` などで yank
- `x`, `dd`, `d{motion}`, Visual `d` などで delete した内容も保存

## Mark / Jump List（現状の基礎）

- mark 設定:
  - `m{a-z}`: local mark（buffer-local）
  - `m{A-Z}`: global mark
- mark jump:
  - `'{mark}`: 行単位ジャンプ（行頭の最初の非空白へ）
  - `` `{mark} ``: 位置ジャンプ
- jump list:
  - `<C-o>`: 古い位置へ
  - `<C-i>`: 新しい位置へ（端末では Tab と同じ入力コード）
  - `''`: 行単位で古い位置へ
  - `` `` ``: 位置ジャンプで古い位置へ
- 現状の jump list 追加契機（簡易）:
  - `gg`, `G`
  - 検索 (`/`, `?`, `n`, `N`, `*`, `#`, `g*`, `g#`)
  - バッファ切替（`:bnext`, `:bprev`, `:buffer`）

## Macro（現状の基礎）

- `q{reg}`: macro 記録開始（`q` で停止）
- `@{reg}`: macro 再生
- `@@`: 直前に再生した macro を再生
- register は `a-z`, `A-Z`, `0-9` を許可（`A-Z` は既存 macro に追記）
- 再帰再生は簡易ガードあり（同一 macro 再入 / 深すぎる入れ子を拒否）

## Option system（現状の基礎）

- option スコープ:
  - global
  - buffer-local
  - window-local
- Ex:
  - `:set`
  - `:setlocal`
  - `:setglobal`
- 実装済み option:
  - `number`（window-local, bool）
  - `relativenumber`（window-local, bool）
  - `ignorecase` / `smartcase` / `hlsearch`（global, bool）
  - `tabstop`（buffer-local, int）
- `Screen` は `number` / `relativenumber` / `tabstop` を描画に反映する

## Filetype / ftplugin（現状の基礎）

- buffer 作成時に path から `filetype` を簡易検出して buffer-local option に保存
- ftplugin 読み込みパス（優先順）:
  - `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
  - `~/.config/ruvim/ftplugin/<filetype>.rb`
- ftplugin では:
  - `nmap` / `imap` -> filetype-local keymap として登録
  - `setlocal` / `setglobal` / `set`（DSL）で option 変更可
- 同一 buffer の同一 filetype ftplugin は一度だけ読み込む

## シンタックスハイライト（最小）

- 描画時に filetype ごとの regex ベース highlighter を適用
- 現状の対応 filetype:
  - `ruby`
  - `json`
- 優先度（高 -> 低）:
  - cursor / visual
  - search highlight
  - syntax highlight
- 実装は `lib/ruvim/highlighter.rb`
- Vim の syntax / treesitter 相当の互換性はない（最小実装）

## シングルトン方針

グローバルに共有して良い「定義系」だけシングルトンにしています。

- `RuVim::CommandRegistry.instance`
- `RuVim::ExCommandRegistry.instance`
- `RuVim::GlobalCommands.instance`

`RuVim::Editor` はシングルトンではありません（実行状態の分離のため）。

## 設定ファイル（現状）

- 起動時に XDG パスの設定ファイルを読み込む（存在する場合）
  - `$XDG_CONFIG_HOME/ruvim/init.rb`
  - 未設定時: `~/.config/ruvim/init.rb`
- `RuVim::ConfigLoader` + `RuVim::ConfigDSL` を使用
- DSL は `BasicObject` ベースで、主に以下を提供:
  - `nmap`
  - `imap`
  - `map_global`
  - `command`
  - `ex_command`
  - `ex_command_call`

安全性メモ:

- XDG 設定ファイル（`init.rb`）は Ruby として評価されるため、信頼できる内容のみ使用する
- 直接内部状態に触る代わりに、まずは DSL API を通す設計

## テスト（現状）

- `Minitest` を利用
- 追加済み:
  - `test/buffer_test.rb`
  - `test/dispatcher_test.rb`
  - `test/keymap_manager_test.rb`

## 既知の未実装 / 今後の仕様候補

- Undo / Redo
- 複数 window split
- Tabpage
- レジスタ（yank/delete）
- 検索 (`/`, `?`)
- operator-pending（`d` + motion）
- 差分描画
- filetype / buffer-local keymap
- user-defined Ex command DSL（`:command`）
- `:ruby`（Ruby 式評価）
