# テキストオブジェクト

> "Simplicity is the ultimate sophistication." — Leonardo da Vinci

## この章で学ぶこと

- `iw`/`aw`（単語）
- `ip`/`ap`（段落）
- 引用符やカッコのテキストオブジェクト

テキストオブジェクトは「カーソルが構造の中にあるだけで、その構造全体を選択できる」という画期的な仕組みです。プログラミングでは括弧や引用符で囲まれた構造を頻繁に操作しますが、テキストオブジェクトを使えば「開始位置に移動して、終了位置まで範囲指定して...」という手順が一発で済みます。

## テキストオブジェクトとは

テキストオブジェクトは「構造化された範囲」を指定するモーションの一種です。`i` は "inner"（内側）、`a` は "a"（外側、区切り文字を含む）を意味します。

## 単語オブジェクト

```
iw    単語（inner word）— 単語本体のみ
aw    単語（a word）— 前後の空白を含む
```

操作例:

```
Hello, World\!
       ^（W の位置）
diw → Hello, \!         （World だけ削除）
daw → Hello,\!          （World と前の空白も削除）
```

## 段落オブジェクト

```
ip    段落（inner paragraph）— 空行に囲まれた段落
ap    段落（a paragraph）— 後続の空行を含む
```

## 引用符オブジェクト

```
i"    ダブルクォートの内側
a"    ダブルクォートを含む範囲
i`    バッククォートの内側
a`    バッククォートを含む範囲
```

操作例:

```
puts "Hello, World\!"
            ^（o の位置）
ci"           ← 引用符の中身を変更
Goodbye
Esc
→ puts "Goodbye"
```

## カッコオブジェクト

```
i)    丸括弧の内側（ i( と同じ ）
a)    丸括弧を含む範囲
i]    角括弧の内側
a]    角括弧を含む範囲
i}    波括弧の内側
a}    波括弧を含む範囲
```

操作例:

```
calculate(x + y)
           ^（カーソルが中に）
di)    → calculate()        （中身だけ削除）
da)    → calculate          （括弧ごと削除）
yi)    → x + y がヤンクされる
ci)    → calculate() の中身を書き換え可能
```

## 実践: HTML タグ内の編集

テキストオブジェクトはコード編集で威力を発揮します。

```html
<\!-- BEFORE -->
<div class="container">
  <p>古いテキスト</p>
</div>
```

`古いテキスト` の中にカーソルがあるとき:

```
ci"           ← class 属性値を変更（" の中にカーソルがある場合）
wrapper
Esc
→ <div class="wrapper">
```

## 実践: 関数の引数を丸ごと書き換え

```python
# BEFORE:
result = process_data(old_arg1, old_arg2, old_arg3)

# 括弧内のどこかにカーソルがある状態で:
ci)
new_arg1, new_arg2
Esc

# AFTER:
result = process_data(new_arg1, new_arg2)
```

## オペレータとの組み合わせ一覧

| 操作 | 意味 |
|------|------|
| `diw` | 単語を削除 |
| `yiw` | 単語をヤンク |
| `ciw` | 単語を変更 |
| `di"` | 引用符内を削除 |
| `ci"` | 引用符内を変更 |
| `da)` | 括弧ごと削除 |
| `ci}` | 波括弧内を変更 |
| `dap` | 段落を削除 |
| `yip` | 段落をヤンク |
