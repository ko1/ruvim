# GitHub 連携

> "Alone we can do so little; together we can do so much." — Helen Keller

## この章で学ぶこと

- `:gh link` / `:gh browse` / `:gh pr`

コードレビューで「この行を見て」と伝えたいとき、[GitHub](#index:GitHub/GitHub 連携) の URL を手でコピーするのは面倒です。[`:gh link`](#index:GitHub/:gh link) を使えば、エディタ上の現在行の GitHub URL を一瞬で生成・コピーできます。チーム開発のコミュニケーションがスムーズになります。

## GitHub リンクの生成

```
:gh link              現在ファイル・行の GitHub URL を生成
:'<,'>gh link         選択範囲の行範囲リンクを生成（#L5-L10 形式）
:gh link origin       リモート名を明示指定
```

URL は message line に表示され、OSC 52 でクリップボードにコピーされます。

## ブラウザで開く

```
:gh browse            現在ファイルの GitHub ページをブラウザで開く
```

`:gh link` と同じ URL 解決ロジックを使用します。

## PR ページを開く

```
:gh pr                現在ブランチの PR ページをブラウザで開く
```

## その他の gh コマンド

未知のサブコマンドはシェルで直接実行されます。

```
:gh issue list
:gh pr status
```

Tab [補完](ch-completion.md)で gh サブコマンドを補完できます。

> [!NOTE]
> [Git 連携](ch-git.md)と同様、[Restricted mode](ch-security.md) (`-Z`) では `:gh` コマンドは無効化されます。
