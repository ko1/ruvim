# RuVim 完全ガイド — チュートリアルブック

> Ruby で書かれた Vim ライクなターミナルエディタ「RuVim」の包括的なチュートリアルです。
> 基本操作から応用テクニック、カスタマイズまで、サンプルを交えて解説します。

---

# 第I部: はじめの一歩

---

## 第1章: RuVimとは

### この章で学ぶこと

- RuVim の概要とインストール方法
- 起動と終了の方法
- モードの概念

### 1.1 RuVim の概要

RuVim は Ruby で実装された Vim ライクなターミナルエディタです。Ruby 標準ライブラリのみで動作し、Vim の操作感を維持しつつ、Ruby ネイティブな拡張性を備えています。

主な特徴:

- Vim 互換のモーダル編集（Normal / Insert / Visual / Command-line モード）
- Ruby DSL による設定とプラグイン
- 26 言語のシンタックスハイライト
- TSV/CSV/Markdown/JSON/画像の Rich View モード
- Git / GitHub 連携
- ストリーム連携（stdin パイプ、`:run`、`:follow`）

### 1.2 インストール

RuVim は gem としてインストールできます。

```bash
gem install ruvim
```

開発環境で直接実行する場合:

```bash
ruby -Ilib exe/ruvim
```

### 1.3 起動

ファイルを指定して起動:

```bash
ruvim file.txt
```

ファイル指定なしで起動すると、Vim 風の intro screen が表示されます:

```bash
ruvim
```

複数ファイルを開く:

```bash
ruvim file1.txt file2.txt file3.txt
```

レイアウトを指定して複数ファイルを開く:

```bash
ruvim -o file1.txt file2.txt    # 水平分割
ruvim -O file1.txt file2.txt    # 垂直分割
ruvim -p file1.txt file2.txt    # タブ
```

特定の行から開く:

```bash
ruvim +10 file.txt              # 10行目へジャンプ
ruvim + file.txt                # 最終行へジャンプ
ruvim file.txt:10               # path:line 形式でも可
ruvim file.txt:10:5             # path:line:col 形式
```

### 1.4 モードの概念

RuVim は Vim と同様に「モーダル」なエディタです。モードによってキーの意味が変わります。

| モード | 説明 | 入り方 | 抜け方 |
|--------|------|--------|--------|
| Normal | カーソル移動・コマンド実行 | `Esc` | — |
| Insert | テキスト入力 | `i`, `a`, `o` など | `Esc`, `Ctrl-c` |
| Visual | 範囲選択 | `v`, `V`, `Ctrl-v` | `Esc`, `Ctrl-c` |
| Command-line | Ex コマンド入力 | `:`, `/`, `?` | `Enter`(実行), `Esc`(取消) |
| Rich | 構造化データ閲覧 | `gr`, `:rich` | `Esc`, `Ctrl-c` |

起動直後は **Normal mode** です。

### 1.5 終了

```
:q        通常終了（未保存変更があるとエラー）
:q!       強制終了（未保存変更を破棄）
:wq       保存して終了
:qa       全ウィンドウ/タブを閉じて終了
:qa!      強制的に全終了
:wqa      全バッファ保存して終了
```

操作例 — ファイルを開いて保存して終了:

```
$ ruvim hello.txt
（Normal mode で）
i                    ← Insert mode に入る
Hello, RuVim!        ← テキストを入力
Esc                  ← Normal mode に戻る
:wq Enter            ← 保存して終了
```

### 1.6 サスペンド

全モード共通で `Ctrl-z` を押すとシェルに戻ります（サスペンド）。`fg` で復帰できます。

---

## 第2章: 基本の移動

### この章で学ぶこと

- h/j/k/l による移動
- 行頭・行末への移動
- 単語単位の移動
- バッファの先頭・末尾への移動
- スクロール操作
- カウントの使い方

### 2.1 基本の4方向移動

Normal mode での基本移動:

```
h    左へ移動
j    下へ移動
k    上へ移動
l    右へ移動
```

矢印キーも使えます。

操作例:

```
Hello, World!
^（カーソルここ）

l l l l l l
      ^（6回 l を押すとカンマの後の空白へ）
```

### 2.2 行内の移動

```
0    行の先頭（列0）へ移動
$    行の末尾へ移動
^    行頭の最初の非空白文字へ移動
```

操作例 — インデントされた行での動き:

```
    def hello
    ^（^ で d の位置へ）
^（0 で先頭の空白へ）
               ^（$ で末尾へ）
```

### 2.3 単語単位の移動

```
w    次の単語の先頭へ
b    前の単語の先頭へ
e    現在の単語（または次の単語）の末尾へ
```

操作例:

```
def calculate_total(items)
^
w → calculate_total(items) の c へ
w → ( へ
w → items の i へ
b → ( へ（戻る）
e → f へ（def の末尾）
```

### 2.4 バッファの先頭・末尾

```
gg   バッファの先頭行へ移動
G    バッファの末尾行へ移動
```

カウント付き:

```
10gg    10行目へ移動
10G     10行目へ移動
```

### 2.5 スクロール

```
Ctrl-d    半ページ下へスクロール
Ctrl-u    半ページ上へスクロール
Ctrl-f    1ページ下へスクロール（PageDown）
Ctrl-b    1ページ上へスクロール（PageUp）
Ctrl-e    カーソルを保ったまま1行下へスクロール
Ctrl-y    カーソルを保ったまま1行上へスクロール
```

カーソル行の画面位置を制御:

```
zt    カーソル行を画面の上端に
zz    カーソル行を画面の中央に
zb    カーソル行を画面の下端に
```

`PageUp` / `PageDown` キーも使えます。

### 2.6 カウント（数値プレフィックス）

多くのコマンドは数値プレフィックスを受け付けます。

```
5j     5行下へ
3w     3単語先へ
10k    10行上へ
2Ctrl-d  2×半ページ下へ
```

注意: `0` は行頭移動として扱われ、カウントの一部にはなりません。

---

## 第3章: テキストの入力と基本編集

### この章で学ぶこと

- Insert mode への入り方のバリエーション
- 基本的な削除操作
- 保存操作
- Undo / Redo

### 3.1 Insert mode への入り方

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

### 3.2 Insert mode での操作

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

### 3.3 基本の削除操作（Normal mode）

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

### 3.4 その他の編集コマンド

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

### 3.5 保存

```
:w              現在のバッファを保存
:w filename     指定したファイル名で保存
:wq             保存して終了
:wqa            全バッファ保存して終了
```

### 3.6 Undo / Redo

```
u       直前の変更を取り消す（Undo）
Ctrl-r  取り消した変更をやり直す（Redo）
```

Undo の粒度:

- Normal mode のコマンド（`x`, `dd` など）: 1コマンド = 1 undo 単位
- Insert mode: 入ってから出るまでの全入力 = 1 undo 単位

操作例:

```
（元の状態）Hello, World!
dd           → （行が消える）
u            → Hello, World!（元に戻る）
Ctrl-r       → （また行が消える）
u            → Hello, World!（再び戻る）
```

### 3.7 永続 Undo

RuVim はデフォルトで undo 履歴をファイルに保存します。エディタを閉じて再度開いても、undo/redo が使えます。

```
:set undofile       有効化（デフォルトで有効）
:set noundofile     無効化
```

undo ファイルの保存先: `~/.local/share/ruvim/undo/`（`undodir` オプションで変更可能）

---

## 第4章: ファイルを開いて編集する

### この章で学ぶこと

- `:e` でファイルを開く
- `:r` でファイル内容を挿入する
- `:!` でシェルコマンドを実行する
- `:help` でヘルプを見る
- `Ctrl-z` でサスペンドする

### 4.1 ファイルを開く

```
:e path/to/file.txt     ファイルを開く
:e! path/to/file.txt    未保存変更を破棄して開く
:e!                     現在ファイルを再読み込み（undo/redo クリア）
```

`path:line` 形式でファイルを開くと指定行にジャンプ:

```
:e app.rb:42            42行目にジャンプして開く
:e app.rb:42:10         42行目10列にジャンプして開く
```

大きいファイル（デフォルト閾値以上）は先頭部分を先に表示し、残りをバックグラウンドで読み込みます。statusline に `[load]` と表示されます。

### 4.2 ファイル内容やコマンド出力の挿入

```
:r file.txt             ファイルの内容をカーソル行の下に挿入
:r !ls                  ls コマンドの出力をカーソル行の下に挿入
:3r file.txt            3行目の下に挿入
```

### 4.3 バッファ内容をコマンドに渡す

```
:w !wc -l               バッファ全体の行数をカウント
:'<,'>w !sort           選択範囲をソートコマンドに渡す
```

### 4.4 シェルコマンドの実行

```
:!ls                    ls を実行（画面を一時的に抜ける）
:!ruby %                現在のファイルを Ruby で実行（% はファイル名に展開）
```

実行後「Press ENTER or type command to continue」と表示されるので、`Enter` を押してエディタに戻ります。

より高度な実行には `:run` コマンドが使えます:

```
:run ruby %             Ruby で実行し、出力を [Shell Output] バッファに表示
:run                    直前のコマンドを再実行（または runprg の値を使用）
```

`:run` は PTY 経由でリアルタイムにストリーム表示し、`Ctrl-C` で停止できます。

### 4.5 ヘルプ

```
:help                   ヘルプバッファを開く
:help regex             正規表現のヘルプ
:help options           オプションのヘルプ
:help w                 :w コマンドのヘルプ
```

### 4.6 サスペンドと復帰

`Ctrl-z` は全モード共通でシェルにサスペンドします。`fg` で RuVim に復帰します。

```
（RuVim 操作中に Ctrl-z）
$ fg    ← RuVim に復帰
```

---

# 第II部: 効率的な編集

---

## 第5章: オペレータとモーション

### この章で学ぶこと

- オペレータ + モーションの文法
- `d`（削除）、`y`（ヤンク）、`c`（変更）、`=`（インデント）
- ペースト操作

### 5.1 オペレータ + モーション文法

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

### 5.2 delete オペレータ

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

### 5.3 yank オペレータ

```
yy    現在行をヤンク
yw    次の単語の先頭までヤンク
y$    行末までヤンク（Y と同じ）
```

### 5.4 change オペレータ

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

### 5.5 indent オペレータ

```
==    現在行を自動インデント
=j    現在行と次の行をインデント
=G    現在行からバッファ末尾までインデント
=gg   現在行からバッファ先頭までインデント
```

Ruby filetype ではネスト構造に基づく自動インデントが適用されます。

### 5.6 行単位のシフト

```
>>    現在行を右にシフト（shiftwidth 分）
<<    現在行を左にシフト（shiftwidth 分）
```

### 5.7 ペースト

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

---

## 第6章: テキストオブジェクト

### この章で学ぶこと

- `iw`/`aw`（単語）
- `ip`/`ap`（段落）
- 引用符やカッコのテキストオブジェクト

### 6.1 テキストオブジェクトとは

テキストオブジェクトは「構造化された範囲」を指定するモーションの一種です。`i` は "inner"（内側）、`a` は "a"（外側、区切り文字を含む）を意味します。

### 6.2 単語オブジェクト

```
iw    単語（inner word）— 単語本体のみ
aw    単語（a word）— 前後の空白を含む
```

操作例:

```
Hello, World!
       ^（W の位置）
diw → Hello, !         （World だけ削除）
daw → Hello,!          （World と前の空白も削除）
```

### 6.3 段落オブジェクト

```
ip    段落（inner paragraph）— 空行に囲まれた段落
ap    段落（a paragraph）— 後続の空行を含む
```

### 6.4 引用符オブジェクト

```
i"    ダブルクォートの内側
a"    ダブルクォートを含む範囲
i`    バッククォートの内側
a`    バッククォートを含む範囲
```

操作例:

```
puts "Hello, World!"
            ^（o の位置）
ci"           ← 引用符の中身を変更
Goodbye
Esc
→ puts "Goodbye"
```

### 6.5 カッコオブジェクト

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

### 6.6 オペレータとの組み合わせ一覧

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

---

## 第7章: 行内の高速移動

### この章で学ぶこと

- `f`/`F`/`t`/`T` による行内文字検索
- `;` と `,` による繰り返し
- `%` による括弧マッチング

### 7.1 行内文字検索

```
f{char}    行内で次の {char} へ移動（on）
F{char}    行内で前の {char} へ移動（on）
t{char}    行内で次の {char} の手前へ移動（till）
T{char}    行内で前の {char} の直後へ移動（till）
```

操作例:

```
def calculate_total(items, tax)
^
f(    → ( へ移動
fi    → items の i へ移動
```

### 7.2 繰り返しと逆方向

```
;    直前の f/F/t/T を同方向に繰り返す
,    直前の f/F/t/T を逆方向に繰り返す
```

操作例:

```
one, two, three, four
^
f,    → 最初のカンマへ
;     → 2番目のカンマへ
;     → 3番目のカンマへ
,     → 2番目のカンマへ（逆方向）
```

### 7.3 オペレータとの組み合わせ

`f/t` はモーションなのでオペレータと組み合わせられます。

```
df)    ) まで削除（) を含む）
dt)    ) の手前まで削除（) は残る）
cf,    , まで変更
```

### 7.4 括弧マッチング

```
%    対応する括弧へジャンプ（(), [], {}）
```

操作例:

```
if (x > 0) {
   ^（( の位置）
%  → ) へジャンプ
%  → ( へ戻る
```

カーソルが `{` 上にあれば対応する `}` へ、`}` 上にあれば対応する `{` へジャンプします。

---

## 第8章: 検索と置換

### この章で学ぶこと

- `/` と `?` による検索
- `n`/`N` による検索の繰り返し
- `*`/`#` によるカーソル下単語の検索
- `:substitute` による置換
- `:global` / `:vglobal`

### 8.1 検索

```
/pattern    前方検索（下方向）
?pattern    後方検索（上方向）
n           同方向に次のマッチへ
N           逆方向に次のマッチへ
```

検索パターンは Ruby 正規表現です。

操作例:

```
/def        "def" を前方検索
n           次の "def" へ
N           前の "def" へ
/\d+        数字の連続を検索
/TODO|FIXME TODO または FIXME を検索
```

検索ハイライトを一時的に消す:

```
:nohlsearch    （または :noh）
```

### 8.2 カーソル下単語の検索

```
*     カーソル下の単語を前方検索（単語境界つき）
#     カーソル下の単語を後方検索（単語境界つき）
g*    カーソル下の単語を前方検索（部分一致）
g#    カーソル下の単語を後方検索（部分一致）
```

操作例 — 変数の使用箇所を探す:

```
total = items.sum
^（total にカーソル）
*        → 次の "total" へジャンプ（単語境界つき）
n        → さらに次の "total" へ
```

### 8.3 検索オプション

```
:set ignorecase      大文字小文字を無視
:set smartcase       ignorecase 有効時、大文字を含むパターンは case-sensitive
:set hlsearch        マッチをハイライト表示（デフォルト有効）
:set incsearch       入力中にインクリメンタル検索
```

### 8.4 置換 (`:substitute`)

基本形:

```
:s/old/new/           現在行の最初のマッチを置換
:s/old/new/g          現在行の全マッチを置換
:%s/old/new/g         バッファ全体の全マッチを置換
:10,20s/old/new/g     10-20行の全マッチを置換
:'<,'>s/old/new/g     Visual 選択範囲の全マッチを置換
```

フラグ:

```
g    行内の全マッチを置換（グローバル）
i    大文字小文字を無視
I    大文字小文字を区別
n    置換せずマッチ数を表示
e    マッチなし時のエラーを抑制
c    確認モード（y/n/a/q/l/Esc で対話的に判断）
```

操作例 — 確認付き置換:

```
:%s/foo/bar/gc
```

各マッチで `y`（置換する）、`n`（スキップ）、`a`（残り全部置換）、`q`（中止）、`l`（これだけ置換して終了）を選べます。

操作例 — Ruby 正規表現の利用:

```
:%s/(\w+), (\w+)/\2, \1/g     引数の順番を入れ替え
:%s/\bfoo\b/bar/g              単語境界つきで置換
```

### 8.5 `:global` / `:vglobal`

パターンにマッチする行（またはしない行）に対して Ex コマンドを実行します。

```
:g/pattern/command      マッチ行にコマンドを実行
:v/pattern/command      非マッチ行にコマンドを実行
:g!/pattern/command     :v と同じ
```

操作例:

```
:g/TODO/d               TODO を含む行を全削除
:v/important/d          important を含まない行を全削除
:g/^$/d                 空行を全削除
:g/pattern/p            マッチ行を表示（hit-enter prompt）
:g/def/normal A;        def を含む行の末尾にセミコロン追加
```

`:global` の undo は一括です — 1回の `u` で全変更が元に戻ります。

---

## 第9章: Visual mode

### この章で学ぶこと

- 文字単位・行単位・ブロック単位の選択
- 選択範囲に対する操作
- テキストオブジェクトによる選択

### 9.1 Visual mode の3種類

```
v        文字単位の選択（characterwise）
V        行単位の選択（linewise）
Ctrl-v   矩形選択（blockwise）
```

### 9.2 文字単位の選択（`v`）

```
v        選択開始
（移動キーで範囲を広げる）
y        選択範囲をヤンク
d        選択範囲を削除
=        選択範囲を自動インデント
Esc      選択解除
```

操作例 — 単語を選択してヤンク:

```
Hello, World!
^
v        ← 選択開始
e        ← 単語末まで（Hello を選択）
y        ← ヤンク
```

### 9.3 行単位の選択（`V`）

```
V        行選択開始
j/k      行を追加/削除
d        選択行を全削除
y        選択行をヤンク
```

操作例 — 3行削除:

```
V        ← 現在行を選択
jj       ← 下2行も選択
d        ← 3行削除
```

### 9.4 矩形選択（`Ctrl-v`）

```
Ctrl-v   矩形選択開始
h/j/k/l  矩形を調整
y        矩形範囲をヤンク
d        矩形範囲を削除
```

### 9.5 Visual mode でのテキストオブジェクト

Visual mode 中にテキストオブジェクトを使うと、選択範囲がそのオブジェクトに更新されます。

```
v        ← 選択開始
iw       ← 単語を選択
```

操作例 — 括弧の中身を選択してヤンク:

```
func(arg1, arg2)
       ^（カーソルが中に）
vi)      ← 括弧の中身を選択（arg1, arg2）
y        ← ヤンク
```

### 9.6 Visual mode でのインデント

```
V        行選択
jj       範囲を広げる
>>       右にシフト
<<       左にシフト
=        自動インデント
```

Visual 選択中の `>` や `<` で範囲のインデントを調整できます。

---

## 第10章: ドットリピート・マクロ・レジスタ

### この章で学ぶこと

- `.` による直前操作の繰り返し
- マクロの記録と再生
- レジスタの使い方

### 10.1 ドットリピート（`.`）

`.` は直前の変更コマンドを繰り返します。

対応コマンド:

- `x`, `dd`, `d{motion}`
- `p`, `P`
- `r{char}`
- `i`/`a`/`A`/`I`/`o`/`O` + Insert 入力
- `cc`, `c{motion}`

操作例 — 複数の行末にセミコロンを追加:

```
console.log("hello")
console.log("world")
console.log("!")

（1行目で）
A;Esc     ← 行末に ; を追加
j.        ← 次の行で繰り返す
j.        ← さらに次の行で繰り返す
```

操作例 — 同じ単語を次々と削除:

```
/word     ← 検索
dw        ← 最初の word を削除
n.        ← 次のマッチに移動して削除
n.        ← さらに次も
```

### 10.2 マクロ

マクロは一連のキー操作を記録し、再生する仕組みです。

```
q{reg}    レジスタ {reg} にマクロ記録開始
（操作を実行）
q         記録停止
@{reg}    マクロ {reg} を再生
@@        直前のマクロを再生
```

レジスタは `a`-`z`, `A`-`Z`（追記）, `0`-`9` が使えます。

操作例 — 各行を括弧で囲むマクロ:

```
hello
world
foo

（1行目で）
qa        ← レジスタ a に記録開始
I(Esc     ← 行頭に ( を挿入
A)Esc     ← 行末に ) を挿入
j         ← 次の行へ
q         ← 記録停止

@a        ← 2行目で再生
@@        ← 3行目で再生（直前マクロ）
```

カウント付きの再生:

```
10@a      マクロ a を10回再生
```

### 10.3 レジスタ

RuVim にはテキストを保存する複数のレジスタがあります。

| レジスタ | 説明 |
|----------|------|
| `""` | unnamed register（デフォルト） |
| `"a`-`"z` | 名前付きレジスタ |
| `"A`-`"Z` | 名前付きレジスタに追記 |
| `"0` | 最後の yank 内容 |
| `"1`-`"9` | delete/change 履歴（回転） |
| `"_` | ブラックホール（捨てる） |
| `"+` | システムクリップボード |
| `"*` | システムクリップボード |

レジスタの指定:

```
"ayy      レジスタ a に行をヤンク
"Ayy      レジスタ a に追記ヤンク
"ap       レジスタ a からペースト
"+yy      システムクリップボードに行をヤンク
"+p       システムクリップボードからペースト
"_dd      行を削除するが、どのレジスタにも保存しない
```

操作例 — 2つのテキストを入れ替え:

```
（テキスト A の単語上で）
"adiw     ← レジスタ a にヤンクして削除
（テキスト B の単語上で）
"bdiw     ← レジスタ b にヤンクして削除
"aP       ← レジスタ a をペースト（元の B の位置に A が入る）
（元の A の位置に移動）
"bP       ← レジスタ b をペースト（元の A の位置に B が入る）
```

---

## 第11章: マークとジャンプリスト

### この章で学ぶこと

- マークの設定とジャンプ
- ジャンプリストの活用

### 11.1 マークの設定

```
m{a-z}    バッファローカルマークを設定（小文字）
m{A-Z}    グローバルマークを設定（大文字）
```

小文字マークはバッファごとに独立です。大文字マークは全バッファ共通で、別のバッファにいても一発でジャンプできます。

### 11.2 マークへのジャンプ

```
'{mark}     マーク行の先頭非空白文字へジャンプ（行単位）
`{mark}     マークの正確な位置へジャンプ
```

操作例:

```
（重要なコードの行で）
ma           ← マーク a を設定

（別の場所に移動して作業...）

'a           ← マーク a の行へ戻る
`a           ← マーク a の正確な位置へ戻る
```

### 11.3 ジャンプリスト

`gg`, `G`, 検索、バッファ切替などの「大きな移動」はジャンプリストに記録されます。

```
Ctrl-o    前の位置へ戻る（older）
Ctrl-i    次の位置へ進む（newer）
''        行単位で前の位置へ戻る
``        正確な位置で前の位置へ戻る
```

注意: ターミナルでは `Ctrl-i` と `Tab` は同じキーコードです。

操作例 — 定義とリファレンスを行き来する:

```
（関数の呼び出し箇所にいる）
*            ← カーソル下の単語を検索（ジャンプ）
（定義を確認）
Ctrl-o       ← 元の位置に戻る
```

---

## 第12章: その他の便利な編集コマンド

### この章で学ぶこと

- 1文字操作（`r`, `~`, `s`, `S`）
- 行結合（`J`）
- `gf` によるファイルジャンプ
- 範囲コマンド
- `:filter` によるフィルタリング

### 12.1 1文字操作

```
r{char}    カーソル位置の文字を {char} に置換
~          大文字/小文字切り替え
s          カーソル位置を削除して Insert mode
S          行全体を削除して Insert mode（cc と同じ）
X          カーソル前の1文字を削除
```

### 12.2 行結合

```
J    現在行と次の行をスペースで結合
```

操作例:

```
Hello,
World!
（Hello, の行で J）
→ Hello, World!
```

### 12.3 `gf` — ファイルジャンプ

```
gf    カーソル下のファイル名を開く
```

- `file:line` 形式で開くと指定行にジャンプ
- `file:line:col` 形式で開くと指定行・桁にジャンプ
- `http://` / `https://` で始まる URL はブラウザで開く
- Markdown では `[text](path)` のリンクを認識

`path` オプションと `suffixesadd` オプションでファイル探索ディレクトリと拡張子補完を設定できます。

### 12.4 範囲コマンド

Ex コマンドには行範囲を指定できます。

```
:10,20d           10-20行を削除
:10,20y           10-20行をヤンク
:10,20s/a/b/g     10-20行で置換
:.,$d             現在行から最終行まで削除
:1,.d             先頭行から現在行まで削除
:%d               バッファ全体を削除（% は 1,$ の略）
:'<,'>d           Visual 選択範囲を削除
```

その他の範囲コマンド:

```
:{range}m {addr}    行を {addr} の後ろに移動
:{range}t {addr}    行を {addr} の後ろにコピー
:{range}j           行を結合
:{range}>           右シフト
:{range}<           左シフト
:{range}normal {keys}   各行で Normal mode コマンドを実行
```

操作例 — 範囲の行を末尾に移動:

```
:5,10m$     5-10行を末尾に移動
:5,10t0     5-10行を先頭にコピー
```

### 12.5 `g/` — フィルタバッファ

`g/` キーバインド（または `:filter`）は、検索パターンにマッチする行だけを集めたフィルタバッファを作成します。

```
/pattern         まず検索
g/               マッチ行のフィルタバッファを作成

:filter /TODO/   パターンを指定してフィルタ
```

- フィルタバッファ上で `Enter` を押すと、元バッファの該当行にジャンプ
- フィルタバッファ上で再度 `g/` を使うと再帰的に絞り込み可能
- `:q` でフィルタバッファを閉じて前のバッファに戻る

### 12.6 スペルチェック

```
:set spell       スペルチェックを有効化
]s               次のスペルミスへジャンプ
[s               前のスペルミスへジャンプ
:set nospell     無効化
```

`gitcommit` filetype ではデフォルトで有効です。辞書は `/usr/share/dict/words` を使用します。

---

# 第III部: 複数ファイルとワークフロー

---

## 第13章: バッファ管理

### この章で学ぶこと

- バッファの一覧と切り替え
- arglist（引数リスト）
- `hidden` オプション

### 13.1 バッファとは

RuVim ではファイルを開くと「バッファ」として管理されます。バッファは画面に表示されていなくてもメモリ上に保持できます。

### 13.2 バッファ一覧

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

### 13.3 バッファ切り替え

```
:bnext       次のバッファへ（:bn）
:bprev       前のバッファへ（:bp）
:buffer 2    バッファ ID 2 へ切替（:b 2）
:buffer #    直前のバッファへ切替
:buffer foo  名前に "foo" を含むバッファへ切替
```

未保存変更がある場合:

```
:bnext!      変更を無視して切替
:buffer! 2   変更を無視して切替
```

### 13.4 バッファの削除

```
:bdelete     現在バッファを一覧から削除（:bd）
:bdelete!    未保存変更を破棄して削除
:bdelete 3   バッファ ID 3 を削除
```

### 13.5 arglist（引数リスト）

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

### 13.6 `hidden` オプション

```
:set hidden    未保存バッファを残したまま別バッファに移動可能に
```

`hidden` が有効だと、`:e` や `:buffer` で未保存変更があっても `!` なしで切り替えられます。

### 13.7 `autowrite` オプション

```
:set autowrite    バッファ切替時に変更があれば自動保存
```

---

## 第14章: ウィンドウ分割

### この章で学ぶこと

- 水平/垂直分割
- ウィンドウ間の移動
- ウィンドウのサイズ調整とクローズ
- ネスト分割

### 14.1 ウィンドウの分割

```
:split       水平分割（上下）
:vsplit      垂直分割（左右）
```

分割すると、同じバッファを2つのウィンドウで表示します。それぞれ独立したカーソル位置とスクロール位置を持ちます。

別のファイルを分割して開くには:

```
:split other.txt
:vsplit other.txt
```

### 14.2 ウィンドウ間の移動

```
Ctrl-w w     次のウィンドウへ
Ctrl-w h     左のウィンドウへ
Ctrl-w j     下のウィンドウへ
Ctrl-w k     上のウィンドウへ
Ctrl-w l     右のウィンドウへ
```

`Shift+矢印キー` でも移動できます（1ウィンドウのときは自動で分割）。

### 14.3 ウィンドウのクローズ

```
Ctrl-w c     現在ウィンドウを閉じる
:q           現在ウィンドウを閉じる（最後のウィンドウなら終了）
Ctrl-w o     他の全ウィンドウを閉じる
```

### 14.4 ウィンドウのサイズ調整

```
Ctrl-w +     高さを増やす
Ctrl-w -     高さを減らす
Ctrl-w >     幅を増やす
Ctrl-w <     幅を減らす
Ctrl-w =     全ウィンドウのサイズを均等化
```

### 14.5 分割方向の制御

```
:set splitbelow     :split 時に下に分割
:set splitright     :vsplit 時に右に分割
```

### 14.6 ネスト分割

RuVim はツリー構造のレイアウトをサポートしています。`:vsplit` 後に `:split` すると、右ウィンドウだけが上下に分割されます。

```
┌───────┬───────┐
│       │ upper │
│ left  ├───────┤    ← vsplit 後に右で split
│       │ lower │
└───────┴───────┘
```

同方向の連続分割は自動的にフラット化されます。

---

## 第15章: タブページ

### この章で学ぶこと

- タブの作成と移動
- CLI からの複数タブ起動

### 15.1 タブの操作

```
:tabnew          新しいタブを作成
:tabnew file.txt ファイルを開いた新しいタブを作成
:tabnext         次のタブへ（:tabn）
:tabprev         前のタブへ（:tabp）
:tabs            タブ一覧を表示
```

タブが2つ以上あるとき、statusline に `tab:n/m` と表示されます。

### 15.2 タブを閉じる

```
:q     最後のウィンドウなら現在タブを閉じる
```

### 15.3 CLI からのタブ起動

```bash
ruvim -p file1.txt file2.txt file3.txt
```

`-p` で各ファイルを別タブで開きます。

分割で開く場合:

```bash
ruvim -o file1.txt file2.txt    # 水平分割
ruvim -O file1.txt file2.txt    # 垂直分割
```

### 15.4 タブとウィンドウの関係

各タブは独立した:

- ウィンドウリスト
- 現在ウィンドウ
- 分割レイアウト

を持ちます。バッファはタブ間で共有されます。

---

## 第16章: 検索ワークフロー

### この章で学ぶこと

- quickfix list と location list
- `:vimgrep` / `:grep` による検索
- `:filter` による絞り込み
- スペルチェック

### 16.1 quickfix list

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

### 16.2 location list

location list はウィンドウローカルな quickfix list です。

```
:lvimgrep /pattern/    現在バッファ内を検索して location list に
:lopen                 location list を表示
:lnext (:ln)           次の項目へジャンプ
:lprev (:lp)           前の項目へジャンプ
:lclose                location list を閉じる
```

### 16.3 外部 grep

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

### 16.4 `:filter` による絞り込み

```
/pattern     まず検索
g/           マッチ行のフィルタバッファを作成
```

フィルタバッファでは:

- `Enter` で元バッファの該当行へジャンプ
- 再度 `g/` で再帰的に絞り込み
- `:q` で閉じて戻る

### 16.5 スペルチェック

```
:set spell     スペルチェック有効化
]s             次のスペルミスへ
[s             前のスペルミスへ
:set nospell   無効化
```

---

## 第17章: Git 連携

### この章で学ぶこと

- Git コマンドの使い方
- blame, status, diff, log, branch, commit, grep

### 17.1 Git コマンドへのアクセス

```
Ctrl-g    ":git " がプリセットされたコマンドラインに入る
:git <subcmd>    Git サブコマンドを実行
```

### 17.2 Git Blame

```
:git blame
```

- ガター（行番号エリア）にコミットハッシュ・著者名・日付を表示
- 元ファイルの filetype に基づくシンタックスハイライトが適用される
- blame バッファ内のキー:
  - `p` — 親コミットの blame へ遷移
  - `P` — 前の blame に戻る
  - `c` — カーソル行のコミット詳細（`git show`）を表示

### 17.3 Git Status

```
:git status
```

`git status` の結果を読み取り専用バッファで表示します。

### 17.4 Git Diff

```
:git diff
:git diff --cached
```

diff 結果を表示します（filetype: diff でハイライト）。`Enter` で差分行の対応ファイルにジャンプできます。

### 17.5 Git Log

```
:git log
:git log -p          パッチ付き（diff ハイライト）
:git log --oneline
```

ストリーミングで逐次表示されます。バッファを閉じるとプロセスも停止します。`-p` 指定時は diff のシンタックスハイライトが適用されます。

### 17.6 Git Branch

```
:git branch
```

ブランチ一覧を表示（コミット日時の新しい順）。各行にブランチ名・日付・最新コミットのサブジェクトを表示。

`Enter` で `:git checkout <branch>` がコマンドラインにプリフィルされます（即時実行ではなく確認ステップ付き）。

### 17.7 Git Commit

```
:git commit
```

コミットメッセージ編集バッファが開きます。`#` で始まる行はコメント（git status 情報）。Insert mode で開始。`:w` または `:wq` でコミット実行、`:q!` でキャンセル。

### 17.8 Git Grep

```
:git grep pattern
:git grep -i pattern
```

`git grep -n` を実行し、結果バッファで `Enter` を押すと該当ファイルの該当行にジャンプします。

### 17.9 その他の Git コマンド

未知のサブコマンドはシェルで直接実行されます。

```
:git stash
:git rebase -i HEAD~3
```

Tab 補完で git サブコマンドを補完できます。

---

## 第18章: GitHub 連携

### この章で学ぶこと

- `:gh link` / `:gh browse` / `:gh pr`

### 18.1 GitHub リンクの生成

```
:gh link              現在ファイル・行の GitHub URL を生成
:'<,'>gh link         選択範囲の行範囲リンクを生成（#L5-L10 形式）
:gh link origin       リモート名を明示指定
```

URL は message line に表示され、OSC 52 でクリップボードにコピーされます。

### 18.2 ブラウザで開く

```
:gh browse            現在ファイルの GitHub ページをブラウザで開く
```

`:gh link` と同じ URL 解決ロジックを使用します。

### 18.3 PR ページを開く

```
:gh pr                現在ブランチの PR ページをブラウザで開く
```

### 18.4 その他の gh コマンド

未知のサブコマンドはシェルで直接実行されます。

```
:gh issue list
:gh pr status
```

Tab 補完で gh サブコマンドを補完できます。

---

# 第IV部: カスタマイズと拡張

---

## 第19章: オプション設定

### この章で学ぶこと

- `:set` の構文
- 主要オプションの解説

### 19.1 `:set` の構文

```
:set                     現在の設定一覧を表示
:set {name}              boolean オプションを ON
:set no{name}            boolean オプションを OFF
:set inv{name}           boolean オプションを反転
:set {name}?             値を表示
:set {name}={value}      値を設定
:setlocal {name}={value} ローカルスコープで設定
:setglobal {name}={value} グローバルスコープで設定
```

### 19.2 表示系オプション（Window-local）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `number` | bool | false | 行番号表示 |
| `relativenumber` | bool | false | 相対行番号（number 併用時は現在行が絶対番号） |
| `wrap` | bool | true | 長い行を画面幅で折り返し |
| `linebreak` | bool | false | wrap 時に空白位置で折り返し |
| `breakindent` | bool | false | wrap 継続行にインデントを反映 |
| `cursorline` | bool | false | 現在行の背景ハイライト |
| `scrolloff` | int | 0 | カーソル上下の余白行数 |
| `sidescrolloff` | int | 0 | カーソル左右の余白桁数 |
| `numberwidth` | int | 4 | 行番号列の最小幅 |
| `colorcolumn` | string | nil | 桁ガイド列（例: "80" や "80,100"） |
| `signcolumn` | string | "auto" | サイン列の表示方針 |
| `list` | bool | false | 不可視文字の可視化 |
| `listchars` | string | "tab:>-,trail:-,nbsp:+" | 不可視文字の表示記号 |
| `showbreak` | string | "" | wrap 継続行の先頭文字列 |

### 19.3 編集系オプション（Buffer-local）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `tabstop` | int | 2 | タブの表示幅 |
| `expandtab` | bool | false | Tab をスペースに変換 |
| `shiftwidth` | int | 2 | インデント幅 |
| `softtabstop` | int | 0 | Tab 入力/削除時の編集幅 |
| `autoindent` | bool | true | 改行時にインデントを引き継ぐ |
| `smartindent` | bool | true | 簡易自動インデント |
| `filetype` | string | nil | ファイルタイプ |
| `iskeyword` | string | nil | 単語境界の定義 |
| `spell` | bool | false | スペルチェック |
| `path` | string | nil | gf 用ファイル探索ディレクトリ |
| `suffixesadd` | string | nil | gf 用拡張子補完候補 |
| `onsavehook` | bool | true | 保存時の lang フック |

### 19.4 検索系オプション（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `ignorecase` | bool | false | 大文字小文字を無視 |
| `smartcase` | bool | false | 大文字を含むときだけ case-sensitive |
| `hlsearch` | bool | true | 検索ハイライト |
| `incsearch` | bool | false | インクリメンタル検索 |

### 19.5 ウィンドウ/バッファ管理（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `splitbelow` | bool | false | split を下に |
| `splitright` | bool | false | vsplit を右に |
| `hidden` | bool | false | 未保存バッファの切替を許可 |
| `autowrite` | bool | false | 切替時に自動保存 |
| `clipboard` | string | "" | "unnamed" で `*`、"unnamedplus" で `+` と連携 |

### 19.6 入力・補完系（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `timeoutlen` | int | 1000 | キーマップの保留待ち時間(ms) |
| `ttimeoutlen` | int | 50 | ESC シーケンス待ち時間(ms) |
| `backspace` | string | "indent,eol,start" | Backspace が越えてよい境界 |
| `completeopt` | string | "menu,menuone,noselect" | 補完 UI の挙動 |
| `pumheight` | int | 10 | 補完候補の最大表示件数 |
| `wildmode` | string | "full" | コマンドライン補完の挙動 |
| `wildmenu` | bool | false | コマンドライン補完候補の一覧表示 |
| `wildignore` | string | "" | path 補完から除外するパターン |
| `wildignorecase` | bool | false | wildignore を case-insensitive に |
| `showmatch` | bool | false | 閉じ括弧入力時のフィードバック |
| `whichwrap` | string | "" | 左右移動の行またぎ条件 |
| `virtualedit` | string | "" | 実文字のない位置へのカーソル移動 |
| `termguicolors` | bool | false | truecolor 描画 |

### 19.7 Undo / Grep 系（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `undofile` | bool | true | undo 履歴の永続化 |
| `undodir` | string | nil | undo ファイルの保存先 |
| `syncload` | bool | false | 大ファイルの同期ロード |
| `grepprg` | string | "grep -nH" | 外部 grep コマンド |
| `grepformat` | string | "%f:%l:%m" | grep 出力のパース書式 |

### 19.8 sixel（Global）

| オプション | 型 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `sixel` | string | "auto" | sixel 出力制御（auto/on/off） |

---

## 第20章: 設定ファイル

### この章で学ぶこと

- init.rb の場所と書き方
- ftplugin の仕組み
- ConfigDSL
- CLI オプションとの組み合わせ

### 20.1 設定ファイルの場所

```
$XDG_CONFIG_HOME/ruvim/init.rb
~/.config/ruvim/init.rb          （XDG_CONFIG_HOME 未設定時）
```

ftplugin（ファイルタイプごとの設定）:

```
~/.config/ruvim/ftplugin/<filetype>.rb
```

### 20.2 init.rb の例

```ruby
# ~/.config/ruvim/init.rb

# オプション設定
set "number"
set "relativenumber"
set "ignorecase"
set "smartcase"
set "scrolloff=5"
set "splitbelow"
set "splitright"

# キーバインド
nmap "H", "cursor.line_start"
nmap "L", "cursor.line_end"

# カスタムコマンド
command "user.show_path", desc: "Show current file path" do |ctx, **|
  ctx.editor.echo(ctx.buffer.path || "[No Name]")
end

nmap "gp", "user.show_path"

# Ex コマンドとして公開
ex_command_call "ShowPath", "user.show_path"
```

### 20.3 ftplugin の例

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb

setlocal "tabstop=2"
setlocal "expandtab"
setlocal "shiftwidth=2"

# Ruby ファイルでだけ有効なキーバインド
nmap "K", desc: "Show method name" do |ctx, **|
  line = ctx.buffer.line_at(ctx.window.cursor_y)
  if line =~ /def (\w+)/
    ctx.editor.echo("Method: #{$1}")
  end
end
```

ftplugin の `nmap`/`imap` は filetype-local として登録され、そのファイルタイプのバッファでのみ有効です。

### 20.4 ConfigDSL メソッド一覧

| メソッド | 説明 |
|---------|------|
| `set "option"` | オプション設定 |
| `setlocal "option"` | ローカルスコープで設定 |
| `setglobal "option"` | グローバルスコープで設定 |
| `nmap seq, cmd_id` | Normal mode キーバインド |
| `imap seq, cmd_id` | Insert mode キーバインド |
| `map_global seq, cmd_id, mode:` | 汎用キーバインド |
| `command id, &block` | 内部コマンド定義 |
| `ex_command name, &block` | Ex コマンド定義 |
| `ex_command_call name, cmd_id` | Ex → 内部コマンドの中継 |

### 20.5 CLI オプションとの組み合わせ

```bash
ruvim --clean file.txt                 # 設定を読まない
ruvim -u /path/to/custom_init.rb       # 別の設定ファイル
ruvim -u NONE                          # user config を読まない（ftplugin は有効）
ruvim --cmd 'set number' file.txt      # config 読み込み前に実行
ruvim -c 'set number' file.txt         # 起動後に実行
```

---

## 第21章: Plugin API

### この章で学ぶこと

- `command` / `ex_command` の定義
- `nmap` / `imap` の定義
- `ctx` API の使い方
- `:ruby` による対話的な Ruby 実行

### 21.1 内部コマンドの定義

```ruby
command "user.hello", desc: "Say hello" do |ctx, argv:, kwargs:, bang:, count:|
  ctx.editor.echo("Hello! count=#{count}")
end
```

### 21.2 Ex コマンドの定義

```ruby
ex_command "BufInfo", desc: "Show buffer info", nargs: 0 do |ctx, argv:, kwargs:, bang:, count:|
  buf = ctx.buffer
  ctx.editor.echo("#{buf.display_name} (#{buf.line_count} lines, modified=#{buf.modified?})")
end
```

### 21.3 Ex → 内部コマンドの中継

```ruby
command "user.hello" do |ctx, **|
  ctx.editor.echo("hello")
end

ex_command_call "Hello", "user.hello", desc: "Run hello"
```

これで `H` キーでも `:Hello` でも同じ処理を呼べます。

### 21.4 キーバインドのブロック版

```ruby
nmap "K", desc: "Show buffer name" do |ctx, **|
  ctx.editor.echo(ctx.buffer.display_name)
end
```

### 21.5 `ctx` API

ブロックに渡される `ctx` は `RuVim::Context` です。

主なアクセス先:

```ruby
ctx.editor          # エディタ全体の状態
ctx.buffer          # 現在バッファ（RuVim::Buffer）
ctx.window          # 現在ウィンドウ（RuVim::Window）
```

#### `ctx.editor` の主要メソッド

```ruby
# 表示
ctx.editor.echo("message")
ctx.editor.echo_error("error message")

# モード操作
ctx.editor.enter_normal_mode
ctx.editor.enter_insert_mode

# バッファ操作
ctx.editor.open_path("file.txt")
ctx.editor.switch_to_buffer(buffer_id)
ctx.editor.buffers  # {id => Buffer}

# オプション
ctx.editor.effective_option("tabstop")
ctx.editor.set_option("number", true)

# レジスタ
ctx.editor.get_register("a")
ctx.editor.set_register("a", text: "hello", type: :charwise)

# マーク / ジャンプ
ctx.editor.set_mark("a")
ctx.editor.jump_to_mark("a")
```

#### `ctx.buffer` の主要メソッド

```ruby
ctx.buffer.path           # ファイルパス
ctx.buffer.display_name   # 表示名
ctx.buffer.lines          # 行配列
ctx.buffer.line_count     # 行数
ctx.buffer.modified?      # 変更あり?
ctx.buffer.line_at(row)   # 指定行の内容

# 編集（undo グループで囲む）
ctx.buffer.begin_change_group
ctx.buffer.insert_text(row, col, "text")
ctx.buffer.end_change_group
```

#### `ctx.window` の主要メソッド

```ruby
ctx.window.cursor_x       # カーソル列
ctx.window.cursor_y       # カーソル行
ctx.window.cursor_y += 10
ctx.window.clamp_to_buffer(ctx.buffer)
```

### 21.6 `:ruby` — 対話的な Ruby 実行

```
:ruby buffer.line_count
:rb [window.cursor_y, window.cursor_x]
:ruby editor.echo("hello from :ruby")
```

`ctx`, `editor`, `buffer`, `window` を参照できます。stdout/stderr の出力は `[Ruby Output]` バッファに表示されます。

### 21.7 ファイル分割

```ruby
# ~/.config/ruvim/init.rb
require File.expand_path("plugins/my_tools", __dir__)
```

`~/.config/ruvim/plugins/my_tools.rb` に分離できます。

---

## 第22章: シンタックスハイライトと言語サポート

### この章で学ぶこと

- 対応言語の一覧
- filetype 検出の仕組み
- オートインデント
- on_save フック

### 22.1 対応言語（26言語）

RuVim は以下の言語のシンタックスハイライトに対応しています:

| 言語 | filetype | インデント | on_save |
|------|----------|-----------|---------|
| Ruby | ruby | あり | `ruby -wc` 構文チェック |
| JSON | json | あり | — |
| JSONL | jsonl | — | — |
| Markdown | markdown | — | — |
| Scheme | scheme | — | — |
| C | c | あり | `gcc` チェック |
| C++ | cpp | あり | `g++` チェック |
| Diff | diff | — | — |
| YAML | yaml | あり | — |
| Shell/Bash | sh | あり | — |
| Python | python | あり | — |
| JavaScript | javascript | あり | — |
| TypeScript | typescript | あり | — |
| HTML | html | — | — |
| TOML | toml | — | — |
| Go | go | あり | — |
| Rust | rust | あり | — |
| Makefile | make | — | — |
| Dockerfile | dockerfile | — | — |
| SQL | sql | — | — |
| Elixir | elixir | あり | — |
| Perl | perl | あり | — |
| Lua | lua | あり | — |
| OCaml | ocaml | あり | — |
| ERB | erb | — | — |
| Git commit | gitcommit | — | — |

加えて TSV, CSV, 画像ファイル（PNG/JPG/GIF/BMP/WEBP）は Rich View 用の filetype として検出されます。

### 22.2 filetype 検出

ファイルを開くと、以下の順で filetype を検出します:

1. ファイル名（basename）のマッチング（例: `Makefile`, `Dockerfile`）
2. 拡張子のマッチング（例: `.rb` → ruby, `.py` → python）
3. shebang 行のチェック（例: `#!/usr/bin/env ruby`）

手動で filetype を変更:

```
:set filetype=python
```

### 22.3 オートインデント

`autoindent` がデフォルトで有効です。改行時に前行のインデントを引き継ぎます。

`smartindent` も有効で、前行が `{`, `[`, `(` で終わる場合に `shiftwidth` 分のインデントを追加します。

Ruby filetype では `=` オペレータでネスト構造に基づく自動インデントが適用されます。

### 22.4 on_save フック

ファイル保存時に lang モジュールの `on_save` フックが呼ばれます。

- Ruby: `ruby -wc` で構文チェック → エラーを quickfix list に展開
- C: `gcc` でチェック
- C++: `g++` でチェック

```
:set noonsavehook     保存時フックを無効化
:set onsavehook       有効に戻す
```

---

## 第23章: Rich View モード

### この章で学ぶこと

- TSV/CSV のテーブル表示
- Markdown のリッチ表示
- JSON/JSONL の整形表示
- 画像表示

### 23.1 Rich View の起動

```
gr          Normal mode でトグル
:rich       Ex コマンドでトグル
:rich tsv   形式を明示指定
:rich csv
```

Rich mode ではバッファ内容を変更せず、描画パイプラインで整形表示します。

### 23.2 TSV/CSV テーブル表示

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

### 23.3 Markdown リッチ表示

Markdown ファイルで Rich View を有効にすると:

- 見出し（H1-H6）: レベル別の太字 + 色
- インライン装飾: `**太字**`, `*斜体*`, `` `コード` ``, `[リンク](url)`, チェックボックス
- コードブロック: フェンスで囲まれた部分を暖色表示
- テーブル: 列幅揃え + box-drawing 罫線（`│`, `─`, `┼`）
- 水平線（HR）: `─` 線に置換
- ブロック引用: `>` 行を cyan 表示
- 画像: sixel 対応ターミナルでは画像を表示

### 23.4 JSON/JSONL 整形表示

JSON ファイルで Rich View を有効にすると、ミニファイ JSON を整形して読み取り専用バッファに表示します。

JSONL（1行1JSON）ファイルでは、各行を個別にパース・整形し、`---` セパレータで区切って表示します。

仮想バッファ方式なので、`Esc` / `Ctrl-C` で元のバッファに戻れます。

### 23.5 画像表示

画像ファイル（PNG/JPG/GIF/BMP/WEBP）を開くと、自動的に Rich View として表示されます。sixel 対応ターミナルでは画像がインライン表示されます。

```
:e photo.png     画像ファイルを開く
```

sixel の制御:

```
:set sixel=auto    自動検出（デフォルト）
:set sixel=on      強制有効
:set sixel=off     無効
```

### 23.6 Rich mode での操作

Rich mode 中は:

- 移動・検索・yank 等は通常通り使える
- バッファを変更する操作（insert/delete/change/paste/replace）はブロックされる
- statusline に `-- RICH --` と表示

---

## 第24章: ストリーム連携

### この章で学ぶこと

- stdin パイプ
- `:run` コマンド
- `:follow` コマンド
- 非同期ファイルロード

### 24.1 stdin パイプ

コマンドの出力を RuVim にパイプできます:

```bash
cat file.txt | ruvim
ls -la | ruvim
git log | ruvim
```

- バッファ名は `[stdin]`
- Normal mode の `Ctrl-c` でストリームを停止
- 完了時: `[stdin/EOF]`、失敗時: `[stdin/error]`

### 24.2 `:run` コマンド

```
:run command         コマンドを実行し、出力を [Shell Output] バッファに表示
:run ruby %          現在ファイルを Ruby で実行
:run                 直前のコマンドを再実行（または runprg の値）
```

- PTY 経由でリアルタイム出力
- `Ctrl-C` で停止
- `%` は現在のファイル名に展開
- 変更のあるバッファは実行前に自動保存
- statusline に実行状態を表示

ファイルタイプ別のデフォルト `runprg`:

| filetype | runprg |
|----------|--------|
| ruby | `ruby -w %` |
| python | `python3 %` |
| c | `gcc -Wall -o /tmp/a.out % && /tmp/a.out` |
| cpp | `g++ -Wall -o /tmp/a.out % && /tmp/a.out` |
| scheme | `gosh %` |
| javascript | `node %` |

### 24.3 `:follow` コマンド

```
:follow              follow mode 開始（トグル）
ruvim -f file.log    起動時から follow mode
```

ファイルへの追記をリアルタイムにバッファへ反映する `tail -f` 相当の機能です。

- カーソルが最終行（`G`）にいると末尾を自動追従
- 途中にいるとスクロール位置を維持
- `Ctrl-C` や再度 `:follow` で停止
- follow 中はバッファ変更不可
- ファイルの truncate/削除を検知して対応
- Linux では inotify を優先、使えない場合は polling

### 24.4 非同期ファイルロード

大きなファイル（デフォルト閾値以上）を開くと:

1. 先頭 8MB を先に表示
2. 残りをバックグラウンドでチャンク単位で読み込み
3. statusline に `[load]` と表示（完了で消える）

```
:set syncload        同期ロードに切替（非同期を無効化）
:set nosyncload      非同期に戻す
```

環境変数で閾値を調整:

```bash
RUVIM_ASYNC_FILE_THRESHOLD_BYTES=16777216 ruvim huge.log
RUVIM_ASYNC_FILE_PREFIX_BYTES=4194304 ruvim huge.log
```

---

## 第25章: 補完

### この章で学ぶこと

- Command-line 補完
- Insert mode 補完
- 履歴

### 25.1 Command-line 補完

`:` の後で `Tab` を押すと補完が動作します。

補完対象:

- **コマンド名**: `:w` → `:write`, `:wq`, `:wqa` など
- **パス**: `:e `, `:w ` の後にファイルパスを補完
- **バッファ名**: `:buffer ` の後にバッファ名を補完
- **オプション名**: `:set ` の後にオプション名を補完
- **Git サブコマンド**: `:git ` の後に `blame`, `status` などを補完
- **gh サブコマンド**: `:gh ` の後に `link`, `browse` などを補完

補完の挙動は `wildmode` オプションで制御:

```
:set wildmode=full       全候補をサイクル（デフォルト）
:set wildmode=longest    最長共通部分まで展開
:set wildmode=list       候補を一覧表示
```

除外パターン:

```
:set wildignore=*.o,*.pyc,__pycache__
```

### 25.2 Insert mode 補完

```
Ctrl-n    次の候補（buffer words 補完）
Ctrl-p    前の候補（buffer words 補完）
```

バッファ内の単語から補完候補を生成します。

補完 UI の制御:

```
:set completeopt=menu,menuone,noselect
:set pumheight=15        候補の最大表示件数
```

### 25.3 コマンドライン履歴

```
Up      前の履歴を呼び出す
Down    次の履歴を呼び出す
```

履歴は prefix ごとに独立して保持されます（`:`, `/`, `?`）。

---

## 第26章: セキュリティと起動オプション

### この章で学ぶこと

- `-Z`（restricted mode）
- `-R`（readonly）
- `-M`（modifiable off）
- DoS 保護
- Unicode 幅の設定

### 26.1 Restricted mode (`-Z`)

```bash
ruvim -Z file.txt
```

以下のコマンドが無効化されます:

- `:!`（シェル実行）
- `:ruby` / `:rb`（Ruby eval）
- `:grep` / `:lgrep`（外部 grep）
- `:git`（Git 操作全般）
- `:gh`（GitHub 操作全般）
- user config / ftplugin の読み込み
- Ruby 構文チェック（on_save）

信頼できないファイルを安全に閲覧するのに適しています。

### 26.2 Readonly mode (`-R`)

```bash
ruvim -R file.txt
```

バッファが readonly になり、`:w` が拒否されます。

### 26.3 Modifiable off (`-M`)

```bash
ruvim -M file.txt
```

バッファが `modifiable=false` + `readonly=true` になり、編集操作が拒否されます。

### 26.4 DoS 保護

RuVim には以下のセキュリティ対策が含まれています:

- **Sixel DoS 保護**: PNG デコーダで画像サイズ上限（50M ピクセル）、Zlib 展開サイズ上限（200MB）、URL ダウンロードサイズ上限（10MB）を設定
- **特殊ファイルの拒否**: FIFO・デバイス・ソケット等の特殊ファイルは `File.file?` チェックで拒否
- **制御文字のサニタイズ**: Rich view レンダリング時にバッファ内容の制御文字（ESC 含む）を無害化し、ターミナルエスケープインジェクションを防止
- **`:grep` のシェルインジェクション対策**: argv 配列で安全に実行（シェル経由ではない）

### 26.5 Unicode 幅の設定

```bash
RUVIM_AMBIGUOUS_WIDTH=2 ruvim      # 曖昧幅文字を幅2として扱う
```

CJK 環境でギリシャ文字等の幅がずれる場合に設定してください。

---

# 付録

---

## 付録A: キーバインド全一覧

### Normal mode

| キー | 動作 |
|------|------|
| `h` / `←` | 左へ移動 |
| `j` / `↓` | 下へ移動 |
| `k` / `↑` | 上へ移動 |
| `l` / `→` | 右へ移動 |
| `0` | 行頭へ |
| `$` | 行末へ |
| `^` | 最初の非空白へ |
| `w` | 次の単語へ |
| `b` | 前の単語へ |
| `e` | 単語末へ |
| `f{c}` | 行内で次の {c} へ |
| `F{c}` | 行内で前の {c} へ |
| `t{c}` | 行内で次の {c} の手前へ |
| `T{c}` | 行内で前の {c} の直後へ |
| `;` | f/F/t/T を繰り返し |
| `,` | f/F/t/T を逆方向 |
| `%` | 対応括弧へジャンプ |
| `gg` | バッファ先頭へ |
| `G` | バッファ末尾へ |
| `Ctrl-d` | 半ページ下 |
| `Ctrl-u` | 半ページ上 |
| `Ctrl-f` / `PageDown` | 1ページ下 |
| `Ctrl-b` / `PageUp` | 1ページ上 |
| `Ctrl-e` | 1行下スクロール |
| `Ctrl-y` | 1行上スクロール |
| `zt` | カーソル行を上端 |
| `zz` | カーソル行を中央 |
| `zb` | カーソル行を下端 |
| `i` | Insert mode（前） |
| `a` | Insert mode（後ろ） |
| `A` | Insert mode（行末） |
| `I` | Insert mode（行頭非空白） |
| `o` | 下に行を開いて Insert |
| `O` | 上に行を開いて Insert |
| `x` | 文字削除 |
| `X` | 前の文字削除 |
| `s` | 文字削除して Insert |
| `S` | 行削除して Insert |
| `dd` | 行削除 |
| `D` | 行末まで削除 |
| `d{motion}` | モーション範囲を削除 |
| `yy` / `Y` | 行ヤンク |
| `yw` | 単語方向ヤンク |
| `y{motion}` | モーション範囲をヤンク |
| `p` | 後ろにペースト |
| `P` | 前にペースト |
| `cc` | 行変更 |
| `C` | 行末まで変更 |
| `c{motion}` | モーション範囲を変更 |
| `==` | 自動インデント |
| `={motion}` | 範囲を自動インデント |
| `>>` | 右シフト |
| `<<` | 左シフト |
| `r{c}` | 1文字置換 |
| `~` | 大文字小文字切替 |
| `J` | 行結合 |
| `v` | Visual (characterwise) |
| `V` | Visual (linewise) |
| `Ctrl-v` | Visual (blockwise) |
| `u` | Undo |
| `Ctrl-r` | Redo |
| `.` | 直前変更の繰り返し |
| `/` | 前方検索 |
| `?` | 後方検索 |
| `n` | 次のマッチ |
| `N` | 前のマッチ |
| `*` | カーソル下単語を前方検索 |
| `#` | カーソル下単語を後方検索 |
| `g*` | 部分一致で前方検索 |
| `g#` | 部分一致で後方検索 |
| `gf` | ファイルジャンプ |
| `gr` | Rich mode トグル |
| `g/` | フィルタバッファ作成 |
| `"{reg}` | レジスタ指定 |
| `m{mark}` | マーク設定 |
| `'{mark}` | マークへ（行頭） |
| `` `{mark} `` | マークへ（正確位置） |
| `''` | 前の位置へ（行頭） |
| ` `` ` | 前の位置へ（正確位置） |
| `Ctrl-o` | ジャンプリスト戻る |
| `Ctrl-i` | ジャンプリスト進む |
| `q{reg}` | マクロ記録開始/終了 |
| `@{reg}` | マクロ再生 |
| `@@` | 直前マクロ再生 |
| `Ctrl-w w` | 次ウィンドウ |
| `Ctrl-w h/j/k/l` | ウィンドウ方向移動 |
| `Ctrl-w c` | ウィンドウ閉じる |
| `Ctrl-w o` | 他ウィンドウ全閉じ |
| `Ctrl-w =` | サイズ均等化 |
| `Ctrl-w +/-` | 高さ増減 |
| `Ctrl-w >/<` | 幅増減 |
| `Shift+矢印` | ウィンドウ移動 or 分割 |
| `:` | Command-line mode |
| `Ctrl-g` | Git コマンドモード |
| `Ctrl-c` | stdin ストリーム停止 |
| `Ctrl-z` | サスペンド |
| `Esc` | メッセージ/保留入力クリア |
| `Q` | quickfix list を開く |
| `]q` | 次の quickfix item |
| `[q` | 前の quickfix item |
| `]s` | 次のスペルミス |
| `[s` | 前のスペルミス |
| `Enter` | quickfix/location バッファでジャンプ |

### Insert mode

| キー | 動作 |
|------|------|
| 文字入力 | テキスト挿入 |
| `Enter` | 改行 |
| `Backspace` | 1文字削除 |
| `Ctrl-n` | 補完（次候補） |
| `Ctrl-p` | 補完（前候補） |
| `Esc` | Normal mode |
| `Ctrl-c` | Normal mode |
| `Ctrl-z` | サスペンド |
| 矢印キー | 移動 |
| `PageUp`/`PageDown` | ページ移動 |

### Visual mode

| キー | 動作 |
|------|------|
| `h/j/k/l`, `w/b/e`, `0/$`, `gg/G` | 範囲伸縮 |
| `v` | characterwise 開始/終了 |
| `V` | linewise 切替 |
| `y` | ヤンク |
| `d` | 削除 |
| `=` | 自動インデント |
| `i`/`a` + object | テキストオブジェクト選択 |
| `Esc` / `Ctrl-c` | キャンセル |

### Rich mode

| キー | 動作 |
|------|------|
| 移動・検索・yank | 通常通り |
| 編集操作 | ブロック |
| `Esc` / `Ctrl-c` | Normal mode |

### Command-line mode

| キー | 動作 |
|------|------|
| 文字入力 | 入力 |
| `Enter` | 実行 |
| `Backspace` | 削除 |
| `Up` / `Down` | 履歴移動 |
| `Left` / `Right` | カーソル移動 |
| `Tab` | 補完 |
| `Esc` / `Ctrl-c` | キャンセル |

---

## 付録B: Exコマンド全一覧

| コマンド | エイリアス | 説明 |
|---------|-----------|------|
| `:w [path]` | `:write` | 保存 |
| `:q[!]` | `:quit` | 終了 |
| `:qa[!]` | `:qall` | 全終了 |
| `:wq[!] [path]` | — | 保存して終了 |
| `:wqa[!]` | `:wqall`, `:xa`, `:xall` | 全保存して終了 |
| `:e[!] [path]` | `:edit` | ファイルを開く / 再読み込み |
| `:r [file]` | `:read` | ファイル/コマンド出力を挿入 |
| `:w !cmd` | — | バッファをコマンドにパイプ |
| `:!cmd` | — | シェルコマンド実行 |
| `:run [cmd]` | — | コマンド実行 + 結果バッファ |
| `:help [topic]` | — | ヘルプ表示 |
| `:commands` | — | Ex コマンド一覧 |
| `:bindings [mode]` | — | キーバインド一覧 |
| `:command[!] Name body` | — | ユーザー定義 Ex コマンド |
| `:ruby code` | `:rb` | Ruby 実行 |
| `:ls` | `:buffers` | バッファ一覧 |
| `:bnext[!]` | `:bn` | 次バッファ |
| `:bprev[!]` | `:bp` | 前バッファ |
| `:buffer[!] id\|name\|#` | `:b` | バッファ切替 |
| `:bdelete[!] [id]` | `:bd` | バッファ削除 |
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

---

## 付録C: オプション全一覧（51個）

### Window-local

| 名前 | 型 | デフォルト | 状態 |
|------|------|-----------|------|
| `number` | bool | false | DONE |
| `relativenumber` | bool | false | DONE |
| `wrap` | bool | true | PARTIAL |
| `linebreak` | bool | false | PARTIAL |
| `breakindent` | bool | false | PARTIAL |
| `cursorline` | bool | false | DONE |
| `scrolloff` | int | 0 | DONE |
| `sidescrolloff` | int | 0 | DONE |
| `numberwidth` | int | 4 | DONE |
| `colorcolumn` | string | nil | DONE |
| `signcolumn` | string | "auto" | PARTIAL |
| `list` | bool | false | PARTIAL |
| `listchars` | string | "tab:>-,trail:-,nbsp:+" | PARTIAL |
| `showbreak` | string | "" | PARTIAL |

### Global

| 名前 | 型 | デフォルト | 状態 |
|------|------|-----------|------|
| `showmatch` | bool | false | PARTIAL |
| `matchtime` | int | 5 | PARTIAL |
| `whichwrap` | string | "" | PARTIAL |
| `virtualedit` | string | "" | PARTIAL |
| `ignorecase` | bool | false | DONE |
| `smartcase` | bool | false | DONE |
| `hlsearch` | bool | true | DONE |
| `incsearch` | bool | false | PARTIAL |
| `splitbelow` | bool | false | DONE |
| `splitright` | bool | false | DONE |
| `hidden` | bool | false | PARTIAL |
| `autowrite` | bool | false | PARTIAL |
| `clipboard` | string | "" | PARTIAL |
| `timeoutlen` | int | 1000 | DONE |
| `ttimeoutlen` | int | 50 | DONE |
| `backspace` | string | "indent,eol,start" | PARTIAL |
| `completeopt` | string | "menu,menuone,noselect" | PARTIAL |
| `pumheight` | int | 10 | PARTIAL |
| `wildmode` | string | "full" | PARTIAL |
| `wildignore` | string | "" | DONE |
| `wildignorecase` | bool | false | DONE |
| `wildmenu` | bool | false | PARTIAL |
| `termguicolors` | bool | false | PARTIAL |
| `undofile` | bool | true | DONE |
| `undodir` | string | nil | DONE |
| `syncload` | bool | false | DONE |
| `grepprg` | string | "grep -nH" | DONE |
| `grepformat` | string | "%f:%l:%m" | DONE |
| `sixel` | string | "auto" | — |

### Buffer-local

| 名前 | 型 | デフォルト | 状態 |
|------|------|-----------|------|
| `path` | string | nil | PARTIAL |
| `suffixesadd` | string | nil | PARTIAL |
| `textwidth` | int | 0 | 定義のみ |
| `formatoptions` | string | nil | 定義のみ |
| `expandtab` | bool | false | DONE |
| `shiftwidth` | int | 2 | PARTIAL |
| `softtabstop` | int | 0 | PARTIAL |
| `autoindent` | bool | true | DONE |
| `smartindent` | bool | true | PARTIAL |
| `iskeyword` | string | nil | PARTIAL |
| `tabstop` | int | 2 | DONE |
| `filetype` | string | nil | DONE |
| `spell` | bool | false | DONE |
| `spelllang` | string | "en" | 定義のみ |
| `onsavehook` | bool | true | DONE |

---

## 付録D: 対応言語一覧（26言語）

| filetype | 拡張子 | ハイライト方式 | インデント | on_save |
|----------|--------|---------------|-----------|---------|
| ruby | .rb | Prism lexer | あり | ruby -wc |
| json | .json | regex | あり | — |
| jsonl | .jsonl | regex | — | — |
| markdown | .md | regex | — | — |
| scheme | .scm | regex | — | — |
| c | .c, .h | regex | あり | gcc |
| cpp | .cpp, .hpp, .cc | regex（C拡張） | あり | g++ |
| diff | .diff, .patch | regex | — | — |
| yaml | .yml, .yaml | regex | あり | — |
| sh | .sh, .bash | regex | あり | — |
| python | .py | regex | あり | — |
| javascript | .js, .jsx | regex | あり | — |
| typescript | .ts, .tsx | regex（JS拡張） | あり | — |
| html | .html, .htm | regex | — | — |
| toml | .toml | regex | — | — |
| go | .go | regex | あり | — |
| rust | .rs | regex | あり | — |
| make | Makefile | regex | — | — |
| dockerfile | Dockerfile | regex | — | — |
| sql | .sql | regex | — | — |
| elixir | .ex, .exs | regex | あり | — |
| perl | .pl, .pm | regex | あり | — |
| lua | .lua | regex | あり | — |
| ocaml | .ml, .mli | regex | あり | — |
| erb | .erb | regex（HTML+Ruby） | — | — |
| gitcommit | COMMIT_EDITMSG | regex | — | — |

追加の filetype（Rich View 用）:

| filetype | 拡張子 | 用途 |
|----------|--------|------|
| tsv | .tsv | テーブル表示 |
| csv | .csv | テーブル表示 |
| image | .png, .jpg, .gif, .bmp, .webp | 画像表示 |

---

## 付録E: Vimとの違い

### RuVim の独自機能

- **Ruby DSL 設定**: init.rb で Ruby の全機能を利用可能（Vim script 不要）
- **`:ruby` コマンド**: 実行中に Ruby eval が可能
- **Rich View モード**: TSV/CSV/Markdown/JSON/画像の構造化表示
- **Follow mode**: `:follow` / `-f` でファイル追従（`tail -f` 相当）
- **ストリーム連携**: stdin パイプ、`:run` でリアルタイム出力表示
- **検索は Ruby 正規表現**: Vim regex ではなく Ruby の Regexp を使用
- **ネスト分割**: ツリー構造のウィンドウレイアウト
- **Shift+矢印キー**: スマート分割（1ウィンドウなら分割、2つ以上ならフォーカス移動）

### 動作の差分

- undo 粒度は簡略化（Insert mode は入ってから出るまでが 1 undo 単位）
- `.` repeat のカウント互換は完全ではない
- word motion の単語境界定義が Vim と一致しない場合がある
- 文字幅は近似（East Asian Width 完全互換ではない）
- `:w!` は現状 `:w` とほぼ同じ（権限昇格は未実装）
- Visual blockwise は最小対応
- option 名の短縮（`nu`, `ts` 等）は未対応
- `:set` の `+=`, `-=` は未対応

### 未実装の主要機能

- Vim script 互換
- folds
- LSP / diagnostics
- job / channel / terminal
- swap / backup（undofile は実装済み）
- diff mode, session（placeholder のみ）

---

## 付録F: トラブルシューティング

### 表示が崩れる

- `Ctrl-z` でサスペンドし、`fg` で復帰すると全面再描画される
- ターミナルリサイズ後は自動で再描画される
- CJK 文字の幅がずれる場合: `RUVIM_AMBIGUOUS_WIDTH=2 ruvim` を試す

### 日本語の表示幅がおかしい

```bash
RUVIM_AMBIGUOUS_WIDTH=2 ruvim
```

### クリップボードが使えない

RuVim はシステムクリップボードとして以下を試みます:

- macOS: `pbcopy` / `pbpaste`
- Linux (Wayland): `wl-copy` / `wl-paste`
- Linux (X11): `xclip` or `xsel`
- WSL: PowerShell 経由

対応コマンドがインストールされているか確認してください。

### 大きいファイルの読み込みが遅い

```bash
# 同期ロードに切替
ruvim --cmd 'set syncload' huge.log

# 閾値を調整
RUVIM_ASYNC_FILE_THRESHOLD_BYTES=33554432 ruvim huge.log
```

### 設定ファイルが読み込まれない

- パスを確認: `~/.config/ruvim/init.rb`
- `--clean` を付けて起動すると設定なしで起動
- `-V` で verbose ログを確認

```bash
ruvim -V file.txt 2>log.txt
cat log.txt
```

### on_save の構文チェックを止めたい

```
:set noonsavehook
```

init.rb に書く場合:

```ruby
set "noonsavehook"
```

### デバッグ情報を見る

```bash
ruvim -V2 file.txt 2>debug.log
ruvim --startuptime timing.log file.txt
```

---

*本書は RuVim の現在の実装に基づいています。将来のバージョンで機能が追加・変更される場合があります。*
