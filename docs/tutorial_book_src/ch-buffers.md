# バッファ管理

> "Order and simplification are the first steps toward the mastery of a subject." — Thomas Mann

## この章で学ぶこと

- バッファの一覧と切り替え
- arglist（引数リスト）
- `hidden` オプション

実際のプロジェクトでは、ソースコード、テスト、設定ファイルなど多数のファイルを同時に扱います。[バッファ](#index:バッファ)管理を理解すると、開いたファイルを閉じずにメモリに保持したまま自由に行き来できるようになり、「あのファイルどこだっけ」と迷うことがなくなります。

> [!TIP]
> バッファは「メモリ上のファイル」、[ウィンドウ](ch-windows.md)は「バッファの表示窓」、[タブ](ch-tabs.md)は「ウィンドウレイアウトの集合」です。この3つの関係を理解すると複数ファイルの扱いが楽になります。

## バッファとは

RuVim ではファイルを開くと「バッファ」として管理されます。バッファは画面に表示されていなくてもメモリ上に保持できます。

## バッファ一覧

```
:ls        バッファ一覧を表示
:buffers   :ls と同じ
```

表示例:

```
  1 %a + "file1.txt"
  2 #    "file2.txt"
  3      "file3.txt"
```

フラグ: `%` = 現在, `#` = 直前, `+` = 変更あり

## バッファ切り替え

```
:bnext       次のバッファへ（:bn）
:bprev       前のバッファへ（:bp）
:buffer 2    バッファ ID 2 へ切替（:b 2）
:buffer #    直前のバッファへ切替
:buffer foo  名前に "foo" を含むバッファへ切替
```

未保存変更がある場合:

```
:bnext\!      変更を無視して切替
:buffer\! 2   変更を無視して切替
```

## バッファの削除

```
:bdelete     現在バッファを一覧から削除（:bd）
:bdelete\!    未保存変更を破棄して削除
:bdelete 3   バッファ ID 3 を削除
```

## arglist（引数リスト）

起動時に複数ファイルを指定すると arglist が初期化されます。

```bash
ruvim file1.txt file2.txt file3.txt
```

```
:args        arglist を表示（現在のファイルは [filename] 形式）
:next        arglist の次のファイルへ
:prev        arglist の前のファイルへ
:first       arglist の最初へ
:last        arglist の最後へ
```

## `hidden` オプション

```
:set hidden    未保存バッファを残したまま別バッファに移動可能に
```

> [!IMPORTANT]
> [`hidden`](#index:hidden) を有効にすると、未保存バッファがあっても `!` なしで他のバッファに切り替えられます。複数ファイルを扱うなら[設定ファイル](ch-config.md)で有効化しておくことを強くお勧めします。

## `autowrite` オプション

```
:set autowrite    バッファ切替時に変更があれば自動保存
```
