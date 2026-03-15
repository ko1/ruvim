# 起動シーケンス — App の初期化

> 「始まりは全体の半ばである」 — アリストテレスを引く西田幾多郎

`exe/ruvim` のエントリーポイントはたった 3 行だ。

```ruby
#!/usr/bin/env ruby
require "ruvim"
RuVim::CLI.run(ARGV)
```

`CLI.run` がコマンドライン引数をパースし、`App.new` を呼ぶ。`App` のコンストラクタは長いが、やっていることは明確だ。

```ruby
def initialize(path: nil, paths: nil, stdin: STDIN, ...)
  # 1. すべてのサブシステムを生成
  @terminal = Terminal.new(stdin:, stdout:)
  @input = Input.new(effective_stdin)
  @screen = Screen.new(terminal: @terminal)
  @dispatcher = Dispatcher.new
  @keymaps = KeymapManager.new

  # 2. シグナル通知用パイプ
  @signal_r, @signal_w = IO.pipe

  # 3. Editor にサブシステムを注入
  @editor = Editor.new(restricted_mode:, keymap_manager: @keymaps)
  @stream_mixer = StreamMixer.new(editor: @editor, signal_w: @signal_w)
  @editor.stream_mixer = @stream_mixer
  @key_handler = KeyHandler.new(
    editor: @editor,
    dispatcher: @dispatcher,
    completion: CompletionManager.new(editor: @editor)
  )

  # 4. Editor にコールバックを注入
  @editor.app_action_handler = @key_handler.method(:handle_editor_app_action)
  @editor.suspend_handler = -> { @terminal.suspend_for_tstp; ... }
  @editor.shell_executor = ->(command) { @terminal.suspend_for_shell(command); ... }

  # 5. 初期化の実行
  register_builtins!        # 組み込みコマンドを登録
  bind_default_keys!        # デフォルトキーバインドを設定
  load_user_config!         # ~/.config/ruvim/init.rb を読む
  open_startup_paths!(paths) # ファイルを開く
end
```

特筆すべき設計上のポイントがいくつかある。

## シグナルパイプ

`IO.pipe` で作った `@signal_r` / `@signal_w` のペアは、シグナルハンドラとメインループの通信に使われる。`SIGWINCH`（ターミナルリサイズ）が来たとき、シグナルハンドラは `@signal_w.write_nonblock(".")` で 1 バイト書き込む。メインループは `IO.select` で `@signal_r` も監視しているので、キー入力がなくても即座にウェイクアップし、画面を再描画できる。

```ruby
Signal.trap("WINCH") do
  @screen.invalidate_cache!
  @needs_redraw = true
  @signal_w.write_nonblock(".")
end
```

シグナルハンドラの中ではブロックする操作（mutex ロック、I/O 待ちなど）は禁止されている。`write_nonblock` は安全に使える数少ない操作の一つだ。

> [!WARNING]
> Ruby のシグナルハンドラ内で使える操作は非常に限られている。`IO#write_nonblock` やグローバル変数の代入は安全だが、`Mutex#lock` や `IO#write`（ブロッキング版）はデッドロックの原因になる。

## 起動時間の計測

`--startuptime` オプションを指定すると、初期化の各段階でモノトニッククロックのタイムスタンプを記録し、最後にファイルに出力する。

```ruby
def startup_mark(label)
  return unless @startup&.time_path
  @startup.timeline << [label.to_s, monotonic_now]
end

def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
```

`CLOCK_MONOTONIC` を使うのは、システムの壁時計時刻が NTP 調整で前後してもドリフトしないためだ。

> [!TIP]
> [メインループ](ch-mainloop.md)でもモノトニッククロックが一貫して使われている。詳しくは[設計パターン](ch-design-patterns.md#モノトニッククロックの一貫した使用)を参照。
