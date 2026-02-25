# RuVim コマンド一覧

## 起動オプション（CLI, 現状）

- `--help`, `--version`
- `--clean`
- `-u {path|NONE}`
- `-c {cmd}`
- `+{cmd}`, `+{line}`, `+`

## Ex コマンド（builtin）

### `:w` / `:write`

- 形式: `:w [path]`
- 現在バッファを保存
- `path` 指定時はそのパスに保存
- `!` 対応: `:w!`（現状は保存メッセージに反映、権限昇格などは未実装）

### `:q` / `:quit`

- 形式: `:q`, `:q!`
- エディタ終了
- 未保存変更がある場合、`!` なしでは拒否

### `:wq`

- 形式: `:wq`, `:wq!`, `:wq [path]`
- 保存して終了

### `:e` / `:edit`

- 形式: `:e[!] [path]`
- 引数あり: 別ファイルを開く
- 引数なし: 現在ファイルを再読込
- 未保存変更がある場合は `!` なしで拒否
- `:e!` は未保存変更を破棄して開き直す（undo/redo もクリア）

### `:help`

- 形式: `:help [topic]`
- help 用の read-only バッファを開く（仮想バッファ）
- 例:
  - `:help`
  - `:help regex`
  - `:help options`
  - `:help w`

### `:commands`

- 形式: `:commands`
- Ex コマンド一覧（alias 含む）を read-only バッファに表示

### `:command`

- 形式: `:command Name ex_body`
- 形式: `:command! Name ex_body`（上書き）
- ユーザー定義 Ex コマンドを追加
- `:command`（引数なし）でユーザー定義コマンド一覧を表示

### `:ruby` / `:rb`

- 形式: `:ruby <code>`
- 形式: `:rb <code>`
- Ruby コードを評価し、返り値をステータスに表示
- 利用可能: `ctx`, `editor`, `buffer`, `window`

### `:ls` / `:buffers`

- 形式: `:ls`
- 形式: `:buffers`
- バッファ一覧をステータスに表示
- `%=current`, `#=alternate`, `+=modified` のフラグを含む

### `:bnext` / `:bn`

- 形式: `:bnext`
- 次のバッファへ切替
- `!` 対応（未保存変更を無視して切替）

### `:bprev` / `:bp`

- 形式: `:bprev`
- 前のバッファへ切替
- `!` 対応（未保存変更を無視して切替）

### `:buffer` / `:b`

- 形式: `:buffer <id|name|#>`
- バッファ ID / 名前 / `#`（alternate）で切替
- `!` 対応（未保存変更を無視して切替）

### `:split`

- 形式: `:split`
- 現在 window を水平分割（簡易タイル）
- 同じ buffer を新しい window に表示

### `:vsplit`

- 形式: `:vsplit`
- 現在 window を垂直分割（簡易タイル）
- 同じ buffer を新しい window に表示

### `:tabnew`

- 形式: `:tabnew [path]`
- 新しいタブを作成
- `path` 指定時はそのファイルを開く

### `:tabnext` / `:tabn`

- 形式: `:tabnext`
- 次のタブへ移動

### `:tabprev` / `:tabp`

- 形式: `:tabprev`
- 前のタブへ移動

## 内部コマンド（主なもの）

内部コマンドは主に key binding から使われ、`RuVim::CommandRegistry` に登録されます。

- `cursor.left`
- `cursor.right`
- `cursor.up`
- `cursor.down`
- `cursor.line_start`
- `cursor.line_end`
- `cursor.first_nonblank`
- `cursor.buffer_start`
- `cursor.buffer_end`
- `cursor.word_forward`
- `cursor.word_backward`
- `cursor.word_end`
- `mode.insert`
- `mode.append`
- `mode.append_line_end`
- `mode.insert_nonblank`
- `mode.open_below`
- `mode.open_above`
- `mode.visual_char`
- `mode.visual_line`
- `window.split`
- `window.vsplit`
- `window.focus_next`
- `window.focus_left`
- `window.focus_right`
- `window.focus_up`
- `window.focus_down`
- `tab_new`
- `tab_next`
- `tab_prev`
- `mode.command_line`
- `mode.search_forward`
- `mode.search_backward`
- `buffer.delete_char`
- `buffer.delete_line`
- `buffer.delete_motion`
- `buffer.change_motion`
- `buffer.change_line`
- `buffer.yank_line`
- `buffer.yank_motion`
- `buffer.paste_after`
- `buffer.paste_before`
- `buffer.visual_yank`
- `buffer.visual_delete`
- `buffer.undo`
- `buffer.redo`
- `search.next`
- `search.prev`
- `editor.buffer_next`
- `editor.buffer_prev`
- `buffer.replace_char`
- `ui.clear_message`

## 検索コマンド（Normal mode）

検索は Ex コマンドではなく、command-line prefix `/` `?` を使う入力経路です。

- `/pattern` : 前方検索
- `?pattern` : 後方検索
- `n` : repeat
- `N` : reverse repeat
- `*` / `#` : カーソル下の単語検索（単語境界）
- `g*` / `g#` : カーソル下の単語検索（部分一致）

### `:%s/.../.../g`（最小実装）

- バッファ全体置換
- Ruby 正規表現 + Ruby 置換文字列を利用
- `g` フラグ対応（全置換）

## Operator-pending（Normal mode）

現状は delete / yank operator を実装:

- `d` + motion
- `y` + motion（現状 `yy`, `yw`）
- `c` + motion / `cc`
- 実装の内部コマンド: `buffer.delete_motion`
- `dd` は linewise delete として扱う

### text object（現状）

- `iw`, `aw`, `i"`, `a"`, `i)`, `a)`（簡易）
- `d`, `y`, `c` から利用可能
- Visual mode からも利用可能（選択更新）

## Visual mode

- `v` / `V` で characterwise / linewise Visual mode
- `buffer.visual_yank`
- `buffer.visual_delete`

## レジスタ（現状）

- unnamed register（`"`）、named register（`"a`..`"z`）、append（`"A`..`"Z`）
- `"+`, `"*` は system clipboard register（利用可能環境のみ）
- delete / yank で更新
- `p`, `P` で paste（register prefix 対応）

## Option / Ex（現状）

- `:set`, `:setlocal`, `:setglobal`
- 現状の接続済み option:
  - `number`（window-local / 行番号表示）
  - `relativenumber`（window-local / 相対行番号）
  - `ignorecase` / `smartcase` / `hlsearch`（global / 検索系）
  - `tabstop`（buffer-local / タブ展開幅）
  - `filetype`（buffer-local / 自動検出 + ftplugin 用）

## 実装ポリシー

- Ex コマンド名（`:w` など）と内部コマンド名（`file_write` / `buffer.undo` など）を分離
- builtin は `Symbol` ベースで `RuVim::GlobalCommands` のメソッドに実装
- 拡張用に `Proc` の登録も可能
- key binding は `KeymapManager` の layered resolution（filetype / buffer / mode / global）で解決
- XDG 設定ファイル（`$XDG_CONFIG_HOME/ruvim/init.rb` または `~/.config/ruvim/init.rb`）から `ConfigDSL` 経由で command / ex command / key binding を追加可能

## UI メモ（現状）

- `Screen` は行キャッシュを使った簡易差分描画を行う
- `SIGWINCH` + self-pipe + `IO.select` で入力待機中でもリサイズに即追従
- command-line は履歴と Ex 補完（コマンド名 + 一部引数の文脈補完）を持つ
- Insert mode は `Ctrl-n` / `Ctrl-p` の buffer words 補完を持つ
- 文字幅は `DisplayWidth` の近似実装（tab 展開 + 一部全角幅2）

## テスト（現状）

- `Minitest`
- `test/buffer_test.rb`
- `test/dispatcher_test.rb`
- `test/keymap_manager_test.rb`
