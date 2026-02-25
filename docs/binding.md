# RuVim キーバインディング一覧

## Normal mode

- `h` : 左へ移動
- `j` : 下へ移動
- `k` : 上へ移動
- `l` : 右へ移動
- `0` : 行頭へ移動
- `$` : 行末へ移動
- `^` : 行頭の最初の非空白へ移動
- `w` : 次の単語へ移動
- `b` : 前の単語へ移動
- `e` : 単語末へ移動
- `f{char}` / `F{char}` : 行内で次/前の文字へ移動
- `t{char}` / `T{char}` : 行内で文字の手前/直後へ移動
- `;` / `,` : 直前の `f/F/t/T` を再実行 / 逆方向再実行
- `%` : 対応する括弧へジャンプ（`()[]{}`）
- `gg` : バッファ先頭へ移動
- `G` : バッファ末尾へ移動
- `i` : Insert mode に入る
- `a` : カーソル後ろから Insert mode
- `A` : 行末から Insert mode
- `I` : 行頭の最初の非空白から Insert mode
- `o` : 下に新規行を開いて Insert mode
- `O` : 上に新規行を開いて Insert mode
- `:` : Command-line mode に入る
- `/` : 前方検索入力に入る
- `?` : 後方検索入力に入る
- `x` : カーソル位置の文字削除
- `dd` : 現在行を削除
- `d` + motion : operator-pending delete（`dw`, `dj`, `dk`, `d$`, `dh`, `dl`）
- `diw` / `daw` : 単語 text object delete（簡易）
- `di"` / `da"` : quote text object delete（簡易）
- `di)` / `da)` : paren text object delete（簡易）
- `di]` / `da]`, `di}` / `da}` : bracket / brace text object delete（簡易）
- ``di` `` / ``da` `` : backtick quote text object delete（簡易）
- `dip` / `dap` : paragraph text object delete（簡易）
- `yy` / `yw` : yank
- `yiw` / `yaw` : 単語 text object yank（簡易）
- `yi"` / `ya"` : quote text object yank（簡易）
- `yi)` / `ya)` : paren text object yank（簡易）
- `yi]` / `ya]`, `yi}` / `ya}`, ``yi` `` / ``ya` ``, `yip` / `yap`（簡易）
- `p` / `P` : paste
- `"a`, `"A`, `"_`, `"+`, `"*` + operator/paste : register 指定
- `m{a-zA-Z}` : mark を設定（小文字 local / 大文字 global）
- `'{mark}` / `` `{mark} `` : mark へ jump（行頭寄せ / 正確位置）
- `''` / `` `` `` : jumplist で前の位置へ jump（行頭寄せ / 正確位置）
- `r<char>` : 1文字置換
- `c` + motion / `cc` : change（削除して Insert mode）
- `ciw` / `caw` : 単語 text object change（簡易）
- `ci"` / `ca"` : quote text object change（簡易）
- `ci)` / `ca)` : paren text object change（簡易）
- `ci]` / `ca]`, `ci}` / `ca}`, ``ci` `` / ``ca` ``, `cip` / `cap`（簡易）
- `v` : Visual (characterwise)
- `V` : Visual (linewise)
- `Ctrl-w w` : 次の window へ移動
- `Ctrl-w h/j/k/l` : window 間移動（split UI）
- `u` : Undo
- `Ctrl-r` : Redo
- `.` : 直前変更の repeat（現状: `x`, `dd`, `d{motion}`, `p/P`, `r<char>`）
- `Ctrl-o` : jumplist の古い位置へ
- `Ctrl-i` : jumplist の新しい位置へ（端末では Tab と同じコード）
- `Ctrl-d` / `Ctrl-u` : 半ページ下/上へ移動（概ね表示高さの半分）
- `Ctrl-f` / `Ctrl-b` : 1ページ下/上へ移動（`PageDown` / `PageUp` 相当）
- `Ctrl-e` / `Ctrl-y` : カーソル位置をなるべく保ったまま画面を1行下/上へスクロール（最小実装）
- `q{reg}` : macro 記録開始/終了（再度 `q` で停止）
- `@{reg}` / `@@` : macro 再生 / 直前 macro 再生
- `n` : 直前検索を次へ
- `N` : 直前検索を前へ（逆方向）
- `*` / `#` : カーソル下の単語検索（前/後）
- `g*` / `g#` : カーソル下の単語を部分一致検索（前/後）
- `gf` : カーソル下のファイル名を開く（最小。`path` / `suffixesadd` を参照）
- `Esc` : メッセージ/保留入力のクリア
- `矢印キー` : 移動
- `PageUp` / `PageDown` : 画面単位で移動（概ね表示高さ - 1 行）
- `Enter` : quickfix / location list バッファ上では選択項目へジャンプ（一覧ウィンドウから元の編集ウィンドウへ戻る）

### count 対応（現状）

- `3j`, `5k`, `2x`, `3dd` など
- `0` は count ではなく行頭移動として扱う

## Insert mode

- `文字` : 挿入
- `Enter` : 改行
- `Backspace` : 削除
- `Ctrl-n` : buffer words 補完（次候補）
- `Ctrl-p` : buffer words 補完（前候補）
- `Esc` : Normal mode に戻る
- `Ctrl-c` : Normal mode に戻る
- `矢印キー` : 移動
- `PageUp` / `PageDown` : 画面単位で移動

## Visual mode（characterwise / linewise）

- `h/j/k/l`, `w/b/e`, `0/$/^`, `gg/G`, `矢印キー` : 範囲を伸縮
- `PageUp` / `PageDown` : 範囲を画面単位で伸縮
- `v` : characterwise Visual の開始/終了
- `V` : linewise Visual の開始/切替
- `y` : 選択範囲を yank
- `d` : 選択範囲を delete
- `i` / `a` + object : text object を選択（`iw`, `aw`, `ip`, `ap`, `i"`, `a"`, ``i` ``, ``a` ``, `i)`, `a)`, `i]`, `a]`, `i}`, `a}`）
- `Esc` / `Ctrl-c` : Normal mode に戻る

## Command-line mode

- `文字` : 入力
- `Enter` : Ex コマンド実行
- `Backspace` : 1文字削除
- `Up` / `Down` : 履歴移動
- `Left` / `Right` : カーソル移動
- `Tab` (`Ctrl-i`) : Ex 補完（`:` prefix 時、コマンド名/一部引数の文脈対応）
- `Esc` : キャンセル
- `Ctrl-c` : キャンセル

### prefix 別の Enter 動作

- `:` で始まる場合: Ex コマンドとして実行
- `/` で始まる場合: 前方検索
- `?` で始まる場合: 後方検索

## メモ

- 実装場所（初期バインド）: `lib/ruvim/app.rb`
- `d` は keymap の固定列ではなく operator-pending 状態機械で解釈
- keymap 解決順（現状実装）: `filetype-local -> buffer-local -> mode-local -> global`
- `~/.config/ruvim/init.rb`（または `$XDG_CONFIG_HOME/ruvim/init.rb`）の `nmap` / `imap` / `map_global` で上書き・追加可能
- `Ctrl-d/u/f/b/e/y` も、現在は「既定挙動の前に keymap override を試す」ため `nmap "<C-d>", ...` のように上書き可能
- `~/.config/ruvim/ftplugin/<filetype>.rb`（または `$XDG_CONFIG_HOME/ruvim/ftplugin/<filetype>.rb`）では `nmap` / `imap` が filetype-local として登録される
