# Exコマンド全一覧

| コマンド | エイリアス | 説明 |
|---------|-----------|------|
| `:w [path]` | `:write` | 保存 |
| `:q[\!]` | `:quit` | 終了 |
| `:qa[\!]` | `:qall` | 全終了 |
| `:wq[\!] [path]` | — | 保存して終了 |
| `:wqa[\!]` | `:wqall`, `:xa`, `:xall` | 全保存して終了 |
| `:e[\!] [path]` | `:edit` | ファイルを開く / 再読み込み |
| `:r [file]` | `:read` | ファイル/コマンド出力を挿入 |
| `:w \!cmd` | — | バッファをコマンドにパイプ |
| `:\!cmd` | — | シェルコマンド実行 |
| `:run [cmd]` | — | コマンド実行 + 結果バッファ |
| `:help [topic]` | — | ヘルプ表示 |
| `:commands` | — | Ex コマンド一覧 |
| `:bindings [mode]` | — | キーバインド一覧 |
| `:command[\!] Name body` | — | ユーザー定義 Ex コマンド |
| `:ruby code` | `:rb` | Ruby 実行 |
| `:ls` | `:buffers` | バッファ一覧 |
| `:bnext[\!]` | `:bn` | 次バッファ |
| `:bprev[\!]` | `:bp` | 前バッファ |
| `:buffer[\!] id\|name\|#` | `:b` | バッファ切替 |
| `:bdelete[\!] [id]` | `:bd` | バッファ削除 |
| `:split` | — | 水平分割 |
| `:vsplit` | — | 垂直分割 |
| `:tabnew [path]` | — | 新タブ |
| `:tabnext` | `:tabn` | 次タブ |
| `:tabprev` | `:tabp` | 前タブ |
| `:tabs` | — | タブ一覧 |
| `:args` | — | arglist 表示 |
| `:next` | — | arglist 次 |
| `:prev` | — | arglist 前 |
| `:first` | — | arglist 最初 |
| `:last` | — | arglist 最後 |
| `:{range}d [count]` | `:delete` | 行削除 |
| `:{range}y [count]` | `:yank` | 行ヤンク |
| `:{range}p` | `:print` | 行表示 |
| `:{range}nu` | `:number` | 行番号付き表示 |
| `:{range}m {addr}` | `:move` | 行移動 |
| `:{range}t {addr}` | `:copy`, `:co` | 行コピー |
| `:{range}j` | `:join` | 行結合 |
| `:{range}>` | — | 右シフト |
| `:{range}<` | — | 左シフト |
| `:{range}normal {keys}` | `:norm` | 各行で Normal コマンド |
| `:{range}s/pat/repl/[flags]` | — | 置換 |
| `:[range]g/pat/cmd` | `:global` | マッチ行に実行 |
| `:[range]v/pat/cmd` | `:vglobal` | 非マッチ行に実行 |
| `:nohlsearch` | `:noh` | 検索ハイライトクリア |
| `:vimgrep /pat/` | — | バッファ群検索 → quickfix |
| `:lvimgrep /pat/` | — | 現在バッファ検索 → location list |
| `:grep pat [files]` | — | 外部 grep → quickfix |
| `:lgrep pat [files]` | — | 外部 grep → location list |
| `:copen` / `:cclose` | — | quickfix list 開/閉 |
| `:cnext` / `:cprev` | `:cn` / `:cp` | quickfix 移動 |
| `:lopen` / `:lclose` | — | location list 開/閉 |
| `:lnext` / `:lprev` | `:ln` / `:lp` | location list 移動 |
| `:filter [/pat/]` | — | フィルタバッファ作成 |
| `:rich [format]` | — | Rich mode トグル |
| `:follow` | — | follow mode トグル |
| `:set [option]` | — | オプション設定 |
| `:setlocal [option]` | — | ローカル設定 |
| `:setglobal [option]` | — | グローバル設定 |
| `:git subcmd [args]` | — | Git 連携 |
| `:gh subcmd [args]` | — | GitHub 連携 |
