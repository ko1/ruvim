# ストリーム — 非同期 I/O と外部プロセス

> 「水は方円の器に随う」 — 日本のことわざ

RuVim は、外部コマンドの出力をリアルタイムに[バッファ](ch-buffer.md)に表示できる。`:run ls -la` と打つと、ls の出力が逐次表示される。

## Stream 階層

```
Stream（基底クラス: state, stop!）
├── Stream::Stdin  — stdin からのパイプ入力
├── Stream::Run    — 外部コマンド実行（PTY or popen）
├── Stream::Follow — ファイル監視（tail -f 相当）
└── Stream::FileLoad — 大規模ファイルの非同期読み込み
```

## Stream::Run — PTY による外部コマンド実行

```ruby
class Stream::Run < Stream
  def initialize(command:, buffer_id:, queue:, chdir: nil, ...)
    @state = :live
    @thread = Thread.new do
      if chdir
        run_popen(command, chdir, buffer_id, queue, ...)
      else
        run_pty(command, buffer_id, queue, ...)
      end
    end
  end

  def run_pty(command, buffer_id, queue, stream, &notify)
    PTY.spawn(shell, "-c", command) do |r, _w, pid|
      stream.io = r
      stream.pid = pid
      while (chunk = r.readpartial(4096))
        text = Buffer.decode_text(chunk).delete("\r")
        queue << { type: :stream_data, buffer_id:, data: text }
        notify.call
      end
    rescue EOFError, Errno::EIO
      # PTY は子プロセス終了時に EIO を送る
    end
    status = Process.waitpid2(pid)[1]
    queue << { type: :stream_eof, buffer_id:, status: status }
    notify.call
  end
end
```

バックグラウンドスレッドで PTY を開き、4KB ずつ読み取り、スレッドセーフなキュー（`Queue`）にイベントをプッシュする。`notify.call` は先述のシグナルパイプへの書き込みで、メインループをウェイクアップする。

> [!NOTE]
> シグナルパイプによるウェイクアップの仕組みは[起動シーケンス](ch-startup.md)と[メインループ](ch-mainloop.md)で解説している。

PTY を使うのは、多くのコマンドが PTY 接続時にのみカラー出力や行バッファリングを行うためだ。`chdir` 指定がある場合は `IO.popen` にフォールバックする（PTY は `chdir` をサポートしない）。

## StreamMixer — イベントの合流

`StreamMixer` は、複数のストリームからのイベントを 1 つのキューで受け取り、メインループの各サイクルで処理する。

```ruby
def drain_events!
  return false unless @stream_event_queue

  changed = false
  loop do
    event = @stream_event_queue.pop(true)   # non-blocking pop
    case event[:type]
    when :stream_data
      changed = apply_stream_chunk!(event[:buffer_id], event[:data]) || changed
    when :stream_eof
      changed = finish_stream!(event[:buffer_id], ...) || changed
    when :follow_data
      changed = apply_stream_chunk!(...) || changed
    when :file_lines
      changed = apply_async_file_lines!(...) || changed
    end
  end
rescue ThreadError   # キューが空
  changed
end
```

`Queue#pop(true)` はノンブロッキングで、キューが空なら `ThreadError` を投げる。これを `rescue` して「処理するイベントがなくなった」と判断する。

## 大規模ファイルの非同期読み込み

64MB 以上のファイルは非同期で読み込む。最初の 8MB を同期的に読み込んで即座に表示し、残りをバックグラウンドスレッドで追記する。

```ruby
def open_path_asynchronously!(path)
  file_size = File.size(path)
  buf = @editor.add_empty_buffer(path:)

  io = File.open(path, "rb")
  prefix = io.read(8 * 1024 * 1024)   # 最初の 8MB を同期読み込み

  # 改行で切る（中途半端な行を避ける）
  last_nl = prefix.rindex("\n".b)
  if last_nl && last_nl < prefix.bytesize - 1
    io.seek(-(prefix.bytesize - last_nl - 1), IO::SEEK_CUR)
    prefix = prefix[0..last_nl]
  end

  buf.append_stream_text!(Buffer.decode_text(prefix))

  # 残りをバックグラウンドで
  buf.stream = Stream::FileLoad.new(io:, file_size:, buffer_id: buf.id, ...)
end
```

プレフィックスを改行境界で切断するのは、行の途中でバッファが分断されるのを防ぐためだ。

> [!IMPORTANT]
> 非同期読み込み中も[バッファ](ch-buffer.md)の `append_stream_text!` が使われる。この操作は undo 履歴に記録されず、`@modified` フラグも変更しない。

## 自動追従

ストリーム出力のバッファで、カーソルが最終行にある場合、新しいデータが追加されると自動的にカーソルが最終行に移動する（`tail -f` のような動作）。

```ruby
def stream_window_following_end?(win, buf)
  last_row = buf.line_count - 1
  win.cursor_y >= last_row   # カーソルが最終行にいれば追従
end
```
