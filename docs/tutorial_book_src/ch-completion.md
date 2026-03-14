# 補完

> "Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away." — Antoine de Saint-Exupery

## この章で学ぶこと

- Command-line 補完
- Insert mode 補完
- 履歴

[補完](#index:補完)機能はタイピング量を減らすだけでなく、「何が使えるのか」を発見する手段でもあります。コマンドライン補完で利用可能な Ex コマンドや[オプション](ch-options.md)を探索し、Insert mode 補完でバッファ内の変数名を素早く入力しましょう。

## Command-line 補完

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

## Insert mode 補完

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

## コマンドライン履歴

```
Up      前の履歴を呼び出す
Down    次の履歴を呼び出す
```

履歴は prefix ごとに独立して保持されます（`:`, `/`, `?`）。
