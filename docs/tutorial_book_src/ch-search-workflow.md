# 検索ワークフロー

> "If you can't find it, you can't fix it." — Software Engineering Proverb

## この章で学ぶこと

- quickfix list と location list
- `:vimgrep` / `:grep` による検索
- `:filter` による絞り込み
- スペルチェック

バグの原因を追いかけるとき、リファクタリングで影響範囲を確認するとき、検索ワークフローが武器になります。quickfix list を使えば、プロジェクト全体の検索結果を一覧にして、一つずつ確認しながらジャンプできます。手動でファイルを開いて grep するよりも格段に速く、見落としも減ります。

## quickfix list

quickfix list は検索結果やエラー一覧を保持するリストです。

```
:vimgrep /pattern/     開いているバッファ群から検索して quickfix に
:copen                 quickfix list を表示
:cnext (:cn)           次の項目へジャンプ
:cprev (:cp)           前の項目へジャンプ
:cclose                quickfix list を閉じる
```

Normal mode のショートカット:

```
Q      :copen 相当
]q     :cnext 相当
[q     :cprev 相当
Enter  quickfix バッファ上で選択項目へジャンプ
```

実践例 — プロジェクト内の TODO を確認:

```
:grep TODO lib/*.rb          ← lib 以下の Ruby ファイルから TODO を検索
Q                            ← quickfix list を開く
（結果の一覧が表示される）
Enter                        ← 選択した結果へジャンプ
]q                           ← 次の結果へジャンプ
[q                           ← 前の結果へ戻る
```

## location list

location list はウィンドウローカルな quickfix list です。

```
:lvimgrep /pattern/    現在バッファ内を検索して location list に
:lopen                 location list を表示
:lnext (:ln)           次の項目へジャンプ
:lprev (:lp)           前の項目へジャンプ
:lclose                location list を閉じる
```

## 外部 grep

```
:grep pattern [files...]     外部 grep を実行 → quickfix
:lgrep pattern [files...]    外部 grep を実行 → location list
```

grep プログラムは `grepprg` オプションで設定できます（デフォルト: `grep -nH`）。

操作例:

```
:grep TODO *.rb          Ruby ファイルから TODO を検索
:grep -i error lib/**    lib 以下を case-insensitive 検索
```

ワイルドカードは Ruby の `Dir.glob` で展開されます。

## `:filter` による絞り込み

```
/pattern     まず検索
g/           マッチ行のフィルタバッファを作成
```

フィルタバッファでは:

- `Enter` で元バッファの該当行へジャンプ
- 再度 `g/` で再帰的に絞り込み
- `:q` で閉じて戻る

## スペルチェック

```
:set spell     スペルチェック有効化
]s             次のスペルミスへ
[s             前のスペルミスへ
:set nospell   無効化
```
