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

#### Buffer 構造メモ（性能検討）

現状の `RuVim::Buffer` は「行配列 + Ruby String 直接編集」です。

- 利点:
  - 実装が単純でデバッグしやすい
  - undo snapshot 実装と相性がよい
- 欠点:
  - 大きいテキストで中央付近の挿入/削除が増えるとコピーコストが目立つ
  - 永続 undo / 差分保存を入れると snapshot 方式のメモリ負荷が上がる

将来の候補（検討済み）:

- `piece table`
  - undo/redo と相性がよく、エディタ実装で定番
  - 行インデックスを別途持つ必要がある
- `rope`
  - 大規模テキストの編集に強い
  - 実装複雑度が上がる（Ruby での実装コスト高め）

当面の方針:

- まずは現在構造のまま描画/ハイライト/検索側を最適化
- `永続 undo` を実装する段階で `piece table` 移行を再評価する

### 2. Window

`Buffer` をどの位置で表示するかを持つビューです。

- `buffer_id`
- `cursor_x`, `cursor_y`
- `row_offset`, `col_offset`

同一 buffer を複数 window で表示できる前提の設計です（現状 UI は単一 window）。
同一 buffer を複数 window で表示できる前提の設計です（現状 UI は simple split 対応）。

#### 座標系（現状の単位）

RuVim は Vim と同様に、用途ごとに座標系を分けています。

- `buffer row` (`cursor_y`, `row_offset`)
  - 行番号ベース（0-origin）
- `char index` (`cursor_x`, `col_offset`)
  - Ruby の UTF-8 `String` に対する文字 index（byte offset ではない）
- `grapheme boundary`
  - 左右移動時は `RuVim::TextMetrics` で grapheme cluster 境界に揃える
- `screen column`
  - 描画・横スクロールでは表示幅（全角/結合文字/tab 幅込み）を使う

役割分担（現状）:

- `RuVim::Window`
  - カーソル位置保持（`char index`）
  - `ensure_visible` で `screen column` ベースの横スクロール
- `RuVim::TextMetrics`
  - `char index <-> screen column` 変換
  - grapheme 境界移動
- `RuVim::Screen`
  - 表示幅ベースの clipping / padding / cursor 描画位置計算

### 3. Editor

エディタ全体の実行状態です。

- buffers / windows 管理
- layout tree（ネストしたウィンドウ分割をツリーで管理）
- tabpages 管理（タブごとに layout tree / current window を保持）
- current window の管理
- mode 管理（`:normal`, `:insert`, `:command_line`, `:rich`）
- message line のメッセージ管理
- command-line 状態

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
5. Insert mode でキー処理後、stdin に未読データが残っていればレンダリングをスキップして追加のキーを読み取り・処理する（ペースト高速化）。このバッチ処理中は autoindent を抑制し、貼り付けテキストが余分にインデントされるのを防ぐ
6. `RuVim::Screen` が再描画

## 起動オプション（CLI, 現状）

インストール後の `ruvim` コマンド（実体は `exe/ruvim`）は `RuVim::CLI` を通して起動オプションを解釈します（`bin/ruvim` は互換ラッパー）。

- `--help`, `--version`
- `--clean`
  - user config と ftplugin の読み込みを抑止
- `-R`
  - 起動時に開いた current buffer を readonly にする（現状は保存禁止の意味）
- `-d`
  - diff mode 互換 placeholder（現状は通常起動 + 未実装メッセージ表示）
- `-q {errorfile}`
  - `-q {errorfile}` は quickfix 起動互換 placeholder（現状は未実装メッセージ表示）
  - Ex の quickfix/location list は最小実装あり（`:vimgrep`, `:lvimgrep`, `:copen`, `:cnext` など）
- `-S [session]`
  - session 起動互換 placeholder（現状は未実装メッセージ表示）
- `-M`
  - 起動時に開いた file buffer を `modifiable=false` + `readonly=true` にする
- `-Z`
  - restricted mode（現状）
  - user config / ftplugin を読み込まない
  - `:ruby` / `:rb` を禁止する
  - `:!` を禁止する
  - `:grep` / `:lgrep` を禁止する
  - `:git` / `:gh` を禁止する
  - Ruby 構文チェック（`on_save`）を無効化する
- `-n`
  - 現状は no-op（将来の swap / 永続 undo / session 互換の先行予約）
- `-o[N]`, `-O[N]`, `-p[N]`
  - 複数ファイルを水平 split / 垂直 split / tab で開く
  - `N` は現状受理するがレイアウト数の厳密制御には未使用（将来拡張用）
- `-V[N]`, `--verbose[=N]`
  - verbose ログを `stderr` に出力（現状は startup / config / startup actions / Ex submit の簡易ログ）
- `--startuptime FILE`
  - 起動フェーズ時刻の簡易ログをファイルへ出力
  - 現状は `init.start`, `pre_config_actions.done`, `config.loaded`, `signals.installed`, `buffers.opened`, `ftplugin.loaded`, `startup_actions.done`
- `--cmd {cmd}`
  - user config 読み込み前に Ex コマンドを実行（複数回指定可）
- `-u {path|NONE}`
  - `path`: 指定ファイルを設定として読み込む
  - `NONE`: user config のみ無効化（ftplugin は有効）
- `-c {cmd}`
  - 起動後に Ex コマンドを実行（複数回指定可）
- `+{cmd}`, `+{line}`, `+`
  - 起動後の Ex 実行 / 行ジャンプ / 最終行ジャンプ

補足（現状実装）:

- `stdin` が non-TTY で、起動引数ファイルがない場合は `stdin` を follow stream として開く
  - バッファ名は `[stdin]`
  - statusline に `[stdin/live]`, `[stdin/closed]`, `[stdin/error]` を表示
  - Normal mode の `Ctrl-c` はデフォルトバインドで `stdin` stream stop（上流 PID へ直接 signal は送らない）
- `Ctrl-z` は全モード共通で suspend
  - suspend 前に terminal を cooked + main screen に戻す
  - `SIGTSTP` を自身に送って停止
  - `fg` 復帰後に raw + alt screen を再有効化して再描画

起動時コマンド（`-c`, `+...`）は、初期 buffer / file open / intro screen 構築の後に実行します。
`--cmd` はそれより前で、user config 読み込み前に実行します。

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
- `=` + motion / `==`: auto-indent（Ruby / JSON filetype でインデント自動調整。`=j`, `=G` 等）
- `v`: Visual (characterwise)
- `V`: Visual (linewise)
- `Ctrl-v`: Visual (blockwise, 最小)
- `u`: Undo
- `Ctrl-r`: Redo
- `.`: 直前変更の repeat（拡張版。`x`, `dd`, `d{motion}`, `p/P`, `r<char>`, `i/a/A/I/o/O`, `cc`, `c{motion}`）
- `n`: 直前検索を同方向に繰り返し
- `N`: 直前検索を逆方向に繰り返し
- `1..9` + 動作: count（例: `3j`, `2x`）
- 矢印キー: 移動
- `Ctrl-z`: shell へ suspend（`fg` で復帰）

### Insert mode

- 通常文字: 挿入
- `Enter`: 改行
- `Backspace`: 1文字削除 / 行結合
- `Ctrl-n` / `Ctrl-p`: buffer words 補完（次/前）
- `Esc`: Normal mode に戻る
- `Ctrl-c`: Normal mode に戻る（終了しない）
- 矢印キー: 移動
- `Ctrl-z`: shell へ suspend（`fg` で復帰）

### Visual mode（現状）

- `v`: characterwise Visual の開始 / 終了
- `V`: linewise Visual の開始 / 切替
- `Ctrl-v`: blockwise Visual の開始 / 切替（最小）
- 移動キー: `h/j/k/l`, `w/b/e`, `0/$/^`, `gg/G`, 矢印キー
- `y`: 選択範囲を yank
- `d`: 選択範囲を delete
- `i`/`a` + object: text object を選択（`iw`, `aw`, `ip`, `ap`, `i"`, `a"`, ``i` ``, ``a` ``, `i)`, `a)`, `i]`, `a]`, `i}`, `a}`）
- `Esc` / `Ctrl-c`: Normal mode に戻る
- `Ctrl-z`: shell へ suspend（`fg` で復帰）
- blockwise の text object 選択 / paste の Vim 互換挙動は未対応

### Rich mode

- `:rich [format]` / `gr` で入る（トグル）
- 同一バッファ上で動作（仮想バッファを作らない）
- Normal mode とほぼ同じキーバインドが使える（移動・検索・yank 等）
- バッファを変更する操作（insert/delete/change/paste/replace）はブロック
- `Esc` / `Ctrl-C` で Normal mode に戻る
- statusline に `-- RICH --` を表示
- 描画時に表示行をテーブル整形（`TableRenderer` を利用）
- wrap は強制 OFF

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
- `Ctrl-z` で shell へ suspend（`fg` で復帰）

### Hit-enter prompt（複数行メッセージ表示）

`:ls` や `:set`（引数なし）など、複数行にわたる出力を行うコマンドの結果を表示するモード。

- 画面下部にメッセージ行をオーバーレイ描画
- 最下行に「Press ENTER or type command to continue」を反転表示
- statusline は非表示（Vim と同様）
- 対象コマンド: `:ls` / `:buffers`, `:args`, `:set`（引数なし）, `:command`（引数なし）
- 1行以下の出力時は通常の `echo` を使用

#### キー操作

- `Enter` / `Space` / `Escape` / `Ctrl-C` / その他のキー → dismiss（通常モードに戻る）
- `:` → dismiss して Command-line mode に入る
- `/` / `?` → dismiss して検索 Command-line mode に入る

## Ex コマンド仕様（現状 builtin）

- `:w [path]` / `:write [path]`
- `:q[!]` / `:quit[!]`
- `:qa[!]` / `:qall[!]`
- `:wq[!] [path]`
- `:wqa[!]` / `:wqall[!]` / `:xa[!]` / `:xall[!]`
- `:e <path>` / `:edit <path>`
- `:e[!] [path]` / `:edit[!] [path]`
- `:help [topic]`
- `:commands`
- `:bindings [mode]`
- `:command[!] <Name> <ex-body>`
- `:ruby <code>` / `:rb <code>`
- `:!<command>`
- `:ls` / `:buffers`
- `:bnext` / `:bn`
- `:bprev` / `:bp`
- `:buffer <id|name|#>` / `:b <id|name|#>`
- `:bdelete[!] [id|name|#]` / `:bd[!] [id|name|#]`
- `:split`
- `:vsplit`
- `:tabnew [path]`
- `:tabnext` / `:tabn`
- `:tabprev` / `:tabp`
- `:vimgrep`, `:lvimgrep`
- `:copen`, `:cclose`, `:cnext` / `:cn`, `:cprev` / `:cp`
- `:lopen`, `:lclose`, `:lnext` / `:ln`, `:lprev` / `:lp`
- `:grep /pattern/ [path...]`, `:lgrep /pattern/ [path...]`
  - `grepprg` を argv 配列として実行（シェル経由ではない）
  - ファイル引数の glob パターンは Ruby 側で展開
  - restricted mode（`-Z`）では禁止
- `:git checkout <branch>` でブランチ切り替え
  - ブランチ一覧（`:git branch`）で Enter を押すとコマンドラインにプリフィル、明示的に Enter で確定
- `:filter [/pattern/]` : 検索マッチ行のみのフィルタバッファを作成（`g/` キーバインド）
- `:rich [format]`
- `:d [count]` / `:delete`
- `:y [count]` / `:yank`
- `:tabs`
- `:args`, `:next`, `:prev`, `:first`, `:last`

## 検索仕様（現状）

- `/pattern` : 前方検索
- `?pattern` : 後方検索
- `n` : 直前検索を同方向に繰り返し
- `N` : 直前検索を逆方向に繰り返し
- `*`, `#` : カーソル下の単語を前/後方検索（単語境界つき）
- `g*`, `g#` : カーソル下の単語を前/後方検索（部分一致）
- `:{range}s/pat/repl/[flags]` : substitute（フラグ: `g`, `i`, `I`, `n`, `e` 対応。`c` は未実装）

### 仕様メモ

- 検索文字列は Ruby 正規表現として扱う
- 末尾/先頭でラップ検索する
- 空の検索文字列は直前検索を再利用（直前がなければエラー）
- 検索開始位置は現在カーソルの次文字/前文字
- 可視範囲の検索ハイライトを表示（簡易）

補足:

- `:q` は未保存変更があると拒否
- `:q` は Vim 寄りに、複数 window 時は current window を閉じる（window が1つで tab が複数なら current tab を閉じる）
- `:q!` は強制的に window / tab / app を閉じる
- `:qa` は全ウィンドウ/タブを無視して一括終了（未保存バッファがあると拒否、`:qa!` で強制）
- `:wqa` は全バッファを保存して一括終了
- `:e` は未保存変更があると拒否（`!` で破棄可）
- `:e!`（引数なし）は現在ファイルの再読込（undo/redo クリア）
- `:buffer!`, `:bnext!`, `:bprev!` は未保存変更があっても切替
- `:w!` は現状 `:w` と同等に受理（権限昇格などは未実装）
- `:bindings` は current buffer 文脈の有効 key binding を layer 別（`buffer`, `filetype`, `app`）に一覧表示
  - 任意で mode filter を受ける（例 `:bindings normal`）
- 大きいファイルを開くときは、閾値以上で段階読み込みになる場合がある
  - statusline に `[load/live]`（失敗時 `[load/error]`）
  - デフォルト実装は先頭 `8MB` を先に表示し、残りをチャンク単位でバックグラウンド読み込み
  - 環境変数:
    - `RUVIM_ASYNC_FILE_THRESHOLD_BYTES`
    - `RUVIM_ASYNC_FILE_PREFIX_BYTES`
- ファイルを開く際、FIFO・デバイス・ソケット等の特殊ファイルは拒否する（`File.file?` チェック）

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
- `stdout` / `stderr` に出力があれば `[Ruby Output]` 仮想バッファに表示（返り値も表示）
- 出力がない場合、返り値を message line に表示（`inspect`）

### `:r` / `:read`（ファイル・コマンド出力の挿入）

- `:r <file>` でファイルの内容をカーソル行の下に挿入
- `:r !<command>` でシェルコマンドの stdout を挿入
- 行番号指定可: `:3r file.txt`（3行目の下に挿入）
- stderr が出た場合、最初の行をエラーメッセージとして表示

### `:w !`（バッファ内容をコマンドへパイプ）

- `:w !<command>` でバッファ全体をシェルコマンドの stdin に渡す
- 範囲指定可: `:'<,'>w !sort`（選択範囲のみ渡す）

### `:!`（shell 実行, 最小）

- `:!<command>` で shell コマンドを同期実行
- alternate screen を一時的に抜けて main screen 上でコマンドを実行（Vim 互換）
- 実行後 "Press ENTER or type command to continue" を表示し、入力待ち後にエディタに復帰
- 完了後は `shell exit N` をステータス表示
- restricted mode（`-Z`）では禁止

### バッファ管理 Ex コマンド（現状仕様）

- `:ls` / `:buffers` : バッファ一覧表示
- `:bnext` / `:bn` : 次バッファへ
- `:bprev` / `:bp` : 前バッファへ
- `:buffer` / `:b` : バッファ切替
  - 数値ID
  - パス名 / basename
  - `#`（alternate buffer）
- `:bdelete` / `:bd` : バッファ削除（未保存は `!` 必須）

### alternate buffer（`#`）

- `Editor#alternate_buffer_id` を保持
- バッファ切替時に直前バッファを更新
- `:buffer #` で切替可能

### arglist（引数リスト）

- `Editor#arglist` と `Editor#arglist_index` を保持
- 起動時に複数ファイル引数があるとarglistが初期化される
- 複数ファイル起動時、レイアウトオプション未指定でも全ファイルをバッファとして読み込む（`:ls` に表示される）
- `:args` : arglistを表示（現在の引数は `[filename]` で表示）
- `:next` / `:prev` : arglist内を移動
- `:first` / `:last` : arglistの最初/最後に移動
- arglist移動時にalternate bufferも更新される

## 画面描画仕様（現状）

ANSI エスケープシーケンスによる再描画です。

- 代替スクリーン (`?1049h / ?1049l`)
- カーソル非表示/表示 (`?25l / ?25h`)
- 行キャッシュによる簡易差分描画（同サイズ時）
- フッターは 2 行固定:
  - 最下段: 用途に応じて command-line（`:` `/` `?` 入力時）または message line（メッセージ表示時）として使用。複数行メッセージ時は hit-enter prompt で表示
  - 1つ上: statusline（モード・ファイル名・カーソル位置）
- command-line mode 時も statusline は維持し、最下段だけを入力行として使う
- ファイル未指定起動時は Vim 風 intro screen を表示（RuVim では intro 用の read-only 特殊バッファ）
- カーソル位置の文字を反転表示（見やすさ向上）
- カーソル形状の制御（DECSCUSR）
  - Normal / Visual mode: ターミナルカーソルを非表示にし、セル描画（反転）でカーソルを表現
  - Insert / Command-line mode: ターミナルのバーカーソル（`\e[6 q`）を表示
  - UI 開始時に非点滅ブロック（`\e[2 q`）を設定、終了時にデフォルト（`\e[0 q`）に復元

### split UI

- `:split` / `:vsplit` で複数 window を作成
- レイアウトはツリー構造（ネストした分割に対応）
  - `hsplit`: 上下分割
  - `vsplit`: 左右分割
  - 例: vsplit 後に右ウィンドウを split すると、右カラムだけが上下分割される
- 同方向の分割は親ノードにマージ（hsplit の中で hsplit しても 1 レベルに統合）
- `close_window` でツリーを簡略化（子が 1 個になった分割ノードは子に置き換え）
- `focus_window_direction` は正規化座標空間で最近接ウィンドウを選択
- 各 window は cursor / scroll を独立して保持

### Tabpage（現状）

- `:tabnew [path]` で新しいタブを作成
- `:tabnext`, `:tabprev` で移動
- `:tabs` で全タブ一覧を表示（各タブのウィンドウとバッファ名）
- statusline に `tab:n/m` を表示（タブが2つ以上のとき）
- 各タブは以下を独立に保持
  - window list（表示中 window 群）
  - current window
  - split layout（horizontal / vertical / single）

### リサイズ対応

- `SIGWINCH` を trap して `Screen` キャッシュを無効化
- self-pipe (`IO.pipe`) で resize 通知を `select` 待ちへ伝播
- 入力待機は `stdin + resize通知` を `IO.select` で待つ
- 描画ごとに `winsize` を再取得して viewport を再計算

### suspend / resume（現状）

- `Ctrl-z` 入力は app レベルで処理し、モードに関係なく suspend する
- suspend 時は terminal を cooked + main screen に戻してから `SIGTSTP` を送る
- `fg` 復帰時は alt screen を再有効化し、`Screen` キャッシュを破棄して全面再描画する

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

描画の幅処理（現状）:

- 本文行の clipping/padding は `RuVim::TextMetrics.clip_cells_for_width` を共通利用
  - tab 展開
  - `source_col` 保持（cursor/search/syntax highlight の重ね合わせ用）
- 横スクロール可視判定と cursor 列計算は `char index <-> screen column` 変換で揃える
- ステータス/エラー行は「プレーン文字列を先に切り詰めてから SGR を付ける」方針で ANSI 切断を避ける

制約:

- 左右移動（`h/l`・矢印左右）は grapheme cluster を考慮するが、他の移動は未統一
- 完全な Unicode grapheme / East Asian Width 互換ではない
- 横スクロール可視判定は `screen column` ベース（`TextMetrics` 利用）

### エンコーディング方針（現状）

- 読み込み:
  - `File.binread` で bytes を取得
  - `RuVim::Buffer.decode_text` で UTF-8 へ変換して保持
  - UTF-8 として妥当ならそのまま使用
  - 不正 UTF-8 の場合は `Encoding.default_external` を試し、それでもダメなら `scrub`
- 内部表現:
  - `Buffer#lines` は UTF-8 `String` 前提
- 保存:
  - 現状は `File.binwrite` で `lines.join("\n")` をそのまま保存
  - 実質的に UTF-8 保存（元 encoding の保持は未実装）
- 制約:
  - 元ファイル encoding の保持/再保存は未対応
  - 不正バイト列を完全保持したまま編集するモードは未実装

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

設計上は operator-pending 状態機械を導入しており、`d/y/c/=` を同じ流れで扱います。

補足:

- 現状 `y` operator も実装済み（`yy`, `yw`）
- 現状 `c` operator も実装済み（`cw`, `cc`, `c$`, `ciw`, `caw` など）
- 現状 `=` operator も実装済み（`==`, `=j`, `=k`, `=G`, `=gg`、Visual `=`）
  - Ruby filetype の場合にネスト構造に基づく自動インデントを適用
  - 他の filetype はフォールバック（現在のインデント維持）

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
- 実装済み option は `RuVim::Editor::OPTION_DEFS` に定義（現状 `49` 個）
- 代表例:
  - window-local: `number`, `relativenumber`, `wrap`, `linebreak`, `breakindent`, `cursorline`, `scrolloff`, `sidescrolloff`
  - global: `ignorecase`, `smartcase`, `hlsearch`, `incsearch`, `splitbelow`, `splitright`, `hidden`, `clipboard`, `timeoutlen`
  - buffer-local: `tabstop`, `expandtab`, `shiftwidth`, `softtabstop`, `autoindent`, `smartindent`, `filetype`, `onsavehook`
- 詳細な一覧・実装状況は `docs/config.md` を参照

## Filetype / ftplugin（現状の基礎）

- buffer 作成時に path から `filetype` を簡易検出して buffer-local option に保存
- ftplugin 読み込みパス（優先順）:
  - `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`
  - `~/.config/ruvim/ftplugin/<filetype>.rb`
- ftplugin では:
  - `nmap` / `imap` -> filetype-local keymap として登録
  - `setlocal` / `setglobal` / `set`（DSL）で option 変更可
- 同一 buffer の同一 filetype ftplugin は一度だけ読み込む

## Lang モジュール on_save フック

- Lang モジュールに `on_save(ctx, path)` ライフサイクルフックを定義
- `:w` でファイル保存後、`onsavehook` オプションが有効（デフォルト `true`）なら `buffer.lang_module.on_save(ctx, target)` を呼び出す
- `Lang::Base.on_save` はデフォルトで何もしない（no-op）
- `Lang::Ruby.on_save` は `ruby -wc` で構文チェックを実行し、エラー/警告を quickfix list に展開する
  - エラー出力を `filename:line:` 形式でパースし quickfix items に変換
  - 複数エラー時はヒント `(]q to see next, N total)` を表示
  - 正常時は quickfix list を空にクリアする
- `:set noonsavehook` で無効化可能

## シンタックスハイライト（最小）

- 描画時に filetype ごとの regex ベース highlighter を適用
- 現状の対応 filetype:
  - `ruby`
  - `json` / `jsonl`
  - `markdown`（見出し・フェンス・HR・ブロック引用・インライン装飾）
  - `scheme`
  - `diff`
  - `c`（C/C++: キーワード・型名・文字列・数値・コメント・プリプロセッサ・定数マクロ。スマートインデント・保存時 gcc チェック対応）
- 優先度（高 -> 低）:
  - cursor / visual
  - search highlight
  - syntax highlight
- 実装は `lib/ruvim/highlighter.rb`（ディスパッチャ）+ `lib/ruvim/lang/markdown.rb`（言語固有ロジック）
- Vim の syntax / treesitter 相当の互換性はない（最小実装）

## Rich mode（構造化データ表示）

構造化データ（TSV/CSV）や Markdown を見やすく整形して表示するモードです。
Visual mode と同様に Normal mode の上に乗るモードとして設計されています。

- **アーキテクチャ**: filetype ごとにレンダラーを登録できる汎用フレームワーク
  - `RuVim::RichView` モジュール（`lib/ruvim/rich_view.rb`）
  - レンダラー登録: `RichView.register(filetype, renderer)`
  - レンダラー: `TableRenderer`（TSV/CSV）、`MarkdownRenderer`（Markdown）、`JsonRenderer`（JSON）、`JsonlRenderer`（JSONL）
  - `JsonRenderer` は仮想バッファ方式: ミニファイ JSON を `JSON.pretty_generate` で整形し、読み取り専用バッファに表示
  - `JsonlRenderer` は仮想バッファ方式: 各行を個別にパース・整形し、`---` セパレータで区切って読み取り専用バッファに表示。パースエラー行はエラーマーカー付きで表示
  - 仮想バッファ方式のレンダラーでは `Esc` / `C-c` でバッファを閉じて元に戻れる
- **起動方法**:
  - `:rich [format]` Ex コマンド（トグル）
  - `gr` Normal mode キーバインド（トグル）
- **モード仕様**:
  - 同一バッファ上で動作（仮想バッファを作成しない）
  - `Editor#rich_state` に format/delimiter を保持
  - Normal mode とほぼ同じキーバインドが使える（移動・検索・yank 等）
  - バッファを変更する操作（insert/delete/change/paste/replace）はブロック
  - `Esc` / `Ctrl-C` で Normal mode に戻る
  - statusline に `-- RICH --` を表示
  - wrap は強制 OFF
- **レンダリング**:
  - `Screen` の `plain_window_render_rows` で `editor.rich_mode?` を判定
  - Rich mode の場合、表示行だけを `RichView.render_visible_lines` で整形
  - バッファ内容は変更せず、描画パイプラインでの変換のみ
  - `render_rich_view_line_sc` は ANSI エスケープシーケンスを幅ゼロとして扱い、横スクロール時もスタイルを正しく維持
  - Rich view に渡す前にバッファ行の制御文字（ESC 含む）をサニタイズし、terminal escape injection を防止
- **横スクロール**:
  - 表示カラム（display column）ベースでスクロール量を管理（`@rich_col_offset_sc`）
  - `renderer.cursor_display_col` で raw バッファの `cursor_x` を整形後の表示カラムに変換し、スクロールオフセットを決定
  - `render_rich_view_line_sc` で各行を同じ表示カラム数だけスキップして描画（CJK/ASCII 混在でも列揃えが保たれる）
  - ワイド文字がビューポート左端をまたぐ場合はスペースで置換（部分表示は不可）
  - カーソルの画面位置も整形後の表示カラム座標で計算
- **テーブルレンダラー仕様**:
  - 区切り表示: ` | `（スペース+パイプ+スペース）
  - 列幅は画面に見えている行だけから計算（大規模ファイルでも高速）
  - CJK 文字の表示幅を `DisplayWidth.display_width` で正確に計算
  - CSV は最小限の quoted field パース対応
  - 列が1つしかない場合は元の行をそのまま返す
- **Markdown レンダラー仕様**:
  - インラインマーカー（`#`, `**`, `*`, `` ` `` 等）は残し、ANSI スタイルを重ねる
  - 見出し H1-H6: レベル別 bold + 色
  - インライン装飾: `**bold**`, `*italic*`, `` `code` ``, `[text](url)`, チェックボックス
  - コードブロック: `` ``` ``/`~~~` フェンスで状態追跡、内容を暖色表示
  - コードフェンス状態は `pre_context_lines` で表示領域前の行から引き継ぎ
  - テーブル: `|...|` パターンを検出し、列幅揃え + box-drawing 罫線（`│`, `─`, `┼`, `├`, `┤`）
  - HR: `---`/`***`/`___` を `─` 線に置換
  - ブロック引用: `>` で始まる行を cyan 表示
  - テーブル行のカーソルマッピングはパディング後の位置を計算
- **filetype 検出**:
  - `.tsv` → `tsv`, `.csv` → `csv`, `.md` → `markdown`
  - `:rich`（引数なし）は filetype から判定、不明なら内容を見て自動推測

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
  - `set`
  - `setlocal`
  - `setglobal`
  - `command`
  - `ex_command`
  - `ex_command_call`

安全性メモ:

- XDG 設定ファイル（`init.rb`）は Ruby として評価されるため、信頼できる内容のみ使用する
- 直接内部状態に触る代わりに、まずは DSL API を通す設計

## Git 連携

### Git Blame

`<C-g>` で `:git ` プリセットのコマンドラインモードに入る。`:git <subcommand>` で実行。
未知のサブコマンドは `:!` と同様に alternate screen を抜けてシェルで直接実行する（例: `:git stash`）。`:gh` も同様（例: `:gh issue list`）。

### GitStatus

`:git status` で `git status` の結果を `kind: :git_status` の読み取り専用バッファで表示。

### GitDiff

`:git diff` で `git diff` の結果を `kind: :git_diff` の読み取り専用バッファで表示（filetype: diff）。追加引数をそのまま渡せる（例: `:git diff --cached`）。差分がない場合はメッセージ表示のみ。Enter で差分行に対応するファイルの該当行にジャンプ。`:git log -p` バッファでも同様に動作する。

### GitLog

`:git log` で `git log` の結果を `kind: :git_log` の読み取り専用バッファで表示。追加引数をそのまま渡せる（例: `:git log -p`）。`-p` 指定時は filetype: diff で syntax highlight が効く。出力はストリーミングで逐次表示（カーソルは先頭行に固定）。バッファを閉じるとプロセスも停止する。

### GitBranch

`:git branch` で `git branch -a` の結果を `kind: :git_branch` の読み取り専用バッファで表示。コミット日時の新しい順にソート。各行にブランチ名、日付、最新コミットのサブジェクトを表示。Enter でカーソル行のブランチ名を `:git checkout <branch>` としてコマンドラインにプリフィル（確認ステップあり、即時実行ではない）。

### GitGrep

`:git grep <pattern> [<args>...]` で `git grep -n` を実行し、結果を `kind: :git_grep` の読み取り専用バッファで表示。追加引数をそのまま渡せる（例: `:git grep -i pattern`）。マッチがない場合はメッセージ表示のみ。Enter で該当ファイルの該当行にジャンプ。Esc / Ctrl-C でバッファを閉じる。

### GitCommit

`:git commit` でコミットメッセージ編集バッファ（`kind: :git_commit`）を開く。`#` で始まる行はコメント（git status 情報を表示）。insert モードで開始。`:w` または `:wq` でコミット実行。`:q!` でキャンセル。メッセージが空の場合はコミットを中止。

### GitBlame

- **Blame バッファ**: `kind: :blame`、readonly、modifiable=false
- 表示形式: ガター（行番号エリア）にメタ情報（短縮ハッシュ・著者名・日付）を暗灰色で表示、本文はコードのみで元ファイルの filetype に基づく syntax highlight が適用される
- `gutter_labels` オプション: バッファに行ごとのガターラベルを設定する汎用機能。設定されると行番号の代わりにラベルを表示
- 内部で `git blame --porcelain` を使用して構造化パース
- ソースファイルのカーソル行位置を引き継ぐ

Blame バッファ内のバッファローカルバインディング:

- `p` (GitBlamePrev): カーソル行のコミット C に対し `git blame C^` の結果に更新。履歴スタックに現在の状態を push
- `P` (GitBlameBack): 履歴スタックから pop して前の blame 状態に復元
- `c` (GitBlameCommit): カーソル行のコミットの `git show` 結果を `kind: :git_show` の読み取り専用バッファで表示（filetype: diff）

実装: `lib/ruvim/git/blame.rb`（blame パース・実行）、`lib/ruvim/git/commands.rb`（status/diff/log 実行）、`lib/ruvim/global_commands.rb`（コマンドハンドラ）

## GitHub 連携

### gh link

`:gh link` で現在のファイル・カーソル行の GitHub URL を生成し、message line に表示する。同時に OSC 52 エスケープシーケンスでクリップボードにコピーする。

- ビジュアル選択範囲（`:'<,'>gh link`）を指定すると `#L5-L10` 形式の行範囲リンクを生成
- GitHub リモートを自動検出（全リモートを走査し、`origin` → `upstream` → その他の優先順位）
- SSH / HTTPS 両対応
- `:gh link <remote>` でリモート名を明示指定可能
- 現在のブランチ名を使用
- ファイルがリモートと異なる場合、URL の後に `(remote may differ)` を注記
- GitHub リモートが見つからない場合はエラー

### gh browse

`:gh browse` で現在のファイル・カーソル行の GitHub URL をブラウザで開く。

- `:gh link` と同じ URL 解決ロジック（行範囲、リモート自動検出、リモート指定）
- ブラウザ起動は `Browser` モジュールを使用（macOS: `open`, Linux: `xdg-open`, WSL: `wslview` / PowerShell）
- 開いた URL を message line に表示
- ファイルがリモートと異なる場合、`(remote may differ)` を注記

### gh pr

`:gh pr` で現在のブランチの PR ページをブラウザで開く。

- `https://github.com/user/repo/pulls?q=head:<branch>` を生成して開く
- ファイルパスがなくても動作（カレントディレクトリから git リポジトリを検出）

実装: `lib/ruvim/gh/link.rb`, `lib/ruvim/browser.rb`

## テスト（現状）

- `Minitest` を利用
- 追加済み:
  - `test/buffer_test.rb`
  - `test/dispatcher_test.rb`
  - `test/keymap_manager_test.rb`

## 既知の未実装 / 今後の仕様候補（現状）

- 永続 undo（`undofile` / `undodir` 相当）
- session 保存/復元（`-S` / `:mksession` 相当の実体）
- `:make` / `:cfile` / `:lfile` など quickfix 入口（`:grep` / `:lgrep` は実装済み）
- `:substitute` の `c`（confirm）フラグ（`g`, `i`, `I`, `n`, `e` は実装済み）
- `Ctrl-w` resize / close-others / equalize など window 操作拡張
- `:set` 高度構文（`+=`, `-=`, `:set all`, 短縮名）
- tag jump / folds / `:global` / `:normal`
- LSP / diagnostics / fuzzy finder など中長期機能
