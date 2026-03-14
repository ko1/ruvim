# トラブルシューティング

## 表示が崩れる

> [!TIP]
> `Ctrl-z` でサスペンドし、`fg` で復帰すると全面再描画されます。多くの表示崩れはこれで解決します。

- ターミナルリサイズ後は自動で再描画される
- CJK 文字の幅がずれる場合: `RUVIM_AMBIGUOUS_WIDTH=2 ruvim` を試す

## 日本語の表示幅がおかしい

```bash
RUVIM_AMBIGUOUS_WIDTH=2 ruvim
```

## クリップボードが使えない

RuVim はシステムクリップボードとして以下を試みます:

- macOS: `pbcopy` / `pbpaste`
- Linux (Wayland): `wl-copy` / `wl-paste`
- Linux (X11): `xclip` or `xsel`
- WSL: PowerShell 経由

対応コマンドがインストールされているか確認してください。

## 大きいファイルの読み込みが遅い

```bash
# 同期ロードに切替
ruvim --sync-load huge.log

# 閾値を調整
RUVIM_ASYNC_FILE_THRESHOLD_BYTES=33554432 ruvim huge.log
```

## 設定ファイルが読み込まれない

- パスを確認: `~/.config/ruvim/init.rb`
- `--clean` を付けて起動すると設定なしで起動
- `-V` で verbose ログを確認

```bash
ruvim -V file.txt 2>log.txt
cat log.txt
```

## on_save の構文チェックを止めたい

```
:set noonsavehook
```

init.rb に書く場合:

```ruby
set "noonsavehook"
```

## デバッグ情報を見る

```bash
ruvim -V2 file.txt 2>debug.log
ruvim --startuptime timing.log file.txt
```
