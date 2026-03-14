# テキストの入力と基本編集

> "The scariest moment is always just before you start." — Stephen King

## この章で学ぶこと

- Insert mode への入り方のバリエーション
- 基本的な削除操作
- 保存操作
- Undo / Redo

テキストを入力できなければエディタとは呼べません。この章では Insert mode の多彩な入り方と、「間違えたら戻す」ための Undo/Redo を学びます。Insert mode への入り方を使い分けるだけで、無駄なカーソル移動がぐっと減ります。

## Insert mode への入り方

```
i    カーソル位置の前から挿入
a    カーソル位置の後ろから挿入
I    行頭の最初の非空白文字から挿入
A    行末から挿入
o    現在行の下に新しい行を開いて挿入
O    現在行の上に新しい行を開いて挿入
```

操作例 — 行末にセミコロンを追加:

```
console.log("hello")
（Normal mode で A を押す）
;
Esc
→ console.log("hello");
```

操作例 — 行の間に新しい行を追加:

```
line 1
line 3
（line 1 の上で o を押す）
line 2
Esc
→ line 1
  line 2
  line 3
```

実践例 — Ruby メソッドに引数を追加:

```ruby
# BEFORE:
def greet(name)
  puts "Hello, #{name}"
end

# name の後にカーソルを置いて a を押し、", greeting" を入力:
# AFTER:
def greet(name, greeting)
  puts "Hello, #{name}"
end
```

## Insert mode での操作

```
文字入力     テキストを挿入
Enter       改行
Backspace   1文字削除（行頭ではインデント削除 or 前の行と結合）
Ctrl-n      buffer words 補完（次候補）
Ctrl-p      buffer words 補完（前候補）
Esc         Normal mode に戻る
Ctrl-c      Normal mode に戻る
矢印キー     カーソル移動
```

## 基本の削除操作（Normal mode）

```
x     カーソル位置の1文字を削除
X     カーソルの前の1文字を削除
dd    現在行を削除
D     カーソルから行末まで削除
```

カウント付き:

```
3x     3文字削除
3dd    3行削除
```

## その他の編集コマンド

```
s     カーソル位置の1文字を削除して Insert mode（substitute）
S     行全体を削除して Insert mode
J     現在行と次の行を結合
r{c}  カーソル位置の1文字を {c} に置換
~     カーソル位置の文字の大文字/小文字を切り替え
```

操作例 — 文字の置換:

```
Hello
^（カーソルが H 上）
rh
→ hello
```

## 保存

```
:w              現在のバッファを保存
:w filename     指定したファイル名で保存
:wq             保存して終了
:wqa            全バッファ保存して終了
```

## Undo / Redo

```
u       直前の変更を取り消す（Undo）
Ctrl-r  取り消した変更をやり直す（Redo）
```

Undo の粒度:

- Normal mode のコマンド（`x`, `dd` など）: 1コマンド = 1 undo 単位
- Insert mode: 入ってから出るまでの全入力 = 1 undo 単位

操作例:

```
（元の状態）Hello, World\!
dd           → （行が消える）
u            → Hello, World\!（元に戻る）
Ctrl-r       → （また行が消える）
u            → Hello, World\!（再び戻る）
```

## 永続 Undo

RuVim はデフォルトで undo 履歴をファイルに保存します。エディタを閉じて再度開いても、undo/redo が使えます。

```
:set undofile       有効化（デフォルトで有効）
:set noundofile     無効化
```

undo ファイルの保存先: `~/.local/share/ruvim/undo/`（`undodir` オプションで変更可能）
