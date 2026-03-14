# オペレータとモーション

> "Give me a lever long enough and a fulcrum on which to place it, and I shall move the world." — Archimedes

## この章で学ぶこと

- オペレータ + モーションの文法
- `d`（削除）、`y`（ヤンク）、`c`（変更）、`=`（インデント）
- ペースト操作

オペレータとモーションの組み合わせは、Vim 系エディタの最も強力な武器です。「何をするか」と「どこまでか」を分離することで、少数のコマンドの掛け合わせから無数の操作を生み出せます。一度この文法を体得すれば、新しいモーションを覚えるたびにすべてのオペレータと組み合わせられる — つまり知識が掛け算で増えていきます。

## オペレータ + モーション文法

Vim/RuVim の最も強力な概念の一つが「オペレータ + モーション」の文法です。

```
{operator}{motion}
```

オペレータ（何をするか）:

```
d    削除（delete）
y    ヤンク（コピー）
c    変更（削除して Insert mode）
=    自動インデント
```

モーション（どこまで）は第2章で学んだ移動コマンドです。

組み合わせの考え方:

```mermaid
flowchart LR
    Op["オペレータ\n(何をするか)"] --- Mul(("×"))
    Mul --- Mo["モーション\n(どこまで)"]
    Mo --- Eq(("="))
    Eq --- Result["操作"]

    style Op fill:#e8f4fd,stroke:#2196F3
    style Mo fill:#fff3e0,stroke:#FF9800
    style Result fill:#e8f5e9,stroke:#4CAF50
```

| オペレータ | × | モーション | = | 操作 |
|-----------|---|-----------|---|------|
| `d` (削除) | × | `w` (次の単語) | = | `dw` (次の単語まで削除) |
| `y` (ヤンク) | × | `$` (行末) | = | `y$` (行末までヤンク) |
| `c` (変更) | × | `iw` (単語内側) | = | `ciw` (単語を変更) |
| `=` (インデント) | × | `G` (末尾) | = | `=G` (末尾までインデント) |

## delete オペレータ

```
dw    次の単語の先頭まで削除
d$    行末まで削除（D と同じ）
d0    行頭まで削除
dj    現在行と次の行を削除
dk    現在行と前の行を削除
dh    左の1文字を削除
dl    右の1文字を削除（x と同じ）
dgg   現在行からバッファ先頭まで削除
dG    現在行からバッファ末尾まで削除
dd    現在行を削除（行全体）
```

カウント付き:

```
3dw   3単語分削除
2dd   2行削除
d3j   現在行 + 下3行を削除
```

## yank オペレータ

```
yy    現在行をヤンク
yw    次の単語の先頭までヤンク
y$    行末までヤンク（Y と同じ）
```

## change オペレータ

`c` は削除した後に Insert mode に入ります。

```
cw    次の単語までを変更
c$    行末まで変更（C と同じ）
cc    行全体を変更（S と同じ）
```

操作例 — 単語を書き換える:

```
Hello World
      ^（W の位置でカーソル）
cw
Universe
Esc
→ Hello Universe
```

## indent オペレータ

```
==    現在行を自動インデント
=j    現在行と次の行をインデント
=G    現在行からバッファ末尾までインデント
=gg   現在行からバッファ先頭までインデント
```

Ruby filetype ではネスト構造に基づく自動インデントが適用されます。

## 行単位のシフト

```
>>    現在行を右にシフト（shiftwidth 分）
<<    現在行を左にシフト（shiftwidth 分）
```

## ペースト

```
p    カーソルの後ろにペースト
P    カーソルの前にペースト
```

ヤンクしたテキストが行単位（linewise）の場合、`p` はカーソルの下の行にペーストし、`P` はカーソルの上の行にペーストします。

操作例 — 行の入れ替え:

```
line A
line B
（line A 上で）
dd      ← line A を削除（unnamed register に保存）
p       ← line B の下にペースト
→ line B
  line A
```

## 実践: Ruby メソッドのリファクタリング

オペレータとモーションを使った実際のリファクタリングのステップを追ってみましょう。

**課題**: メソッド名を変更し、不要な行を削除し、引数を追加する。

```ruby
# BEFORE:
def calc_price(items)
  subtotal = items.sum
  tax = subtotal * 0.1
  debug_log(subtotal)
  subtotal + tax
end
```

**ステップ 1**: メソッド名を変更 — `calc_price` の `c` にカーソルを置いて `cw`

```
（calc_price の c にカーソル）
cw                         ← 単語を変更
calculate_price            ← 新しい名前を入力
Esc
```

**ステップ 2**: debug_log の行を削除 — `debug_log` の行に移動して `dd`

```
（debug_log の行で）
dd                         ← 行を削除
```

**ステップ 3**: 引数を追加 — `items` の `)` の手前にカーソルを置いて `i`

```
（) の位置で）
i                          ← Insert mode
, tax_rate
Esc
```

```ruby
# AFTER:
def calculate_price(items, tax_rate)
  subtotal = items.sum
  tax = subtotal * 0.1
  subtotal + tax
end
```
