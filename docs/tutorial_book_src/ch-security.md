# セキュリティと起動オプション

> "Security is not a product, but a process." — Bruce Schneier

## この章で学ぶこと

- `-Z`（restricted mode）
- `-R`（readonly）
- `-M`（modifiable off）
- DoS 保護
- Unicode 幅の設定

信頼できないファイルを開くことがある以上、セキュリティへの配慮は欠かせません。Restricted mode を使えば、シェル実行や Ruby eval を無効にした安全な閲覧環境を作れます。また、readonly モードは「うっかり変更してしまった」事故を防ぎます。

## Restricted mode (`-Z`)

```bash
ruvim -Z file.txt
```

以下のコマンドが無効化されます:

- `:\!`（シェル実行）
- `:ruby` / `:rb`（Ruby eval）
- `:grep` / `:lgrep`（外部 grep）
- `:git`（Git 操作全般）
- `:gh`（GitHub 操作全般）
- user config / ftplugin の読み込み
- Ruby 構文チェック（on_save）

信頼できないファイルを安全に閲覧するのに適しています。

## Readonly mode (`-R`)

```bash
ruvim -R file.txt
```

バッファが readonly になり、`:w` が拒否されます。

## Modifiable off (`-M`)

```bash
ruvim -M file.txt
```

バッファが `modifiable=false` + `readonly=true` になり、編集操作が拒否されます。

## DoS 保護

RuVim には以下のセキュリティ対策が含まれています:

- **Sixel DoS 保護**: PNG デコーダで画像サイズ上限（50M ピクセル）、Zlib 展開サイズ上限（200MB）、URL ダウンロードサイズ上限（10MB）を設定
- **特殊ファイルの拒否**: FIFO・デバイス・ソケット等の特殊ファイルは `File.file?` チェックで拒否
- **制御文字のサニタイズ**: Rich view レンダリング時にバッファ内容の制御文字（ESC 含む）を無害化し、ターミナルエスケープインジェクションを防止
- **`:grep` のシェルインジェクション対策**: argv 配列で安全に実行（シェル経由ではない）

## Unicode 幅の設定

```bash
RUVIM_AMBIGUOUS_WIDTH=2 ruvim      # 曖昧幅文字を幅2として扱う
```

CJK 環境でギリシャ文字等の幅がずれる場合に設定してください。
