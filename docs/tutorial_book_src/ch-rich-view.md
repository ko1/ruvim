# Rich View モード

> "The purpose of visualization is insight, not pictures." — Ben Shneiderman

## この章で学ぶこと

- TSV/CSV のテーブル表示
- Markdown のリッチ表示
- JSON/JSONL の整形表示
- 画像表示

データはそのままの形式で読むよりも、適切に整形して表示した方が理解しやすくなります。[Rich View](#index:Rich View) モードは、TSV/CSV をテーブルに、Markdown をリッチテキストに、JSON をインデント付きで表示します。データファイルを「見る」だけなら、わざわざ別のツールを起動する必要はありません。

## Rich View の起動

```
gr          Normal mode でトグル
:rich       Ex コマンドでトグル
:rich tsv   形式を明示指定
:rich csv
```

Rich mode ではバッファ内容を変更せず、描画パイプラインで整形表示します。

## TSV/CSV テーブル表示

TSV/CSV ファイルで Rich View を有効にすると、カラムが整列されたテーブルとして表示されます。

- 区切り表示: ` | `（スペース+パイプ+スペース）
- 列幅は画面に見えている行だけから計算（大規模ファイルでも高速）
- CJK 文字の表示幅を正確に計算

操作例:

```
（data.tsv を開いた状態で）
gr     ← テーブル表示に切り替え
（移動・検索・yank は通常通り使える）
Esc    ← Normal mode に戻る
```

表示イメージ:

```
# 元の TSV データ:
name	age	city
Alice	30	Tokyo
Bob	25	Osaka

# Rich View 表示:
name  | age | city
Alice | 30  | Tokyo
Bob   | 25  | Osaka
```

## Markdown リッチ表示

Markdown ファイルで Rich View を有効にすると:

- 見出し（H1-H6）: レベル別の太字 + 色
- インライン装飾: `**太字**`, `*斜体*`, `` `コード` ``, `[リンク](url)`, チェックボックス
- コードブロック: フェンスで囲まれた部分を暖色表示
- テーブル: 列幅揃え + box-drawing 罫線（`│`, `─`, `┼`）
- 水平線（HR）: `─` 線に置換
- ブロック引用: `>` 行を cyan 表示
- 画像: sixel 対応ターミナルでは画像を表示

## JSON/JSONL 整形表示

JSON ファイルで Rich View を有効にすると、ミニファイ JSON を整形して読み取り専用バッファに表示します。

JSONL（1行1JSON）ファイルでは、各行を個別にパース・整形し、`---` セパレータで区切って表示します。

仮想バッファ方式なので、`Esc` / `Ctrl-C` で元のバッファに戻れます。

## 画像表示

画像ファイル（PNG/JPG/GIF/BMP/WEBP）を開くと、自動的に Rich View として表示されます。[sixel](#index:sixel) 対応ターミナルでは画像がインライン表示されます。

> [!NOTE]
> sixel に対応したターミナル（例: WezTerm, foot, mlterm）が必要です。非対応ターミナルでは画像のメタ情報のみ表示されます。

```
:e photo.png     画像ファイルを開く
```

sixel の制御:

```
:set sixel=auto    自動検出（デフォルト）
:set sixel=on      強制有効
:set sixel=off     無効
```

## Rich mode での操作

Rich mode 中は:

- 移動・検索・yank 等は通常通り使える
- バッファを変更する操作（insert/delete/change/paste/replace）はブロックされる
- statusline に `-- RICH --` と表示
