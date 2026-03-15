# キー入力 — 生のバイト列を意味に変える

> 「一を聞いて十を知る」 — 論語を引く日本のことわざ

ロー (raw) モードの端末から読めるのは、ただのバイト列だ。`a` を押せば `0x61` が来るが、矢印キーの ↑ は `0x1B 0x5B 0x41`（ESC `[` `A`）という 3 バイトのシーケンスとして来る。これを意味のあるキーシンボルに変換するのが `Input` クラスの仕事だ。

```ruby
def read_key(timeout: nil, wakeup_ios: [], esc_timeout: nil)
  ios = [@input, *wakeup_ios].compact
  readable = IO.select(ios, nil, nil, timeout)
  return nil unless readable

  ready = readable[0]
  wakeups = ready - [@input]
  wakeups.each { |io| drain_io(io) }
  return nil unless ready.include?(@input)

  ch = @input.getch
  case ch
  when "\u0002" then :ctrl_b
  when "\u0003" then :ctrl_c
  # ... 他のコントロール文字 ...
  when "\r", "\n" then :enter
  when "\u007f", "\b" then :backspace
  when "\e" then read_escape_sequence(timeout: esc_timeout)
  else ch
  end
end
```

## ESC キーの曖昧さ

ターミナルの入力処理で最も厄介な問題の一つが、[ESC キーの曖昧さ](#index:ESC キーの曖昧さ)だ。

- ESC キー単体を押す → `0x1B` が 1 バイト来る
- 矢印キー ↑ を押す → `0x1B 0x5B 0x41` が 3 バイト来る

どちらも最初のバイトは `0x1B`（ESC）だ。これをどう区別するか？ 答は **タイムアウト** だ。

```ruby
def read_escape_sequence(timeout: nil)
  extra = +""
  recognized = {
    "[A" => :up,   "[B" => :down,
    "[C" => :right, "[D" => :left,
    "[1;2A" => :shift_up,  # ... etc
    "[5~" => :pageup,
    "[6~" => :pagedown
  }
  wait = timeout.nil? ? 0.005 : [timeout.to_f, 0.0].max
  begin
    while IO.select([@input], nil, nil, wait)
      extra << @input.read_nonblock(1)
      key = recognized[extra]
      return key if key
    end
  rescue IO::WaitReadable, EOFError
  end

  case extra
  when "" then :escape    # ESC の後に何も来なかった
  else [:escape_sequence, extra]  # 未知のシーケンス
  end
end
```

ESC を受け取った後、ごく短い時間（デフォルト 5ms, `ttimeoutlen` で設定可能）だけ追加のバイトを待つ。

- 時間内に `[A` が来たら → `:up`（矢印キー ↑）
- 何も来なかったら → `:escape`（ESC 単体）

認識済みのシーケンスに一致した時点で即座に返す。これにより、矢印キーの反応は遅延なく、ESC キーは `ttimeoutlen` ミリ秒だけ遅延する。Vim の `ttimeoutlen` と同じ仕組みだ。

> [!TIP]
> `ttimeoutlen` を短くするとESCの反応が速くなるが、ネットワーク越しのSSH接続ではエスケープシーケンスが分断されて矢印キーが効かなくなることがある。デフォルトの50msは多くの環境で良好なバランスだ。

## ウェイクアップ I/O

`read_key` の `wakeup_ios` パラメータに注目してほしい。メインループではここにシグナルパイプの読み取り端を渡している。

```ruby
key = @input.read_key(
  wakeup_ios: [@signal_r],
  timeout: @key_handler.loop_timeout_seconds,
  ...
)
```

`IO.select` は `@input`（stdin）と `@signal_r`（シグナルパイプ）の両方を監視する。ウィンドウリサイズのシグナルが来ると、`@signal_r` が読み取り可能になり、`IO.select` から復帰する。ウェイクアップ I/O からのデータは `drain_io` で捨てて、`nil` を返す（「キーは来なかったがウェイクアップした」）。
