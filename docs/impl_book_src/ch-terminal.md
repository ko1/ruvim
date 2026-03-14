# ターミナル制御 — 端末を乗っ取る

> 「道具を極めよ、さすれば道具が手の延長となる」 — 宮本武蔵

テキストエディタがターミナル上で動作するには、端末を「乗っ取る」必要がある。通常のシェルでは、ユーザーが Enter を押すまで入力がバッファリングされ、`^C` でシグナルが送られる。エディタは 1 文字ずつリアルタイムに読みたいし、`^C` をキーとして受け取りたい。

## ロー (Raw) モード

`Terminal#with_ui` は、端末をロー (raw) モードに切り替えて UI セッションを開始する。

```ruby
def with_ui
  @stdin.raw do
    write("\e]112\a\e[2 q\e[?1049h\e[?25l")
    yield
  ensure
    write("\e[0 q\e[?25h\e[?1049l")
  end
end
```

`@stdin.raw` は Ruby の `IO#raw` メソッドで、`termios` の設定を変更して以下を実現する。

- **エコーの無効化**: 入力された文字を端末が自動で表示しない
- **行バッファリングの無効化**: Enter を待たず 1 文字ずつ読める
- **シグナル処理の無効化**: `^C` が SIGINT ではなく `\x03` というバイトとして読める

## エスケープシーケンスによる端末制御

開始時に送るシーケンスの意味はこうだ。

| シーケンス | 意味 |
|---|---|
| `\e]112\a` | カーソル色をリセット |
| `\e[2 q` | カーソルを点滅ブロックに設定 |
| `\e[?1049h` | **代替スクリーンバッファに切り替え** |
| `\e[?25l` | カーソルを非表示 |

代替スクリーンバッファ (`?1049h`) は重要な概念だ。端末には主画面と代替画面の 2 つのバッファがある。エディタは代替画面で動作し、終了すると主画面に戻る。つまり、エディタを閉じるとシェルの表示がそのまま復元される。`less` や `vim` と同じ動作だ。

終了時には逆の操作をする。

| シーケンス | 意味 |
|---|---|
| `\e[0 q` | カーソルスタイルをデフォルトに |
| `\e[?25h` | カーソルを表示 |
| `\e[?1049l` | 主スクリーンバッファに戻る |

## Sixel サポート検出

RuVim は画像表示のために Sixel プロトコルをサポートしている。端末が Sixel に対応しているかどうかは、Device Attributes (DA1) クエリで検出する。

```ruby
def detect_sixel
  @stdout.write("\e[c")        # DA1 クエリを送信
  @stdout.flush
  response = read_terminal_response("c", timeout: 0.5)

  if (m = response.match(/\e\[\?([0-9;]+)c/))
    attrs = m[1].split(";").map(&:to_i)
    return attrs.include?(4)   # 属性 4 = Sixel サポート
  end
  false
end
```

端末に「お前の能力を教えろ」とクエリを送り、返ってきた属性リストに `4` が含まれていれば Sixel 対応だ。この問い合わせ→応答のパターンは `read_terminal_response` で実装されている。

```ruby
def read_terminal_response(terminator, timeout: 0.3)
  response = +""
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    if IO.select([@stdin], nil, nil, 0.05)
      ch = @stdin.read_nonblock(64, exception: false)
      break if ch == :wait_readable || ch.nil?
      response << ch
      break if response.include?(terminator)
    end
  end
  response
end
```

デッドラインまでノンブロッキングで読み続け、ターミネータ文字（`"c"` や `"t"`）が見つかったら終了する。古い端末や応答しない端末では単にタイムアウトする。

## シェルへの一時退避

`:!command` でシェルコマンドを実行する際、エディタは一時的に端末を通常モードに戻す。

```ruby
def suspend_for_shell(command)
  shell = ENV["SHELL"].to_s
  shell = "/bin/sh" if shell.empty?
  @stdin.cooked do                      # 端末を通常モードに戻す
    write("\e[0 q\e[?25h\e[?1049l")     # 主画面に切り替え
    system(shell, "-c", command)         # コマンド実行
    status = $?
    write("\r\nPress ENTER or type command to continue")
    @stdin.raw { @stdin.getc }           # Enter 待ち
    write("\e[2 q\e[?1049h\e[?25l")     # 代替画面に復帰
    status
  end
end
```

`system(shell, "-c", command)` で引数を配列として渡しているのは、シェルインジェクションを防ぐためだ。ユーザーの入力がそのまま引数文字列としてシェルに渡され、展開やパイプは利用者のシェルが処理する。
