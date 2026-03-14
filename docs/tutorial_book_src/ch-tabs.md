# タブページ

> "A place for everything, and everything in its place." — Benjamin Franklin

## この章で学ぶこと

- タブの作成と移動
- CLI からの複数タブ起動

[ウィンドウ分割](ch-windows.md)は「同時に見比べたいファイル」に向いていますが、[タブ](#index:タブページ)は「作業のコンテキストを切り替える」のに適しています。たとえば、「機能Aの実装」タブと「機能Bのレビュー」タブを分けておけば、頭の切り替えもスムーズです。

## タブの操作

```
:tabnew          新しいタブを作成
:tabnew file.txt ファイルを開いた新しいタブを作成
:tabnext         次のタブへ（:tabn）
:tabprev         前のタブへ（:tabp）
:tabs            タブ一覧を表示
```

タブが2つ以上あるとき、statusline に `tab:n/m` と表示されます。

## タブを閉じる

```
:q     最後のウィンドウなら現在タブを閉じる
```

## CLI からのタブ起動

```bash
ruvim -p file1.txt file2.txt file3.txt
```

`-p` で各ファイルを別タブで開きます。

分割で開く場合:

```bash
ruvim -o file1.txt file2.txt    # 水平分割
ruvim -O file1.txt file2.txt    # 垂直分割
```

## タブとウィンドウの関係

各タブは独立した:

- ウィンドウリスト
- 現在ウィンドウ
- 分割レイアウト

を持ちます。[バッファ](ch-buffers.md)はタブ間で共有されます。
