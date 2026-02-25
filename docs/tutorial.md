# RuVim チュートリアル（使い方）

## 起動

このリポジトリは Ruby 標準ライブラリのみで動きます。

```bash
ruby -Ilib exe/ruvim
```

ファイルを指定しない起動では、Vim 風の `intro screen`（RuVim では intro 用の read-only 特殊バッファ）を表示します。
編集を始めると通常の空バッファに置き換わります。

ファイルを開いて起動:

```bash
ruby -Ilib exe/ruvim path/to/file.txt
```

### 起動オプション（Vim 風・現状）

- `--help`, `--version`
- `--clean`（ユーザー設定と ftplugin を読まない）
- `-R`（readonly で開く。現在バッファの `:w` を拒否）
- `-M`（modifiable off 相当。編集操作を拒否し、あわせて readonly）
- `-Z`（restricted mode。config/ftplugin を読まず、`:ruby` を無効化）
- `-n`（現状 no-op。将来の swap/永続機能向け互換フラグ）
- `-o[N]` / `-O[N]` / `-p[N]`（複数ファイルを split / vsplit / tab で開く）
- `-V[N]` / `--verbose[=N]`（起動/設定/Ex のログを stderr に出す）
- `--startuptime file.log`（起動フェーズの簡易 timing log を書く）
- `--cmd 'set number'`（user config 読み込み前に Ex 実行）
- `-u path/to/init.rb`（設定ファイルを指定）
- `-u NONE`（ユーザー設定を読まない）
- `-c 'set number'`（起動後に Ex 実行）
- `+10`（起動後に 10 行目へ移動）
- `+`（起動後に最終行へ移動）

例:

```bash
ruby -Ilib exe/ruvim --clean file.txt
ruby -Ilib exe/ruvim -R file.txt
ruby -Ilib exe/ruvim --cmd 'set number' -u /tmp/minimal_init.rb file.txt
ruby -Ilib exe/ruvim -u /tmp/minimal_init.rb -c 'set number' file.txt
ruby -Ilib exe/ruvim +10 file.txt
ruby -Ilib exe/ruvim -o a.rb b.rb
ruby -Ilib exe/ruvim -O a.rb b.rb
ruby -Ilib exe/ruvim -p a.rb b.rb
```

## 基本操作

### Normal mode

- `h` 左
- `j` 下
- `k` 上
- `l` 右
- `0` 行頭
- `$` 行末
- `^` 行頭の最初の非空白
- `w` 次の単語へ
- `b` 前の単語へ
- `e` 単語末へ
- `f<char>`, `F<char>` 行内文字移動
- `t<char>`, `T<char>` 行内「手前/直後」移動
- `;`, `,` 直前の `f/F/t/T` を繰り返し / 逆方向
- `%` 対応括弧ジャンプ（`()[]{}`）
- `gg` 先頭へ
- `G` 末尾へ
- `i` Insert mode
- `a`, `A`, `I` 挿入開始位置を変えて Insert mode
- `o`, `O` 行を開いて Insert mode
- `:` Command-line mode
- `/` 前方検索
- `?` 後方検索
- `x` 文字削除
- `dd` 行削除
- `d` + motion（例: `dw`, `dj`, `d$`）
- `yy`, `yw` yank
- `p`, `P` paste
- `r<char>` 1文字置換（例: `rx`）
- `v`, `V` Visual mode
- `c` + motion / `cc` change（削除して Insert mode）
- `u` undo
- `Ctrl-r` redo
- `.` 直前変更の繰り返し（現状は `x`, `dd`, `d{motion}`, `p/P`, `r<char>`）
- `n` 検索を次へ
- `N` 検索を前へ
- `3j` など count 対応（一部コマンド）

### Insert mode

- 文字入力で挿入
- `Enter` で改行
- `Backspace` で削除
- `Esc` で Normal mode に戻る
- `Ctrl-c` でも Normal mode に戻る（終了しない）

### Command-line mode（Ex 風）

- `:` を押すと最下段で入力
- `Enter` で実行
- `Esc` でキャンセル
- `Up/Down` で履歴
- `Tab` で Ex 補完（`:` のとき。コマンド名/一部引数）

使えるコマンド:

- `:w`
- `:w path/to/file.txt`
- `:q`
- `:q!`
- `:wq`
- `:e other.txt`
- `:e!`（現在ファイルを再読込）
- `:e! other.txt`（未保存変更を破棄して開く）
- `:help`
- `:help regex`, `:help options`, `:help w`（topic 指定）
- `:commands`
- `:command Name ex_body`
- `:command! Name ex_body`
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

## Undo / Redo

- `u`: 直前の変更を取り消す
- `Ctrl-r`: 取り消した変更をやり直す

現状の undo 粒度:

- Normal mode の `x`, `dd` などは 1 コマンド = 1 undo
- Insert mode は `i` で入って `Esc` / `Ctrl-c` で抜けるまでを 1 undo として扱う

## 検索

- `/foo` : 前方検索
- `?foo` : 後方検索
- `n` : 同方向に繰り返し
- `N` : 逆方向に繰り返し
- `*` / `#` : カーソル下の単語を検索
- `g*` / `g#` : カーソル下の単語を部分一致検索

検索は command-line の入力欄を再利用しています（prefix が `:` ではなく `/` または `?` になる）。
検索パターンは Ruby 正規表現です（例: `/foo\d+/` 相当なら `foo\d+` を入力）。

### substitute（最小）

- `:%s/foo/bar/g`
- バッファ全体に対して置換（Ruby 正規表現 + Ruby の置換文字列）

## `d` + motion（operator-pending）

使える例（現状）:

- `dd` : 行削除
- `dw` : 次の単語先頭まで削除
- `dj` : 現在行 + 次行を削除
- `dk` : 現在行 + 前行を削除
- `d$` : 行末まで削除
- `dh` / `dl` : 左右の文字削除
- `diw` / `daw` : 単語 text object（簡易）
- `di"` / `da"` : ダブルクォート text object（簡易）
- `di)` / `da)` : 丸括弧 text object（簡易）
- `di]` / `da]`, `di}` / `da}` : bracket / brace text object（簡易）
- ``di` `` / ``da` `` : backtick quote text object（簡易）
- `dip` / `dap` : paragraph text object（簡易）

## yank / paste / replace

- `yy` : 現在行を yank
- `yw` : 単語方向に yank
- `yi]`, `yi}`, ``yi` ``, `yip` など text object yank（簡易）
- `p` : カーソル後ろに paste
- `P` : カーソル前に paste
- `r<char>` : カーソル位置の1文字を置換

register prefix を付けると register を指定できます。

- `"ayy` : register `a` に行 yank
- `"Ayy` : register `a` に追記 yank
- `"_dd` : black hole register に捨てる（unnamed/numbered を汚さない）
- `yy` の結果は register `0` にも入る
- `dd` / `d{motion}` の結果は register `1-9` に回転保存される（簡易）
- `"+p` : system clipboard を paste（backend が使える環境）
- `"*p` : system clipboard register `*` を paste（backend が使える環境）

## Mark / Jump list

- `ma` : local mark `a` を設定
- `mA` : global mark `A` を設定
- `'a` : mark `a` の行へジャンプ（先頭の非空白）
- `` `a `` : mark `a` の正確な位置へジャンプ
- `Ctrl-o` / `Ctrl-i` : jump list を戻る / 進む（`Ctrl-i` は Tab と同じコード）

## Macro

- `qa` : macro を register `a` に記録開始
- `q` : 記録停止
- `@a` : macro `a` を再生
- `@@` : 直前 macro を再生

## Options（`:set`）

- `:set number` / `:set nonumber` : 行番号表示の ON/OFF（window-local）
- `:set relativenumber` / `:set norelativenumber` : 相対行番号（window-local）
- `:set ignorecase` / `:set noignorecase` : 検索の大文字小文字を無視（global）
- `:set smartcase` / `:set nosmartcase` : `ignorecase` 有効時に大文字を含む検索を大文字小文字区別にする（global）
- `:set hlsearch` / `:set nohlsearch` : 検索ハイライトの ON/OFF（global）
- `:set tabstop=4` : tab 幅設定（既定スコープは buffer-local）
- `:setlocal number` : 現在 window のみ変更
- `:setglobal tabstop=8` : global 値を変更
- `:set` : 現在の option 一覧を表示（簡易）

## change operator（`c`）

- `cw` : 単語方向に change
- `cc` : 行を change
- `c$` : 行末まで change
- `ciw`, `caw` : 単語 text object を change（簡易）
- `ci]`, `ca}`, ``ci` ``, `cip`, `cap` なども利用可（簡易）

`c` は削除後に Insert mode に入ります。

## Visual mode

- `v` : characterwise Visual
- `V` : linewise Visual
- 移動して範囲を選択
- `y` : yank
- `d` : delete
- `i` / `a` + object : text object を選択（例: `vi"`, `va)`, `viw`, `vip`, `vi]`, ``vi` ``）
- `Esc` / `Ctrl-c` : キャンセル（Normal mode に戻る）

## ユーザー定義 Ex コマンド（`:command`）

例:

```vim
:command Hi help
:Hi
```

既存名を置き換える場合は `!` を使います。

```vim
:command! Hi commands
```

## Ruby 実行（`:ruby` / `:rb`）

例:

```vim
:ruby buffer.line_count
:rb [window.cursor_y, window.cursor_x]
```

`ctx`, `editor`, `buffer`, `window` を参照できます。

## 画面まわり（現状）

- 端末リサイズに追従（`SIGWINCH` + `select` 起床 + 毎描画でサイズ再取得）
- カーソル文字は反転表示される（端末カーソルに加えて視認性向上）
- 同サイズ時は簡易差分描画で更新量を減らす
- タブ/全角文字の表示幅はベースライン対応（完全互換ではない）

## Unicode 幅の設定（現状）

- `RUVIM_AMBIGUOUS_WIDTH=2` を設定すると、曖昧幅文字（例: 一部ギリシャ文字など）を幅2として扱います

例:

```bash
RUVIM_AMBIGUOUS_WIDTH=2 ruby -Ilib exe/ruvim
```

## バッファ管理

- `:ls` / `:buffers` で一覧表示
- `:bnext`, `:bprev` で巡回
- `:buffer 2` のように ID 指定で切替
- `:buffer foo.txt` のように名前指定で切替
- `:buffer #` で直前バッファへ戻る
- `:bnext!`, `:bprev!`, `:buffer! ...` で未保存変更を無視して切替

## 複数 window / split（現状）

- `:split` : 上下に分割
- `:vsplit` : 左右に分割
- `Ctrl-w w` : 次の window へ
- `Ctrl-w h/j/k/l` : 方向移動（簡易タイル前提）

各 window はカーソル位置とスクロール位置を独立に持ちます。

## Tabpage（現状）

- `:tabnew` : 新しいタブを作成
- `:tabnew path/to/file` : ファイルを開いたタブを作成
- `:tabnext` / `:tabn` : 次のタブへ
- `:tabprev` / `:tabp` : 前のタブへ

タブごとに split レイアウトと current window が保持されます。

## 設定ファイル（XDG）

起動時に以下を読み込みます（存在する場合）。

- `$XDG_CONFIG_HOME/ruvim/init.rb`
- `XDG_CONFIG_HOME` 未設定時は `~/.config/ruvim/init.rb`

例:

```ruby
nmap "H", "cursor.left"
nmap "L", "cursor.right"

command "user.say_hi" do |ctx, **|
  ctx.editor.echo("hi from rc")
end

ex_command_call "Hi", "user.say_hi"
```

利用できる主な DSL:

- `nmap`, `imap`
- `map_global`
- `command`
- `ex_command`
- `ex_command_call`

## テスト実行

```bash
ruby -Ilib:test -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
```

## コマンド設計の見方

RuVim では、ユーザーが入力する Ex コマンド名（例: `:w`）と、内部の処理を分けています。

- Ex 名: `w`, `q`, `write`, `quit`
- 実処理: `RuVim::GlobalCommands` のメソッド（例: `file_write`, `app_quit`）

この分離で、ヘルプ・補完・引数チェックを後から足しやすくしています。

## Builtin Ex コマンドを追加する

`lib/ruvim/app.rb` の `register_builtins!` に Ex 登録を追加します。

例: `:bn`（次バッファ）を追加する場合のイメージ

```ruby
register_ex_unless(ex, "bn", call: :buffer_next, desc: "Next buffer", nargs: 0)
```

次に `lib/ruvim/global_commands.rb` に実装を追加します。

```ruby
def buffer_next(ctx, **)
  # TODO: buffer list から次へ移動
end
```

## Normal mode のキーバインドを追加する

`lib/ruvim/app.rb` の `bind_default_keys!` で定義します。

例: `H` を `cursor.left` に割り当てる:

```ruby
@keymaps.bind(:normal, "H", "cursor.left")
```

複数キー列も使えます（現状 `dd` のような連続入力）。

```ruby
@keymaps.bind(:normal, "dd", "buffer.delete_line")
```

## キーマップのレイヤー（現状 API）

`RuVim::KeymapManager` は以下の登録 API を持ちます。

- `bind(:normal, ...)` : mode-local
- `bind_global(...)`
- `bind_buffer(buffer_id, ...)`
- `bind_filetype("rb", ...)`

解決順は `filetype -> buffer -> mode -> global` です。

## ftplugin（filetype ごとの設定）

RuVim は buffer の path から `filetype` を簡易検出し、初回表示時に ftplugin を読み込みます。

- XDG: `~/.config/ruvim/ftplugin/<filetype>.rb`（または `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`）

ftplugin の中では `nmap` / `imap` が filetype-local として登録されます。`setlocal` も使えます。

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb
nmap "K", "search.word_forward"
setlocal "tabstop=2"
```

## シンタックスハイライト（最小）

- filetype が `ruby` / `json` のとき、最小の regex ベース色付けを行います
- `search` / `cursor` / `visual` の強調が優先されるため、構文色は上書きされることがあります

## 補完（現状の基礎）

- Command-line (`:`)
  - `Tab` (`Ctrl-i`) で補完
  - コマンド名に加え、`set` 系 option / `:e` `:w` の path / `:buffer` 引数を一部補完
- Insert mode
  - `Ctrl-n` : buffer words 補完（次候補）
  - `Ctrl-p` : buffer words 補完（前候補）

## Symbol と Proc の使い分け

RuVim のコマンド定義は `Symbol` と `Proc` の両方に対応しています。

### Symbol（推奨: builtin）

```ruby
cmd.register("cursor.left", call: :cursor_left, desc: "Move cursor left")
```

利点:

- 一覧化しやすい
- ヘルプに載せやすい
- 実装の場所が追いやすい

### Proc（推奨: 実験・拡張）

```ruby
ex.register("Hello", call: ->(ctx, **) { ctx.editor.echo("hello") }, desc: "Demo", nargs: 0)
```

利点:

- その場定義しやすい
- プラグイン/設定向き

## 次の拡張候補（おすすめ順）

1. シンタックスハイライト（最小）
2. 補完基盤（Ex 引数 / buffer word）
3. Undo/Redo
4. buffer-local keymap
5. `:command` でユーザー定義 Ex コマンド
6. `:ruby` で Ruby 実行
