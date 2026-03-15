# メインループ — イベント駆動の心臓部

> 「流れる水は腐らず」 — 日本のことわざ

エディタのメインループは、驚くほどシンプルだ。

```ruby
def run
  @terminal.with_ui do
    loop do
      # 1. ストリームイベントを処理
      @needs_redraw = true if @stream_mixer.drain_events!

      # 2. 必要なら再描画
      if @needs_redraw
        @screen.render(@editor)
        @needs_redraw = false
      end

      # 3. 終了判定
      break unless @editor.running?

      # 4. キー入力を待つ
      key = @input.read_key(
        wakeup_ios: [@signal_r],
        timeout: @key_handler.loop_timeout_seconds,
        esc_timeout: @key_handler.escape_sequence_timeout_seconds
      )

      # 5. タイムアウト処理
      if key.nil?
        @needs_redraw = true if @key_handler.handle_idle_timeout
        next
      end

      # 6. キーを処理
      @key_handler.handle(key)
      @needs_redraw = true

      # 7. ペースト最適化
      if @editor.mode == :insert && @input.has_pending_input?
        @key_handler.paste_batch = true
        begin
          while @editor.mode == :insert && @input.has_pending_input?
            batch_key = @input.read_key(timeout: 0, esc_timeout: 0)
            break unless batch_key
            @key_handler.handle(batch_key)
          end
        ensure
          @key_handler.paste_batch = false
        end
      end
    end
  end
ensure
  @stream_mixer.shutdown!
  @key_handler.save_history!
end
```

ここで注目すべきは **[ペースト最適化](#index:ペースト最適化)** だ。ターミナルにテキストをペーストすると、数百〜数千のキー入力が一度にバッファに入る。各キーごとに画面を再描画していたら非常に遅くなる。そこで、インサートモード中にまだ読めるキーが残っている場合（`has_pending_input?`）、`paste_batch = true` を設定して再描画を抑制しつつ、一気に処理する。

```ruby
def has_pending_input?
  IO.select([@input], nil, nil, 0) != nil  # タイムアウト 0 = ノンブロッキング
end
```

## タイムアウトの管理

メインループの `IO.select` には 3 種類のタイムアウトが絡み合う。

1. **ペンディングキータイムアウト** (`timeoutlen`): `d` を押した後、次のキー（`d` で `dd`、`w` で `dw`）を待つ最大時間。デフォルト 1000ms。
2. **エスケープシーケンスタイムアウト** (`ttimeoutlen`): ESC が単独の Escape キーなのか、矢印キーなどのエスケープシーケンスの先頭なのかを判別する時間。デフォルト 50ms。
3. **一時メッセージの有効期限**: エコーエリアに表示した一時メッセージが消える時刻。

`loop_timeout_seconds` はこれらの最小値を返す。

> [!NOTE]
> タイムアウトの管理は [KeyHandler](ch-key-handler.md) のペンディング状態と密接に関連している。`timeoutlen` と `ttimeoutlen` の違いについては[キー入力](ch-key-input.md#esc-キーの曖昧さ)も参照。

```ruby
def loop_timeout_seconds
  now = monotonic_now
  timeouts = []
  timeouts << [@pending_key_deadline - now, 0.0].max if @pending_key_deadline
  timeouts << msg_to if (msg_to = @editor.transient_message_timeout_seconds(now:))
  timeouts.min
end
```
