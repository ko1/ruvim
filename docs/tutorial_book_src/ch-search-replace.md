# 検索と置換

> "The art of being wise is the art of knowing what to overlook." — William James

## この章で学ぶこと

- `/` と `?` による検索
- `n`/`N` による検索の繰り返し
- `*`/`#` によるカーソル下単語の検索
- `:substitute` による置換
- `:global` / `:vglobal`

大規模なコードベースで目的のコードを素早く見つけ出す力は、開発速度に直結します。検索と置換を使いこなせば、変数名のリネームやパターンの一括変更など、手作業では何分もかかる作業を数秒で完了できます。

## 検索

```
/pattern    前方検索（下方向）
?pattern    後方検索（上方向）
n           同方向に次のマッチへ
N           逆方向に次のマッチへ
```

検索パターンは [Ruby 正規表現](#index:正規表現)です[^1]。

[^1]: Vim とは異なり、RuVim では Ruby の `Regexp` がそのまま使えます。`\d`, `\w`, `(?:...)` など Ruby の正規表現構文がすべて有効です。詳しくは[Vimとの違い](appendix-e.md)を参照してください。

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

## カーソル下単語の検索

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

## 検索オプション

> [!TIP]
> [`smartcase`](#index:smartcase) を有効にすると、小文字だけのパターンでは case-insensitive、大文字を含むパターンでは case-sensitive になります。検索の利便性が大幅に向上するので、[設定ファイル](ch-config.md)で有効化しておくことをお勧めします。

```
:set ignorecase      大文字小文字を無視
:set smartcase       ignorecase 有効時、大文字を含むパターンは case-sensitive
:set hlsearch        マッチをハイライト表示（デフォルト有効）
:set incsearch       入力中にインクリメンタル検索
```

## 置換 (`:substitute`)

基本形:

```
:s/old/new/           現在行の最初のマッチを置換
:s/old/new/g          現在行の全マッチを置換
:%s/old/new/g         バッファ全体の全マッチを置換
:10,20s/old/new/g     10-20行の全マッチを置換
:'<,'>s/old/new/g     Visual 選択範囲の全マッチを置換
```

> [!WARNING]
> `g` フラグを忘れると、各行の**最初の**マッチしか置換されません。全マッチを置換したい場合は必ず `g` を付けてください。

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

## 実践: 変数名のリネーム

プロジェクト内で変数名を `user_name` から `username` に変更する実践例:

```ruby
# BEFORE:
def create_user(user_name, email)
  validate_user_name(user_name)
  user = User.new(user_name: user_name, email: email)
  log("Created user: #{user_name}")
  user
end
```

ステップ 1: まず確認付きで置換を実行:

```
:%s/user_name/username/gc
```

各マッチで確認しながら置換:
- `user_name` (引数名) → `y` で置換
- `validate_user_name` → `n` でスキップ（メソッド名は別）
- `user_name:` (キー) → `n` でスキップ（シンボルはそのまま）
- `user_name` (値) → `y` で置換
- ...

ステップ 2: 単語境界を使って正確にマッチ:

```
:%s/\buser_name\b/username/gc
```

こうすると `validate_user_name` の部分一致を避けられます。

```ruby
# AFTER:
def create_user(username, email)
  validate_user_name(username)
  user = User.new(user_name: username, email: email)
  log("Created user: #{username}")
  user
end
```

## `:global` / `:vglobal`

パターンにマッチする行（またはしない行）に対して Ex コマンドを実行します。

```
:g/pattern/command      マッチ行にコマンドを実行
:v/pattern/command      非マッチ行にコマンドを実行
:g\!/pattern/command     :v と同じ
```

操作例:

```
:g/TODO/d               TODO を含む行を全削除
:v/important/d          important を含まない行を全削除
:g/^$/d                 空行を全削除
:g/pattern/p            マッチ行を表示（hit-enter prompt）
:g/def/normal A;        def を含む行の末尾にセミコロン追加
```

> [!NOTE]
> [`:global`](#index::global) の undo は一括です — 1回の `u` で全変更が元に戻ります。

実践例 — ログレベルの整理:

```ruby
# DEBUG ログを一括削除:
:g/logger\.debug/d

# puts デバッグを一括削除:
:g/^\s*puts /d

# コメントアウトされた行を一括削除:
:g/^\s*#/d
```
