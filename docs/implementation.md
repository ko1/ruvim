# RuVim 実装解説 — Ruby でテキストエディタを作る

この記事では、Ruby で書かれた Vim 風テキストエディタ **RuVim** の実装を、設計思想からコードの細部まで深く解説する。対象読者は、エディタのプログラミングに興味がある人、あるいは「面白いプログラムの中身を覗きたい」という好奇心を持つプログラマである。

---

## 目次

1. [全体像 — エディタとは何をするプログラムか](#1-全体像--エディタとは何をするプログラムか)
2. [起動シーケンス — App の初期化](#2-起動シーケンス--app-の初期化)
3. [メインループ — イベント駆動の心臓部](#3-メインループ--イベント駆動の心臓部)
4. [ターミナル制御 — 端末を乗っ取る](#4-ターミナル制御--端末を乗っ取る)
5. [キー入力 — 生のバイト列を意味に変える](#5-キー入力--生のバイト列を意味に変える)
6. [キーマッピング — 層状の解決とプレフィックスインデックス](#6-キーマッピング--層状の解決とプレフィックスインデックス)
7. [コマンドディスパッチ — キーから動作へ](#7-コマンドディスパッチ--キーから動作へ)
8. [KeyHandler — 状態機械の集合体](#8-keyhandler--状態機械の集合体)
9. [バッファ — テキストの器](#9-バッファ--テキストの器)
10. [ウィンドウ — バッファへの窓](#10-ウィンドウ--バッファへの窓)
11. [エディタ — 状態の統括者](#11-エディタ--状態の統括者)
12. [画面描画 — Screen と差分レンダリング](#12-画面描画--screen-と差分レンダリング)
13. [シンタックスハイライト — 色を付ける](#13-シンタックスハイライト--色を付ける)
14. [Unicode 対応 — 文字幅の深淵](#14-unicode-対応--文字幅の深淵)
15. [C 拡張 — ホットパスの高速化](#15-c-拡張--ホットパスの高速化)
16. [ストリーム — 非同期 I/O と外部プロセス](#16-ストリーム--非同期-io-と外部プロセス)
17. [Sixel — ターミナルに画像を描く](#17-sixel--ターミナルに画像を描く)
18. [設定システム — Ruby DSL による拡張](#18-設定システム--ruby-dsl-による拡張)
19. [テスト戦略 — エディタをどうテストするか](#19-テスト戦略--エディタをどうテストするか)
20. [設計パターンと判断の記録](#20-設計パターンと判断の記録)

---

## 1. 全体像 — エディタとは何をするプログラムか

テキストエディタは、一見シンプルなプログラムに見える。テキストを読み込み、ユーザーの入力に応じて編集し、ファイルに保存する。しかし実際に作ってみると、そこには驚くほど多くの技術的課題がある。

- **ターミナル制御**: 端末をロー（raw）モードに切り替え、エスケープシーケンスで画面を制御する
- **キー入力の解釈**: マルチバイトのエスケープシーケンスを正しくパースし、タイムアウトで曖昧さを解消する
- **モード管理**: Normal, Insert, Visual, Command-line など複数のモードで異なる振る舞いをする
- **テキスト操作**: undo/redo、テキストオブジェクト、レジスタ、マクロなど
- **Unicode**: 結合文字、CJK 全角文字、絵文字の表示幅を正しく扱う
- **非同期 I/O**: 外部コマンドの実行結果をリアルタイムに表示する
- **画面描画の最適化**: フレームごとの差分だけを端末に送る

RuVim のアーキテクチャは、これらの関心事を明確に分離している。

```
CLI (exe/ruvim) → CLI.parse() → App.new() → App.run_ui_loop()
  Input.read_key() → KeymapManager.resolve() → Dispatcher.dispatch()
  → GlobalCommands.<method>() → Editor state update → Screen.render() → Terminal.write()
```

主要なオブジェクトの依存関係は以下の通りだ。

```
App
├── Terminal ──── stdin/stdout I/O
├── Input ─────── キーボード入力パース（Terminal から読む）
├── Screen ────── 描画（Terminal に書く）
├── KeymapManager ── キーからコマンドへの解決
├── Dispatcher ──── コマンドルーティング
├── Editor ──────── バッファ、ウィンドウ、モード等の状態
├── StreamMixer ─── 非同期ストリームの調整
├── KeyHandler ──── キー処理、モード遷移、ペンディング状態
└── ConfigLoader ── ユーザー設定の読み込み
```

すべてのオブジェクトは `App` が生成し、依存注入（Dependency Injection）で結合する。グローバル変数やグローバルなシングルトンへの暗黙的な依存は避け、テスタビリティを確保している。

---

## 2. 起動シーケンス — App の初期化

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

### シグナルパイプ

`IO.pipe` で作った `@signal_r` / `@signal_w` のペアは、シグナルハンドラとメインループの通信に使われる。`SIGWINCH`（ターミナルリサイズ）が来たとき、シグナルハンドラは `@signal_w.write_nonblock(".")` で 1 バイト書き込む。メインループは `IO.select` で `@signal_r` も監視しているので、キー入力がなくても即座にウェイクアップし、画面を再描画できる。

```ruby
Signal.trap("WINCH") do
  @screen.invalidate_cache!
  @needs_redraw = true
  @signal_w.write_nonblock(".")
end
```

シグナルハンドラの中ではブロックする操作（mutex ロック、I/O 待ちなど）は禁止されている。`write_nonblock` は安全に使える数少ない操作の一つだ。

### 起動時間の計測

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

---

## 3. メインループ — イベント駆動の心臓部

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

ここで注目すべきは **ペースト最適化** だ。ターミナルにテキストをペーストすると、数百〜数千のキー入力が一度にバッファに入る。各キーごとに画面を再描画していたら非常に遅くなる。そこで、インサートモード中にまだ読めるキーが残っている場合（`has_pending_input?`）、`paste_batch = true` を設定して再描画を抑制しつつ、一気に処理する。

```ruby
def has_pending_input?
  IO.select([@input], nil, nil, 0) != nil  # タイムアウト 0 = ノンブロッキング
end
```

### タイムアウトの管理

メインループの `IO.select` には 3 種類のタイムアウトが絡み合う。

1. **ペンディングキータイムアウト** (`timeoutlen`): `d` を押した後、次のキー（`d` で `dd`、`w` で `dw`）を待つ最大時間。デフォルト 1000ms。
2. **エスケープシーケンスタイムアウト** (`ttimeoutlen`): ESC が単独の Escape キーなのか、矢印キーなどのエスケープシーケンスの先頭なのかを判別する時間。デフォルト 50ms。
3. **一時メッセージの有効期限**: エコーエリアに表示した一時メッセージが消える時刻。

`loop_timeout_seconds` はこれらの最小値を返す。

```ruby
def loop_timeout_seconds
  now = monotonic_now
  timeouts = []
  timeouts << [@pending_key_deadline - now, 0.0].max if @pending_key_deadline
  timeouts << msg_to if (msg_to = @editor.transient_message_timeout_seconds(now:))
  timeouts.min
end
```

---

## 4. ターミナル制御 — 端末を乗っ取る

テキストエディタがターミナル上で動作するには、端末を「乗っ取る」必要がある。通常のシェルでは、ユーザーが Enter を押すまで入力がバッファリングされ、`^C` でシグナルが送られる。エディタは 1 文字ずつリアルタイムに読みたいし、`^C` をキーとして受け取りたい。

### ロー (Raw) モード

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

### エスケープシーケンスによる端末制御

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

### Sixel サポート検出

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

### シェルへの一時退避

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

---

## 5. キー入力 — 生のバイト列を意味に変える

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

### ESC キーの曖昧さ

ターミナルの入力処理で最も厄介な問題の一つが、ESC キーの曖昧さだ。

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

### ウェイクアップ I/O

`read_key` の `wakeup_ios` パラメータに注目してほしい。メインループではここにシグナルパイプの読み取り端を渡している。

```ruby
key = @input.read_key(
  wakeup_ios: [@signal_r],
  timeout: @key_handler.loop_timeout_seconds,
  ...
)
```

`IO.select` は `@input`（stdin）と `@signal_r`（シグナルパイプ）の両方を監視する。ウィンドウリサイズのシグナルが来ると、`@signal_r` が読み取り可能になり、`IO.select` から復帰する。ウェイクアップ I/O からのデータは `drain_io` で捨てて、`nil` を返す（「キーは来なかったがウェイクアップした」）。

---

## 6. キーマッピング — 層状の解決とプレフィックスインデックス

Vim のキーマッピングは奥が深い。`dd`（行削除）、`dw`（ワード削除）、`d3w`（3 ワード削除）のように、複数キーの組み合わせでコマンドが決まる。さらに、ファイルタイプやバッファ固有のマッピングが通常のマッピングを上書きできる。

### LayerMap — プレフィックスインデックス付きハッシュ

`KeymapManager` の核心は `LayerMap` だ。これは `Hash` を継承し、**プレフィックスインデックス** を維持するデータ構造である。

```ruby
class LayerMap < Hash
  def initialize
    super
    @prefix_max_len = {}  # prefix → そのプレフィックスを持つキーの最大長
  end

  def []=(tokens, value)
    was_new = !key?(tokens)
    super
    add_to_prefix_index(tokens) if was_new
  end

  # このプレフィックスで始まるキーが存在するか？（O(1)）
  def has_prefix?(prefix)
    @prefix_max_len.key?(prefix)
  end

  # このプレフィックスより厳密に長いキーが存在するか？
  def has_longer_match?(prefix)
    max = @prefix_max_len[prefix]
    max ? max > prefix.length : false
  end

  private

  def add_to_prefix_index(tokens)
    len = tokens.length
    len.times do |i|
      pfx = tokens[0, i + 1].freeze
      cur = @prefix_max_len[pfx]
      @prefix_max_len[pfx] = len if cur.nil? || len > cur
    end
  end
end
```

例えば `["d", "d"]`（`dd`）というキーを登録すると、プレフィックスインデックスには以下が記録される。

```
["d"]     → 最大長 2
["d", "d"] → 最大長 2
```

これにより、ユーザーが `d` を押した時点で `has_prefix?(["d"])` が `true` を返し、「まだ続きがあるかもしれない」と判断できる。全キーをスキャンする必要がなく、O(1) で判定できる。

### 4 層の解決

キーの解決は以下の優先順位で行われる。

```ruby
def resolve_with_context(mode, pending_tokens, editor:)
  buffer = editor.current_buffer
  filetype = detect_filetype(buffer)
  layers = []
  layers << @filetype_maps[filetype][mode]   # 1. ファイルタイプ固有
  layers << @buffer_maps[buffer.id]          # 2. バッファ固有
  layers << @mode_maps[mode]                 # 3. モード固有
  layers << @global_map                      # 4. グローバル
  resolve_layers(layers, pending_tokens)
end
```

Vim と同じく、ファイルタイプ固有のマッピングが最優先で、グローバルが最低優先だ。

### マッチの 4 状態

解決結果は 4 つの状態を取る。

```ruby
def resolve_layers(layers, pending_tokens)
  layers.each do |layer|
    if (exact = layer[pending_tokens])
      longer = layer.has_longer_match?(pending_tokens)
      return Match.new(
        status: (longer ? :ambiguous : :match),
        invocation: exact
      )
    end
  end

  has_prefix = layers.any? { |layer| layer.has_prefix?(pending_tokens) }
  Match.new(status: has_prefix ? :pending : :none)
end
```

| 状態 | 意味 | 例 |
|---|---|---|
| `:match` | 完全一致、曖昧さなし | `j` → `cursor.down` |
| `:ambiguous` | 完全一致するが、より長いマッチもありうる | `g` は `gg` の前半にも一致 |
| `:pending` | まだ一致しないが、プレフィックスとしては有効 | `d` はまだ何のコマンドでもない |
| `:none` | 何にも一致しない | 未定義のキー |

`:ambiguous` の場合、タイムアウト（`timeoutlen`）を設定する。時間内に次のキーが来なければ、現在の完全一致を実行する。来れば、より長いキーシーケンスとして解決を続ける。

---

## 7. コマンドディスパッチ — キーから動作へ

キーマッピングの解決によって得られた `CommandInvocation` は、`Dispatcher` によってコマンドハンドラに送られる。

### Normal モードコマンドの実行

```ruby
def dispatch(editor, invocation)
  spec = @command_registry.fetch(invocation.id)
  ctx = Context.new(editor:, invocation:)
  @command_host.call(spec.call, ctx,
    argv: invocation.argv,
    kwargs: invocation.kwargs,
    bang: invocation.bang,
    count: invocation.count
  )
end
```

- `CommandRegistry` はシングルトンで、コマンド ID → スペック（ハンドラ関数、説明文など）のマップを持つ
- `Context` は `editor`, `invocation` をバンドルし、コマンドハンドラに渡す文脈オブジェクト
- `GlobalCommands` がすべてのコマンドハンドラのホストとなる

### Ex コマンドの解析パイプライン

`:` で始まるコマンドラインは、より複雑な解析パイプラインを通る。

```ruby
def dispatch_ex(editor, line)
  # 1. シェルコマンド
  if raw.start_with?("!")
    @command_host.shell_command(ctx, command:)
    return
  end

  # 2. レンジプレフィックスの解析（例: %s, 1,5d, '<,'>）
  range_result = parse_range(raw, editor)

  # 3. global/vglobal コマンドの検出
  if (glob = parse_global(rest))
    @command_host.global_command(ctx, **kwargs)
    return
  end

  # 4. substitute コマンドの検出
  if (sub = parse_substitute(rest))
    @command_host.substitute(ctx, **kwargs)
    return
  end

  # 5. 通常の Ex コマンドとして解析
  parsed = parse_ex(rest)
  spec = @ex_registry.resolve(parsed.name)
  @command_host.call(spec.call, ctx, ...)
end
```

#### レンジの解析

Vim のレンジ指定は複雑だ。`%`（ファイル全体）、`.`（現在行）、`$`（最終行）、`'a`（マーク位置）、数字、`+`/`-` オフセットをサポートする。

```ruby
def parse_address(str, pos, editor)
  ch = str[pos]
  case ch
  when /\d/
    m = str[pos..].match(/\A(\d+)/)
    base = m[1].to_i - 1   # 1-based → 0-based
  when "."
    base = editor.current_window.cursor_y
  when "$"
    base = editor.current_buffer.line_count - 1
  when "'"
    mark_ch = str[pos + 1]
    loc = editor.mark_location(mark_ch)
    base = loc[:row]
  end

  # +N / -N オフセットの後続解析
  while new_pos < str.length
    case str[new_pos]
    when "+" then base += ...
    when "-" then base -= ...
    else break
    end
  end

  base = [[base, 0].max, max_line].min   # クランプ
  [base, new_pos]
end
```

#### substitute のパース

`:s/pattern/replacement/flags` は区切り文字（通常は `/`）で分割されるが、実際には任意の文字を区切りに使える（`:s#old#new#g` のように）。区切り文字の中で `\` によるエスケープも扱う。

```ruby
def parse_substitute(line)
  return nil unless raw.match?(/\As[^a-zA-Z]/)

  delim = raw[1]                  # 2 文字目が区切り
  pat, i = parse_delimited_segment(raw, 2, delim)
  rep, i = parse_delimited_segment(raw, i, delim)
  flags_str = raw[i..]
  { pattern: pat, replacement: rep, flags_str: flags_str }
end
```

---

## 8. KeyHandler — 状態機械の集合体

`KeyHandler` はエディタの中で最も複雑なコンポーネントの一つだ。Normal モードのキー入力には、驚くほど多くの「ペンディング状態」がある。

```ruby
@operator_pending      # d, y, c, = の後、モーションを待っている
@register_pending      # " の後、レジスタ名を待っている
@mark_pending          # m の後、マーク名を待っている
@jump_pending          # ' や ` の後、マーク名を待っている
@find_pending          # f, t, F, T の後、文字を待っている
@replace_pending       # r の後、置換文字を待っている
@macro_record_pending  # q の後、マクロ名を待っている
@macro_play_pending    # @ の後、マクロ名を待っている
```

### Normal モードのキー処理

キーが来たとき、以下の優先順位で処理される。

```ruby
def handle_normal_key(key)
  case
  when handle_normal_key_pre_dispatch(key)    # カウント数字の処理
  when (token = normalize_key_token(key)).nil?
  when handle_normal_pending_state(token)     # ペンディング状態の解決
  when handle_normal_direct_token(token)
  else
    @pending_keys ||= []
    @pending_keys << token
    resolve_normal_key_sequence                # キーシーケンスの解決
  end
end
```

### オペレータ + モーション

Vim の `d` + モーション（`dw`, `d$`, `d3j` など）は、オペレータペンディング状態で実現される。

1. `d` が押される → `start_operator_pending(:delete)` でオペレータをセット
2. 次のキー（例えば `w`）が来る → `handle_operator_pending_key` でモーションとして解決
3. 二重オペレータ（`dd`）も特別に処理：オペレータキーが 2 回来たら行全体に適用

テキストオブジェクト（`iw`, `a(`）もモーション接頭辞（`i`, `a`, `g`）として扱い、2 ストロークの入力を待つ。

### ドットリピート

Vim の `.` コマンドは、最後の変更操作を繰り返す。これは一見単純だが、「最後の変更操作」の境界を正しく定義するのが難しい。

```ruby
# 変更操作の開始時にキャプチャを開始
def begin_dot_change_capture
  return if dot_replaying?
  @dot_change_capture_active = true
  @dot_change_capture_keys = []
end

# 各キーを記録
def append_dot_change_capture_key(key)
  return unless @dot_change_capture_active
  @dot_change_capture_keys << key
end

# 変更操作の終了時にキャプチャを完了
def finish_dot_change_capture
  return unless @dot_change_capture_active
  @dot_change_capture_active = false
  @last_change_keys = @dot_change_capture_keys
  @dot_change_capture_keys = nil
end
```

`.` が押されると、記録されたキーシーケンスを再生する。

```ruby
def repeat_last_change
  return unless @last_change_keys && !@last_change_keys.empty?
  @dot_replay_depth = (@dot_replay_depth || 0) + 1
  begin
    @last_change_keys.each { |k| handle(k) }
  ensure
    @dot_replay_depth -= 1
    @dot_replay_depth = nil if @dot_replay_depth <= 0
  end
end
```

`dot_replay_depth` による深度追跡は、ドットリピートの再生中にさらにドット用のキャプチャが起動しないようにするためだ。

### マクロ

マクロ（`q<reg>` で記録、`@<reg>` で再生）は、ドットリピートと似た仕組みだが、名前付きレジスタに保存される。

```ruby
MAX_MACRO_DEPTH = 20

def play_macro(name)
  raise RuVim::CommandError, "Macro depth exceeded" if @macro_play_stack.length >= MAX_MACRO_DEPTH
  keys = @editor.registers[name]
  return unless keys

  @macro_play_stack.push(name)
  suspend_macro_recording do
    keys.each { |k| handle(k) }
  end
ensure
  @macro_play_stack.pop
end
```

マクロの再帰呼び出しを防ぐため、最大深度を 20 に制限している。また、マクロの再生中は録音を一時停止する（でないと、再生中のキーが別のマクロに記録されてしまう）。

大文字のレジスタ名（`qA`）は、既存のマクロに追記する仕様も Vim 互換で実装されている。

---

## 9. バッファ — テキストの器

`Buffer` はテキストデータを保持する器だ。1 つのファイル（または名前なしバッファ）に対応する。

### データ構造

テキストの内部表現は、**行の配列（`Array<String>`）** だ。

```ruby
def initialize(id:, path: nil, lines: [""], ...)
  @lines = lines.dup
  @lines = [""] if @lines.empty?   # 常に最低 1 行を保持
  @undo_stack = []
  @redo_stack = []
  @change_group_depth = 0
end
```

この選択にはトレードオフがある。

- **利点**: 行単位のアクセスが O(1)。Vim の操作モデル（行指向のモーション、`dd` による行削除、`yy` による行ヤンク）と自然に対応する。シンタックスハイライトも行単位で処理する。
- **欠点**: 行の挿入・削除は O(n)（配列の移動）。しかし実際には Ruby の `Array#insert` / `Array#delete_at` は C 実装の `memmove` で十分高速。

Rope やピーステーブルのような高度なデータ構造は使わず、シンプルな配列を選んでいる。数百万行のファイルでない限り、この選択は正しい。

### ファイルの読み込みとエンコーディング

```ruby
def self.decode_text(bytes)
  s = bytes.to_s
  return s.dup if s.encoding == Encoding::UTF_8 && s.valid_encoding?

  utf8 = s.dup.force_encoding(Encoding::UTF_8)
  return utf8 if utf8.valid_encoding?

  ext = Encoding.default_external
  if ext && ext != Encoding::UTF_8
    return utf8.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  utf8.scrub
end
```

まず UTF-8 として解釈を試み、無効なら外部エンコーディングから変換する。それでもダメなら `scrub`（不正バイトを置換文字に変える）する。決してクラッシュしない。

### Undo/Redo — スナップショット方式

RuVim のアンドゥは **スナップショット方式** を採用している。変更前の行配列のコピーをスタックに保存する。

ただし、素朴に全行をディープコピー（`@lines.map(&:dup)`）すると、10 万行のファイルで 100 回の undo を重ねた場合にメモリが爆発する。

RuVim はこの問題を **構造共有（structural sharing）** で解決している。スナップショットは `@lines.dup`（配列の浅いコピー）だけを取り、個々の文字列オブジェクトは共有する。これが安全なのは、Buffer の全ての変更メソッドが文字列を in-place で変更せず、常に新しい文字列を生成して代入するからだ。

```ruby
# insert_char: line.dup.insert() で新しい文字列を作り、@lines[row] に代入
def insert_char(row, col, char)
  record_change_before_mutation!
  line = @lines.fetch(row)
  @lines[row] = line.dup.insert(col, char)  # 元の line は変更されない
  @modified = true
end
```

スナップショットと `@lines` が同じ文字列オブジェクトを指していても、変更は常に新しいオブジェクトとして作られるので、スナップショット側の文字列は壊れない。

```ruby
def record_change_before_mutation!
  ensure_modifiable!
  return if @recording_suspended

  if @change_group_depth.positive?
    unless @group_changed
      @group_before_snapshot = snapshot
      @group_changed = true
    end
    return
  end

  @undo_stack << snapshot
  @redo_stack.clear
end

def snapshot
  { lines: @lines.dup, modified: @modified }  # 浅いコピー: 未変更行は共有
end
```

この方式により、1 行だけ変更した場合のスナップショットは、配列オブジェクト 1 つ（数十バイト）+ 変更された行の新しい文字列 1 つだけの追加メモリで済む。10 万行のファイルでも、未変更の 99,999 行は参照を共有する。

#### チェンジグループ

`dw`（ワード削除）は複数の低レベル操作（文字削除の繰り返し）から成る。これらをまとめて 1 回の undo で元に戻すために、チェンジグループがある。

```ruby
def begin_change_group
  @change_group_depth += 1
end

def end_change_group
  @change_group_depth -= 1
  return unless @change_group_depth.zero?

  if @group_changed && @group_before_snapshot
    @undo_stack << @group_before_snapshot   # グループの最初のスナップショットだけ保存
    @redo_stack.clear
  end
  @group_before_snapshot = nil
  @group_changed = false
end
```

深度カウンタにより、チェンジグループは入れ子にできる。最外周のグループが閉じたときだけスナップショットがスタックにプッシュされる。

### 永続 Undo

バッファの Undo 履歴はファイルに保存・復元できる。パスは SHA-256 ハッシュで一意に決まる。

```ruby
def undo_file_path(undodir)
  require "digest"
  hash = Digest::SHA256.hexdigest(File.expand_path(@path))
  File.join(undodir, hash)
end

def save_undo_file(undodir)
  data = Marshal.dump({ undo: @undo_stack, redo: @redo_stack })
  File.binwrite(uf, data)
end
```

`Marshal.dump` / `Marshal.load` による素朴なシリアライズだが、undo スタックの中身は行配列のコピーだけなので、互換性の問題は起きにくい。

### ストリーム対応

バッファは外部ストリーム（コマンド出力、ファイル監視など）からデータを受け取れる。

```ruby
def append_stream_text!(text)
  return [@lines.length - 1, @lines[-1].length] if text.empty?

  parts = text.split("\n", -1)
  head = parts.shift || ""
  @lines[-1] = @lines[-1] + head     # 最終行に追記
  @lines.concat(parts)               # 残りの行を追加
  @modified = false                   # ストリーム追記は「変更」扱いしない
  [@lines.length - 1, @lines[-1].length]
end
```

ストリームからのデータは undo 履歴に記録しない。また `@modified = false` として、「保存されていない変更がある」という警告を出さないようにしている。

---

## 10. ウィンドウ — バッファへの窓

`Window` はバッファの特定の領域を表示するビューポートだ。1 つのバッファに対して複数のウィンドウを開ける。ウィンドウはカーソル位置とスクロールオフセットを持つ。

### グラフェム単位のカーソル移動

左右の移動は、バイト単位でも文字単位でもなく、**グラフェム・クラスタ単位** で行う。

```ruby
def move_left(buffer, count = 1)
  @preferred_x = nil
  count.times do
    break if @cursor_x <= 0
    @cursor_x = RuVim::TextMetrics.previous_grapheme_char_index(
      buffer.line_at(@cursor_y), @cursor_x
    )
  end
  clamp_to_buffer(buffer)
end
```

グラフェム・クラスタとは、人間が「1 文字」と認識する単位だ。例えば「が」（U+304B U+3099、か + 濁点結合文字）は 2 コードポイントだが 1 グラフェムだ。絵文字の合字（👨‍👩‍👧‍👦）は複数のコードポイントと ZWJ で構成されるが、やはり 1 グラフェムだ。`TextMetrics.previous_grapheme_char_index` は `\X` 正規表現（Unicode 拡張グラフェム・クラスタ境界）を使ってこれを正しく処理する。

### 垂直移動と preferred_x

上下に移動するとき、行の長さが異なることがある。`@preferred_x` は「元いた x 座標」を記憶する。

```ruby
def move_up(buffer, count = 1)
  desired_x = @preferred_x || @cursor_x
  @cursor_y -= count
  clamp_to_buffer(buffer)
  @cursor_x = [desired_x, buffer.line_length(@cursor_y)].min
  @preferred_x = desired_x
end
```

例えば 80 文字の行のカラム 75 にカーソルがあり、↑ で 20 文字の行に移動すると、カーソルは 20 文字目に行く。さらに ↑ でまた 80 文字の行に移動すると、カーソルは 75 文字目に戻る。`@preferred_x` がなければ、20 文字目のままになってしまう。

`move_left` や `move_right` が `@preferred_x = nil` をセットしていることに注目。水平移動は preferred_x をリセットする。

### スクロールの確保

```ruby
def ensure_visible(buffer, height:, width:, tabstop: 2, scrolloff: 0, sidescrolloff: 0)
  clamp_to_buffer(buffer)
  so = [[scrolloff, 0].max, [height - 1, 0].max].min

  # 垂直スクロール
  top_target = @cursor_y - so
  bottom_target = @cursor_y + so
  @row_offset = top_target if top_target < @row_offset
  @row_offset = bottom_target - height + 1 if bottom_target >= @row_offset + height

  # 水平スクロール
  cursor_screen_col = TextMetrics.screen_col_for_char_index(line, @cursor_x, tabstop:)
  # ... sidescrolloff に基づく col_offset の調整
end
```

`scrolloff` はカーソルの上下に常に見えるようにする行数だ。3 に設定すると、カーソルの上下 3 行は常に表示される。`sidescrolloff` は水平方向の同等の機能だ。

水平スクロールでは画面列（表示幅）と文字インデックス（内部位置）の変換が必要になる。タブや全角文字の存在により、これは単純な 1:1 対応ではない。`TextMetrics.screen_col_for_char_index` と `char_index_for_screen_col` がこの変換を担う。

---

## 11. エディタ — 状態の統括者

`Editor` はアプリケーション全体の状態を管理する中心的なオブジェクトだ。

- **バッファの管理**: `@buffers`（id → Buffer のハッシュ）
- **ウィンドウの管理**: `@windows`（id → Window のハッシュ）
- **レイアウトツリー**: `@layout_tree`（ウィンドウ分割の階層構造）
- **タブページ**: `@tabpages`（レイアウトツリーの配列）
- **モード管理**: `@mode`（`:normal`, `:insert`, `:visual_char` など）
- **ビジュアル選択**: `@visual_state`
- **レジスタ**: `@registers`
- **マーク**: `@marks`
- **ジャンプリスト**: `@jump_list`
- **Quickfix / ロケーションリスト**: `@quickfix_items`, `@location_lists`
- **オプション**: グローバル/ウィンドウ/バッファの 3 スコープ

### オプションシステム

Vim のオプションは、スコープ（グローバル、ウィンドウローカル、バッファローカル）と型（boolean, number, string）を持つ。

```ruby
OPTION_DEFS = {
  "number"     => { scope: :window,  type: :bool,   default: false },
  "tabstop"    => { scope: :buffer,  type: :number, default: 2 },
  "filetype"   => { scope: :buffer,  type: :string, default: "" },
  "scrolloff"  => { scope: :global,  type: :number, default: 0 },
  # ... 51 以上のオプション定義
}
```

`effective_option` は、ウィンドウローカル → グローバルの順に値を解決する。

### レイアウトツリー

ウィンドウの分割は木構造で表現される。

```
{ type: :hsplit, children: [
    { type: :window, id: 1 },
    { type: :vsplit, children: [
        { type: :window, id: 2 },
        { type: :window, id: 3 }
    ]}
]}
```

このツリーを再帰的に走査して、各ウィンドウの矩形（行、列、幅、高さ）を計算する。

---

## 12. 画面描画 — Screen と差分レンダリング

`Screen` クラスは、エディタの状態を端末の文字列に変換する。

### 2 フェーズレンダリング

描画は 2 フェーズで行われる。

1. **フレーム構築**: 各画面行の内容を文字列として構築する
2. **差分出力**: 前回のフレームと比較し、変化した行だけを端末に送る

```ruby
def render(editor)
  # フレーム構築
  new_frame = build_frame(editor, rows, cols)

  # 差分出力
  if @last_frame
    new_frame.each_with_index do |line, i|
      next if line == @last_frame[i]   # 同一なら skip
      output << "\e[#{i + 1};1H#{line}\e[K"
    end
  else
    # 初回はフル描画
  end

  @last_frame = new_frame
  @terminal.write(output)
end
```

`\e[#{i + 1};1H` はカーソルを指定行に移動する ANSI シーケンス、`\e[K` は行末までクリアする。変更のない行はスキップするので、大きなファイルでもスクロールしない限り出力量は少ない。

### キャッシュ

パフォーマンスのために 2 つのキャッシュを維持する。

```ruby
@syntax_color_cache = {}       # バッファ行内容 → 色情報（上限 2048 エントリ）
@wrapped_segments_cache = {}   # 行内容 → 折り返しセグメント（上限 1024 エントリ）
```

同じ行の内容が変わらない限り、シンタックスハイライトの計算をスキップできる。LRU ではなくサイズ上限付きのハッシュだが、描画ループでは通常画面に表示されている行だけが参照されるため、実用的には十分だ。

### レイアウト合成

複数ウィンドウのレイアウトは、レイアウトツリーを走査して各画面行の「行計画（row plan）」を構築することで実現する。各行計画は、どのウィンドウの何行目をどのカラムからどの幅で描画するかを記述する。ウィンドウ間にはセパレータ（`│` や `─`）が描画される。

### バッファ文字列から画面セルへの変換

バッファは行を Ruby の String として保持する。しかし、1 文字がターミナル上で何カラム消費するかは文字によって異なる。ASCII は 1 カラム、CJK 文字は 2 カラム、タブは `tabstop` 設定に依存し、結合文字は 0 カラムだ。この「文字インデックス」と「画面カラム」のギャップを吸収するのが **Cell** 抽象だ。

```ruby
class Cell
  attr_reader :glyph          # 表示する文字（タブは " "、制御文字は "?"）
  attr_reader :source_col     # バッファ行内の文字インデックス
  attr_reader :display_width  # この文字が占める画面カラム数
end
```

`TextMetrics.clip_cells_for_width` がバッファの文字列を Cell の配列に変換する。

```ruby
def clip_cells_for_width(text, width, source_col_start: 0, tabstop: 2)
  cells = []
  display_col = 0

  text.each_char do |ch|
    code = ch.ord
    # ASCII 高速パス
    if code >= 0x20 && code <= 0x7E
      break if display_col >= width
      cells << Cell.new(ch, source_col, 1)
      display_col += 1
      source_col += 1
      next
    end

    if ch == "\t"
      w = tabstop - (display_col % tabstop)  # 次のタブ位置まで
      break if display_col + w > width
      w.times { cells << Cell.new(" ", source_col, 1) }  # 空白セルに展開
      display_col += w
      source_col += 1    # バッファ上は 1 文字
      next
    end
    # ... 制御文字 → "?"、CJK → display_width: 2
  end
  [cells, display_col]
end
```

ここに重要な設計がある。**タブ文字は複数の Cell に展開されるが、すべての Cell が同じ `source_col` を持つ**。つまり、画面上のカラム位置からバッファの文字位置を逆引きできる。ビジュアル選択や検索ハイライトが `source_col` を使って色付けの要否を判定するため、タブ展開が正しく動作する。

### 描画のレイヤー構造

Cell 配列ができたら、各セルに色を重ねていく。色の決定は **優先度順** で、最初にマッチした条件が採用される。

```
カーソル位置     → 反転表示 (\e[7m)
ビジュアル選択   → 反転表示 (\e[7m)
検索ハイライト   → 黄色背景 (\e[43m)
カラーカラム     → 灰色背景
カーソル行       → 背景色
シンタックス色   → 各言語モジュールの色 + スペルチェック下線（併用可）
スペルチェック   → 赤下線 (\e[4;31m)
なし             → 素の文字
```

```ruby
cells.each do |cell|
  ch = display_glyph_for_cell(cell, ...)  # list モードでの表示文字変換
  buffer_col = cell.source_col

  if cursor_here
    highlighted << cursor_cell_render(editor, ch)
  elsif selected
    highlighted << "\e[7m#{ch}\e[m"
  elsif search_cols[buffer_col]
    highlighted << "#{search_bg_seq(editor)}#{ch}\e[m"
  elsif (syntax_color = syntax_cols[buffer_col])
    highlighted << "#{syntax_color}#{ch}\e[m"
  else
    highlighted << ch
  end
end
```

色情報はすべて `{ 文字インデックス => ANSI エスケープ文字列 }` のハッシュとして提供される。シンタックスハイライト、検索マッチ、スペルチェックが同じインターフェースを持つことで、描画コードは色の出所を知る必要がない。

### 高速パス — 色も特殊文字もない行

画面に見えるすべての行で Cell を生成するのは無駄が多い。条件が揃えば、**文字列のスライスだけで済む**高速パスを通る。

```ruby
def can_bulk_render_line?(text, ...)
  return false if cursor_on_this_line     # カーソル行は描画が特殊
  return false if visual_active?          # 選択範囲がある
  return false if text.include?("\t")     # タブは展開が必要
  return false unless text.ascii_only?    # CJK は幅計算が必要
  return false unless syntax_cols.empty?  # ハイライトがある
  return false unless search_cols.empty?  # 検索マッチがある
  true
end

def bulk_render_line(text, width, col_offset:)
  clipped = text[col_offset, width].to_s
  clipped + (" " * [width - clipped.length, 0].max)  # 右パディング
end
```

ASCII のみでハイライトも特殊文字もない行は、単純な `String#[]` でクリップして空白を埋めるだけだ。Cell オブジェクトの生成も ANSI エスケープの出力も不要で、大量のプレーンテキストで効果が大きい。

### 編集による再描画の流れ

ユーザーが文字を挿入すると、以下の連鎖が起きる。

```
キー入力 → Buffer#insert_char → @lines[row] = 新しい文字列
→ App#run_ui_loop が @needs_redraw を検出
→ Screen#render → build_frame
→ 変更された行: Cell 変換 → 色重ね → 文字列化
→ 未変更の行: @last_frame と同一 → スキップ
→ 差分出力: 変更行だけ端末に送信
```

ここでキャッシュの無効化は **暗黙的** に起きる。バッファの行が編集されると新しい文字列オブジェクトが生成される（`insert_char` の `line.dup.insert(col, char)` による）。シンタックスキャッシュは `[言語モジュール, 行テキスト]` をキーとするため、文字列が変われば自動的にキャッシュミスし、再計算される。明示的な invalidation は不要だ。

さらに、差分レンダリングにより、編集で変わった行だけが端末に送信される。10 万行のファイルで 1 行だけ変更しても、出力されるのはその 1 行のエスケープシーケンスだけだ。

### 座標系の変換

エディタ内では 3 つの座標系が共存する。

| 座標系 | 単位 | 用途 |
|--------|------|------|
| バッファ座標 | `(行番号, 文字インデックス)` | カーソル位置、テキスト操作 |
| 画面座標 | `(行番号, 画面カラム)` | 描画位置の計算 |
| ターミナル座標 | `(行番号, カラム)` | ANSI エスケープの出力先 |

バッファ座標から画面座標への変換は `TextMetrics.screen_col_for_char_index` が担う。

```ruby
def screen_col_for_char_index(line, char_index, tabstop: 2)
  prefix = line[0...char_index].to_s
  DisplayWidth.display_width(prefix, tabstop:)
end
```

逆方向（画面座標 → バッファ座標）は `char_index_for_screen_col` だ。マウスクリックや水平スクロールで使われる。

ウィンドウの `col_offset`（水平スクロール量）はバッファ座標（文字インデックス）で保持し、描画時に画面座標に変換する。カーソル位置 `cursor_x` もバッファ座標だ。レイアウトツリーから算出された矩形のオフセットを加算して、最終的なターミナル座標（`\e[行;列H` で使う値）を得る。

---

## 13. シンタックスハイライト — 色を付ける

### Lang::Base — 色付けの基盤

すべての言語モジュールは `Lang::Base` を継承する。

```ruby
class Base
  def self.instance
    @instance ||= new.freeze   # フリーズしたシングルトン
  end

  KEYWORD_COLOR  = "\e[36m"   # シアン
  STRING_COLOR   = "\e[32m"   # 緑
  NUMBER_COLOR   = "\e[33m"   # 黄
  COMMENT_COLOR  = "\e[90m"   # 暗いグレー
  VARIABLE_COLOR = "\e[93m"   # 明るい黄
  CONSTANT_COLOR = "\e[96m"   # 明るいシアン

  def apply_regex(cols, text, regex, color, override: false)
    text.to_enum(:scan, regex).each do
      m = Regexp.last_match
      (m.begin(0)...m.end(0)).each do |idx|
        next if cols.key?(idx) && !override
        cols[idx] = color
      end
    end
  end
end
```

`apply_regex` は、テキストに正規表現を適用し、マッチした範囲に色を割り当てる。`override: false` の場合、既に色が付いている位置はスキップする。これにより、優先順位を制御できる。例えば、コメントの色は他のどの色よりも優先される（`override: true`）。

### Lang::Ruby — Prism による正確なハイライト

Ruby のシンタックスハイライトは、正規表現ベースではなく **Prism レキサー** を使う。Prism は Ruby の公式パーサで、正確なトークン列を返す。

```ruby
class Ruby < Base
  def color_columns(text)
    cols = {}
    Prism.lex(text).value.each do |entry|
      token = entry[0]
      type = token.type
      range = token.location.start_offset...token.location.end_offset

      if PRISM_STRING_TYPES.include?(type)
        range.each { |idx| cols[idx] = STRING_COLOR unless cols.key?(idx) }
      elsif PRISM_KEYWORD_TYPES.include?(type)
        range.each { |idx| cols[idx] = KEYWORD_COLOR unless cols.key?(idx) }
      elsif PRISM_COMMENT_TYPES.include?(type)
        range.each { |idx| cols[idx] = COMMENT_COLOR }   # コメントは上書き
      end
      # ...
    end
    cols
  end
end
```

Prism を使うことで、正規表現では正しく扱えないケース（ヒアドキュメント、文字列補間内のコード、複数行コメントなど）も正確に色付けできる。

他の言語（JSON, YAML, Markdown, C, Go, Rust, Python, ...）は正規表現ベースの `apply_regex` で実装されている。言語ごとのモジュールは `autoload` で必要になるまでロードされない。

### インデント支援

各言語モジュールは、インデントのためのフックも提供する。

```ruby
# 行がインデントを増やすか？
def indent_trigger?(line)
  stripped = line.to_s.rstrip.lstrip
  first_word = stripped[/\A(\w+)/, 1].to_s
  return true if %w[def class module if unless ...].include?(first_word)
  return true if stripped.match?(/\bdo\s*(\|[^|]*\|)?\s*$/)
  false
end

# デデント（インデント減少）のトリガー文字
DEDENT_TRIGGERS = {
  "d" => /\A(\s*)end\z/,
  "e" => /\A(\s*)(?:else|rescue|ensure)\z/,
  "f" => /\A(\s*)elsif\z/,
  "n" => /\A(\s*)(?:when|in)\z/
}
```

ユーザーが `end` と入力すると、`d` の入力時にデデントトリガーがチェックされ、自動的にインデントが減少する。

### on_save フック

Ruby ファイルの場合、保存時に `ruby -wc`（シンタックスチェック）を実行し、エラーがあれば Quickfix リストにセットする。

```ruby
def on_save(ctx, path)
  output, status = Open3.capture2e("ruby", "-wc", path)
  unless status.success?
    items = message.lines.filter_map { |line|
      if line =~ /\A.+?:(\d+):/
        { buffer_id:, row: $1.to_i - 1, col: 0, text: line.strip }
      end
    }
    ctx.editor.set_quickfix_list(items)
    ctx.editor.echo_error("#{first}#{hint}")
  end
end
```

C/C++ ファイルでは `gcc -fsyntax-only` / `g++ -fsyntax-only` が同様に使われる。

---

## 14. Unicode 対応 — 文字幅の深淵

テキストエディタにおける Unicode 対応は、表面的な「UTF-8 を扱えます」を遥かに超える問題だ。最大の課題は **表示幅** の計算である。

### 問題

ターミナルは固定幅グリッドで文字を表示する。ASCII 文字は 1 セルだが、CJK 文字（漢字、ひらがな等）は 2 セル分の幅を取る。絵文字も通常 2 セルだ。結合文字（例: `e` + `́` → `é`）は前の文字に重なるため幅 0 だ。

これを正しく計算しないと、カーソル位置がずれる。「こんにちは」の「に」にカーソルがあるはずが、「ち」の位置に表示される、といった問題が起きる。

### DisplayWidth モジュール

```ruby
module DisplayWidth
  def cell_width(ch, col: 0, tabstop: 2)
    return 1 if ch.nil? || ch.empty?

    # タブ: タブストップに揃える（可変幅）
    if ch == "\t"
      width = tabstop - (col % tabstop)
      return width.zero? ? tabstop : width
    end

    # ASCII の高速パス
    return 1 if ch.bytesize == 1

    code = ch.ord
    uncached_codepoint_width(code)
  end

  def uncached_codepoint_width(code)
    return 0 if combining_mark?(code)      # 結合文字: 幅 0
    return 0 if zero_width_codepoint?(code) # ZWJ など: 幅 0
    return ambiguous_width if ambiguous_codepoint?(code)  # 曖昧文字
    return 2 if emoji_codepoint?(code)     # 絵文字: 幅 2
    return 2 if wide_codepoint?(code)      # CJK: 幅 2
    1                                       # その他: 幅 1
  end
end
```

#### コードポイント範囲の分類

```ruby
def combining_mark?(code)
  (0x0300..0x036F).cover?(code) ||   # Combining Diacritical Marks
    (0x1AB0..0x1AFF).cover?(code) || # Combining Diacritical Marks Extended
    (0x1DC0..0x1DFF).cover?(code) || # Combining Diacritical Marks Supplement
    (0x20D0..0x20FF).cover?(code) || # Combining Diacritical Marks for Symbols
    (0xFE20..0xFE2F).cover?(code)    # Combining Half Marks
end

def wide_codepoint?(code)
  (0x1100..0x115F).cover?(code) ||   # Hangul Jamo
    (0x2E80..0xA4CF).cover?(code) || # CJK Radicals 〜 Yi Radicals
    (0xAC00..0xD7A3).cover?(code) || # Hangul Syllables
    (0xF900..0xFAFF).cover?(code) || # CJK Compatibility Ideographs
    # ... 他
end
```

#### 曖昧幅文字

Unicode には「曖昧幅（Ambiguous Width）」という文字カテゴリがある。ギリシャ文字（α, β）や罫線文字（─, │）などは、東アジアの端末では幅 2、西洋の端末では幅 1 で表示される。

```ruby
def ambiguous_width
  env = ::ENV["RUVIM_AMBIGUOUS_WIDTH"]
  (env == "2" ? 2 : 1)
end
```

`RUVIM_AMBIGUOUS_WIDTH=2` 環境変数で切り替えられる。

#### タブの可変幅

タブ文字の幅は固定ではなく、**現在の表示位置** に依存する。

```
位置 0: タブ → 幅 4 (tabstop=4 の場合、次の 4 の倍数まで)
位置 1: タブ → 幅 3
位置 3: タブ → 幅 1
位置 4: タブ → 幅 4
```

`cell_width` が `col:` パラメータを受け取るのはこのためだ。

---

## 15. C 拡張 — ホットパスの高速化

DisplayWidth と TextMetrics の計算は、画面描画のたびに何千回も呼ばれるホットパスだ。Ruby で書いた Pure Ruby 実装でも動作するが、C 拡張に置き換えることで大幅に高速化できる。

### デュアル実装パターン

```ruby
# C 拡張を試みる
begin
  require_relative "ruvim_ext"
rescue LoadError
  # C 拡張なし → Pure Ruby フォールバック
end

module DisplayWidth
  if defined?(RuVim::DisplayWidthExt)
    # C 拡張パス
    def cell_width(ch, col: 0, tabstop: 2)
      sync_ambiguous_width
      DisplayWidthExt.cell_width(ch, col:, tabstop:)
    end
  else
    # Pure Ruby パス
    def cell_width(ch, col: 0, tabstop: 2)
      # ... Ruby 実装
    end
  end
end
```

`require_relative "ruvim_ext"` が失敗しても `LoadError` をキャッチして Pure Ruby にフォールバックする。ユーザーが C コンパイラを持っていなくても動く。

### C 拡張の実装

C 拡張は約 520 行で、以下の関数を実装する。

- `cell_width` — 1 文字の表示幅
- `display_width` — 文字列全体の表示幅
- `expand_tabs` — タブをスペースに展開
- `clip_cells_for_width` — 指定幅にクリップしてセル配列を返す
- `char_index_for_screen_col` — 画面列から文字インデックスに変換

例えば `display_width` の C 実装を見てみよう。

```c
static VALUE
rb_display_width(int argc, VALUE *argv, VALUE self)
{
    VALUE str, opts;
    rb_scan_args(argc, argv, "1:", &str, &opts);

    const char *ptr = RSTRING_PTR(str);
    const char *end = ptr + RSTRING_LEN(str);
    rb_encoding *enc = rb_utf8_encoding();
    int col = start_col;

    while (ptr < end) {
        unsigned int code;
        int clen = rb_enc_precise_mbclen(ptr, end, enc);

        if (!MBCLEN_CHARFOUND_P(clen)) {
            ptr++; col++; continue;   // 不正バイト: 幅 1
        }
        clen = MBCLEN_CHARFOUND_LEN(clen);
        code = rb_enc_codepoint(ptr, end, enc);
        ptr += clen;

        if (code == '\t') {
            int w = tabstop - (col % tabstop);
            if (w == 0) w = tabstop;
            col += w;
        } else if (clen == 1) {
            col++;   // ASCII 高速パス
        } else {
            col += codepoint_width(code);
        }
    }

    return INT2FIX(col - start_col);
}
```

`rb_enc_precise_mbclen` で UTF-8 のマルチバイト長を正確に取得し、`rb_enc_codepoint` でコードポイントを取得する。Ruby のエンコーディング API を直接使うので、エンコーディングの不整合は起きない。

`codepoint_width` は Unicode テーブルを C の静的配列として持ち、線形走査で判定する。

```c
static const range_t wide_ranges[] = {
    {0x1100, 0x115F},  // Hangul Jamo
    {0x2329, 0x232A},
    {0x2E80, 0xA4CF},  // CJK
    // ...
};

static inline int
in_ranges(unsigned int code, const range_t *ranges, int count)
{
    for (int i = 0; i < count; i++) {
        if (code < ranges[i].lo) return 0;  // ソート済み → 早期脱出
        if (code <= ranges[i].hi) return 1;
    }
    return 0;
}
```

テーブルがソートされているため、`code < ranges[i].lo` で早期に脱出できる。テーブルサイズが小さい（各カテゴリ 5〜10 エントリ程度）ので、二分探索よりも線形走査の方が実用的に速い。

---

## 16. ストリーム — 非同期 I/O と外部プロセス

RuVim は、外部コマンドの出力をリアルタイムにバッファに表示できる。`:run ls -la` と打つと、ls の出力が逐次表示される。

### Stream 階層

```
Stream（基底クラス: state, stop!）
├── Stream::Stdin  — stdin からのパイプ入力
├── Stream::Run    — 外部コマンド実行（PTY or popen）
├── Stream::Follow — ファイル監視（tail -f 相当）
└── Stream::FileLoad — 大規模ファイルの非同期読み込み
```

### Stream::Run — PTY による外部コマンド実行

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

PTY を使うのは、多くのコマンドが PTY 接続時にのみカラー出力や行バッファリングを行うためだ。`chdir` 指定がある場合は `IO.popen` にフォールバックする（PTY は `chdir` をサポートしない）。

### StreamMixer — イベントの合流

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

### 大規模ファイルの非同期読み込み

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

### 自動追従

ストリーム出力のバッファで、カーソルが最終行にある場合、新しいデータが追加されると自動的にカーソルが最終行に移動する（`tail -f` のような動作）。

```ruby
def stream_window_following_end?(win, buf)
  last_row = buf.line_count - 1
  win.cursor_y >= last_row   # カーソルが最終行にいれば追従
end
```

---

## 17. Sixel — ターミナルに画像を描く

テキストエディタに画像表示は贅沢に聞こえるが、Markdown のプレビューや画像ファイルの確認など、実用的な場面は多い。RuVim は **Sixel** プロトコルを使って、ターミナル上に画像を直接描画する。

### Sixel プロトコルの仕様

Sixel は DEC 社が 1980 年代に VT300 シリーズ端末のために開発したグラフィックスプロトコルだ。名前の由来は "**six** pix**el**s" — 縦 6 ピクセルを 1 カラム単位で表現する。

#### データ構造

Sixel データは **DCS (Device Control String)** シーケンスで囲まれる。

```
ESC P <P1>;<P2>;<P3> q <sixel-data> ESC \
```

- `ESC P` (`\eP`) — DCS 開始
- `P1` — ピクセルアスペクト比（通常 0）
- `P2` — 背景モード（0: 現在の背景色、1: スクロール無効）
- `P3` — 水平グリッドサイズ（通常省略）
- `q` — Sixel モード開始
- `ESC \` (`\e\\`) — ST (String Terminator)

RuVim では `P2=1`（スクロール無効モード）を指定する。これは画像が画面下部に近い場合に、ターミナルがスクロールしてしまうのを防ぐためだ。

```ruby
out = +"\eP0;1q"
```

#### ラスター属性

Sixel データの先頭で画像の寸法を宣言できる。

```
"Pan;Pad;Ph;Pv
```

- `Pan`, `Pad` — ピクセルのアスペクト比（通常 1:1）
- `Ph` — 画像の幅（ピクセル）
- `Pv` — 画像の高さ（ピクセル）

```ruby
out << "\"1;1;#{width};#{height}"
```

#### カラーレジスタ

Sixel は最大 256 色のパレットを使う。色は **レジスタ** に登録する。

```
#<番号>;2;<R>;<G>;<B>
```

ここで R, G, B は **0〜100 のパーセンテージ**だ。RGB の 0-255 値を変換する必要がある。

```ruby
palette.each_with_index do |c, i|
  rp = (c[0] * 100.0 / 255).round
  gp = (c[1] * 100.0 / 255).round
  bp = (c[2] * 100.0 / 255).round
  out << "##{i};2;#{rp};#{gp};#{bp}"
end
```

#### バンドベースのエンコーディング

Sixel の核心は、画像を **6 行ずつのバンド** に分割して描画する仕組みだ。

各カラムの 6 ピクセルは 6 ビットで表現され、63 を加算して ASCII 文字（`?` 〜 `~`）にマッピングされる。

```
ビット 0 (最上行) → 値 1
ビット 1           → 値 2
ビット 2           → 値 4
ビット 3           → 値 8
ビット 4           → 値 16
ビット 5 (最下行) → 値 32
```

例えば、6 ピクセルすべてが描画対象なら `1+2+4+8+16+32 = 63`、ASCII では `63 + 63 = 126` = `~` になる。

特殊文字:
- `$` — キャリッジリターン（バンド内で横位置を先頭に戻す）
- `-` — グラフィックス改行（次のバンドへ移動）

#### 色の重ね塗り

Sixel は **色ごと** にバンドを描画する。1 つのバンドで複数の色を使う場合、色を選択（`#番号`）→ データを出力 → `$` で先頭に戻る → 次の色を選択、という手順を繰り返す。最後の色の後は `$` 不要で、`-`（次バンド）か ST（終了）に進む。

```ruby
keys.each_with_index do |idx, ci|
  out << "##{idx}"                                    # 色を選択
  color_data[idx].each { |bits| out << (bits + 63).chr }  # データ
  out << "$" unless ci == keys.length - 1             # 最後以外は CR
end
out << "-" if y < height  # 次のバンドへ
```

### Pure Ruby PNG デコーダ

Sixel エンコードの入力となるのは PNG 画像だ。外部ライブラリへの依存を避けるため、RuVim は Pure Ruby で PNG デコーダを実装している。

#### チャンク解析

PNG ファイルは 8 バイトのシグネチャに続いて、チャンクの連続で構成される。

```
[長さ: 4B] [タイプ: 4B] [データ: N B] [CRC: 4B]
```

RuVim は 3 種類のチャンクだけを解析する。

- **IHDR** — 画像ヘッダ（幅、高さ、ビット深度、カラータイプ）
- **IDAT** — 圧縮された画像データ（複数チャンクの場合あり）
- **IEND** — ファイル終端

```ruby
while pos + 8 <= data.bytesize
  length = data.byteslice(pos, 4).unpack1("N")
  type   = data.byteslice(pos + 4, 4)
  chunk_data = data.byteslice(pos + 8, length)
  pos += 12 + length  # length + type + data + CRC

  case type
  when "IHDR" then ihdr = parse_ihdr(chunk_data)
  when "IDAT" then idat_chunks << chunk_data
  when "IEND" then break
  end
end
```

対応するカラータイプは RGB (2) と RGBA (6) の 8bit のみ。インデクスカラーやグレースケールは非対応だが、写真やスクリーンショットの表示には十分だ。

#### IDAT の解凍とフィルタリング

IDAT チャンクを連結して zlib 展開すると、生のピクセルデータが得られる。ただし、各行の先頭にはフィルタタイプのバイトがあり、PNG の圧縮効率を上げるためのフィルタリングが施されている。

PNG は 5 種類のフィルタを定義する。

| タイプ | 名称 | 復元式 |
|--------|------|--------|
| 0 | None | そのまま |
| 1 | Sub | `x + a` (左隣) |
| 2 | Up | `x + b` (上の行) |
| 3 | Average | `x + floor((a + b) / 2)` |
| 4 | Paeth | `x + PaethPredictor(a, b, c)` |

Paeth 予測子は、左 (a)、上 (b)、左上 (c) の 3 つの隣接ピクセルから最も近いものを予測値として使う。

```ruby
def paeth(a, b, c)
  p_val = a + b - c
  pa = (p_val - a).abs
  pb = (p_val - b).abs
  pc = (p_val - c).abs
  if pa <= pb && pa <= pc then a
  elsif pb <= pc then b
  else c
  end
end
```

この予測子は Alan W. Paeth が 1991 年に発表したもので、周囲のピクセルとの差分を最小化することで、zlib 圧縮の効率を大幅に向上させる。

#### 安全対策

デコーダには複数の安全制限がある。

- 最大ピクセル数: 5,000 万ピクセル（メモリ枯渇を防ぐ）
- 最大展開サイズ: 200 MB（zip bomb 対策）
- ストリーミング展開で逐次チェック

```ruby
MAX_PIXELS = 50_000_000
MAX_INFLATE_SIZE = 200 << 20

def safe_inflate(data)
  zstream = Zlib::Inflate.new
  buf = +""
  zstream.inflate(data) do |chunk|
    buf << chunk
    raise Error, "too large" if buf.bytesize > MAX_INFLATE_SIZE
  end
  buf
ensure
  zstream.close
end
```

### 減色 — Median-Cut 量子化

フルカラーの画像を Sixel の 256 色パレットに変換するには、**減色（Color Quantization）** が必要だ。RuVim は **Median-Cut** アルゴリズムを採用している。

#### 5 ビットヒストグラム

まず、RGB 各チャネルを 8 ビットから 5 ビットに縮約し、32K（32×32×32）の色空間にマッピングする。ピクセルごとではなくユニークな色ごとの頻度をカウントするため、大きな画像でも高速に処理できる。

```ruby
SHIFT = 3  # 8bit → 5bit
hist = Hash.new(0)
height.times do |y|
  row = pixels[y]
  width.times do |x|
    r, g, b = row[x]
    key = ((r >> SHIFT) << 10) | ((g >> SHIFT) << 5) | (b >> SHIFT)
    hist[key] += 1
  end
end
```

10 ビット左シフトされた R、5 ビット左シフトされた G、そのままの B を OR 結合することで、15 ビットのキーにパックしている。

#### Median-Cut の分割

色空間を「箱」に分割していく。各ステップで、RGB のうち **最大レンジを持つチャネル** に沿って箱をソートし、**ピクセル数の中央値** で二分する。

```ruby
boxes = [make_box(entries)]
while boxes.length < 256
  # レンジが最大の箱を見つける
  best_idx = ...
  box = boxes[best_idx]
  ch = box[:ranges].index(best_range)  # 最大レンジのチャネル
  sorted = box[:entries].sort_by { |e| e[ch] }

  # ピクセル数の中央値で分割
  half = total / 2
  acc = 0
  sorted.each_with_index do |e, i|
    acc += e[3]  # e[3] = ピクセル数
    if acc >= half
      split = [i + 1, 1].max
      break
    end
  end
  boxes[best_idx] = make_box(sorted[0...split])
  boxes.push(make_box(sorted[split..]))
end
```

ピクセル数で重み付けした分割により、使用頻度の高い色域に多くのパレットエントリが割り当てられる。

#### パレット色の算出

各箱の代表色は、箱内のエントリの **ピクセル数で重み付けした平均** だ。5 ビットに縮約した値を元の 8 ビット空間に戻す際、`(値 << 3) + 4` として中心値を使う。

最終的に、各ピクセルはルックアップテーブル（LUT）を通じてパレットインデックスに変換される。LUT のキーは 15 ビットの量子化キーなので、検索は O(1) だ。

### リサイズ — Nearest-Neighbor

ターミナルのセルサイズに合わせて画像をリサイズする。品質よりも速度を優先し、**最近傍補間** を使う。

```ruby
def resize(pixels, src_w, src_h, dst_w, dst_h)
  Array.new(dst_h) do |y|
    src_y = (y * src_h / dst_h).clamp(0, src_h - 1)
    Array.new(dst_w) do |x|
      src_x = (x * src_w / dst_w).clamp(0, src_w - 1)
      pixels[src_y][src_x]
    end
  end
end
```

最大サイズはターミナルのセル数×セルサイズ（ピクセル）で計算される。縦横比を維持するため、縦横の縮小率のうち小さい方を採用する。

### ターミナル能力の検出

すべてのターミナルが Sixel を表示できるわけではない。RuVim は起動時に 2 つの問い合わせを行う。

#### DA1 (Device Attributes) による Sixel 対応検出

```
ESC [ c  →  応答: ESC [ ? <属性リスト> c
```

応答に **属性 4** が含まれていれば、Sixel 対応ターミナルだ。xterm、mlterm、WezTerm、foot など主要なターミナルエミュレータが対応している。

#### セルサイズの取得

Sixel はピクセル単位で描画するが、エディタのレイアウトはセル（文字）単位だ。ピクセルをセル数に変換するため、1 セルのピクセルサイズを知る必要がある。

```
ESC [ 16 t  →  応答: ESC [ 6 ; <height> ; <width> t
```

この応答から `cell_width` と `cell_height` が得られる。検出に失敗した場合は、一般的な値 `8×16` をフォールバックとして使う。

### 画面統合 — SIXEL_COVERED マーカー

Sixel 画像はターミナルの通常テキストとは独立して描画される。Sixel データを出力した行の下に、画像が複数行にわたって覆う領域ができる。Screen はこれを **`SIXEL_COVERED`** マーカーで管理する。

```ruby
# 画像行の描画
rows << prefix + result[:text]   # Sixel データ本体
(result[:rows] - 1).times do
  rows << SIXEL_COVERED           # 画像に覆われた行
end
```

差分レンダリング時、`SIXEL_COVERED` の行はスキップされる。Sixel データが上の行で出力済みなので、その下の行に通常テキストを書き込むと画像が壊れてしまうためだ。

```ruby
next if line == SIXEL_COVERED  # 覆われた行はスキップ
```

逆に、以前は画像があったが今はない場合、行をクリアして通常テキストを書き込む。

```ruby
if old_line == SIXEL_COVERED && new_line != SIXEL_COVERED
  out << "\e[#{row_no};1H\e[2K"  # 行クリア
  out << (new_line || "")
end
```

### img2sixel フォールバックと二段構え

Pure Ruby の Sixel エンコーダは依存関係ゼロだが、品質面では専用ツールに劣る。RuVim は **img2sixel**（libsixel のコマンドラインツール）が利用可能なら、そちらを優先する。

```ruby
def load_image(path, ...)
  result = encode_with_img2sixel(full_path, max_px_w, max_px_h, cell_height) ||
           encode_file(full_path, ...)  # フォールバック: Pure Ruby
end
```

img2sixel は高品質なディザリングを提供し、PNG 以外の形式（JPEG, GIF, BMP 等）にも対応する。Pure Ruby 実装はフォールバックとして、img2sixel がインストールされていない環境でも画像表示を可能にする。

### キャッシュ戦略

Sixel エンコードは計算コストが高い。スクロールのたびにエンコードし直すのは現実的ではないため、結果をキャッシュする。

```ruby
class Cache
  def get(path, mtime, width, height)
    key = [path, mtime, width, height]
    @entries[key]
  end

  def put(path, mtime, width, height, result)
    key = [path, mtime, width, height]
    @entries.shift if @entries.size >= 64  # FIFO で上限 64
    @entries[key] = result
  end
end
```

キャッシュキーにファイルの `mtime` を含めることで、画像ファイルが更新された場合は自動的に再エンコードされる。ウィンドウサイズも含まれるため、リサイズ時にも正しく再生成される。

### 画像ファイルの RichView

画像ファイル（PNG, JPEG, GIF, BMP, WEBP）を `:edit` で開くと、自動的に RichView モードになる。`ImageRenderer` はバイナリデータの代わりに `![ファイル名](パス)` という Markdown 画像行を持つ仮想バッファを作成し、Markdown レンダラがこの画像行を Sixel に変換して表示する。

画像ファイルを開くだけで中身が見える。テキストエディタとは思えない体験だが、Sixel プロトコルのおかげでターミナルの中に収まっている。

---

## 18. 設定システム — Ruby DSL による拡張

RuVim の設定ファイルは、そのまま Ruby コードだ。`~/.config/ruvim/init.rb` に以下のように書ける。

```ruby
# キーバインド
nmap "K", "buffer.scroll_up"
nmap " ff", "meta.fuzzy_find"

# インラインコマンド定義
nmap "gf" do |ctx|
  word = ctx.buffer.current_word
  ctx.editor.open_path(word)
end

# Ex コマンド
ex_command "hello", desc: "Say hello" do |ctx, **|
  ctx.editor.echo("Hello, World!")
end

# オプション
set "number"
set "tabstop=4"
```

### ConfigDSL — BasicObject による安全なサンドボックス

```ruby
class ConfigDSL < BasicObject
  def initialize(command_registry:, ex_registry:, keymaps:, command_host:, ...)
    @command_registry = command_registry
    @ex_registry = ex_registry
    @keymaps = keymaps
    @command_host = command_host
  end

  def nmap(seq, command_id = nil, desc: "user keymap", **opts, &block)
    command_id = inline_map_command_id(:normal, seq, desc:, &block) if block
    if @filetype
      @keymaps.bind_filetype(@filetype, seq, command_id.to_s, mode: :normal, **opts)
    else
      @keymaps.bind(:normal, seq, command_id.to_s, **opts)
    end
  end
end
```

`ConfigDSL` は `BasicObject` を継承している。`BasicObject` は `Object` のメソッド（`puts`, `require` など）を持たないため、DSL のメソッド名が衝突しにくい。ユーザーが定義した `nmap` や `set` だけが使える、クリーンな名前空間を提供する。

### ファイルタイプ別設定

ファイルタイプ固有の設定は `~/.config/ruvim/ftplugin/<filetype>.rb` に置く。

```ruby
# ~/.config/ruvim/ftplugin/ruby.rb
set "tabstop=2"
set "shiftwidth=2"
nmap "<C-r>", "meta.run_current"
```

ファイルタイプ名はバリデーションされ、パストラバーサルを防いでいる。

### ブロック付きキーマップ

`nmap` にブロックを渡すと、自動的にコマンド ID が生成されて登録される。

```ruby
def inline_map_command_id(mode, seq, desc:, &block)
  @inline_map_command_seq += 1
  id = "user.keymap.#{mode}.#{sanitize_seq_label(seq)}.#{@inline_map_command_seq}"
  command(id, desc:, &block)
  id
end
```

生成される ID は `user.keymap.normal.gf.1` のような形式で、一意性が保証される。

---

## 19. テスト戦略 — エディタをどうテストするか

テキストエディタのテストは難しい。ターミナル I/O を使い、ユーザーのキー入力に応答し、画面に出力する。自動テストにはターミナルを模擬する必要がある。

### テストヘルパー

```ruby
# test/test_helper.rb
module RuVimTestHelpers
  def fresh_editor
    editor = RuVim::Editor.new
    editor.ensure_bootstrap_buffer!
    editor
  end
end
```

`fresh_editor` は、ターミナルを持たない裸の `Editor` を生成する。入力も描画もなく、純粋にエディタの状態だけをテストできる。

### 統合テスト — AppScenarioTest

より高レベルのテストでは、`App` を生成し、キー入力をプログラム的に注入する。

```ruby
class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true, ...)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @key_handler = @app.instance_variable_get(:@key_handler)
  end

  def feed(keys)
    keys.each_char { |ch| @key_handler.handle(ch) }
  end

  def test_insert_hello
    feed("iHello\e")   # Insert モードに入り、"Hello" と打ち、ESC で Normal に戻る
    assert_equal "Hello", @editor.current_buffer.line_at(0)
    assert_equal :normal, @editor.mode
  end
end
```

`feed` メソッドでキーシーケンスを送り、エディタの状態をアサートする。画面描画は行わないが、バッファの内容、カーソル位置、モード、レジスタの中身など、すべての内部状態を検証できる。

テストスイートは 300 以上のアサーションを含み、挿入、検索、ビジュアルモード、ドットリピート、インデント、テキストオブジェクトなど幅広い操作をカバーしている。

### ユニットテスト

各コンポーネントは独立してテスト可能だ。

- `buffer_test` — バッファの行操作、undo/redo、ファイル I/O
- `window_test` — カーソル移動、スクロール、クランプ
- `keymap_manager_test` — キーの登録と解決
- `display_width_test` — Unicode 文字幅
- `text_metrics_test` — グラフェム境界、画面列変換
- `highlighter_test` — 各言語の色付け
- `dispatcher_test` — レンジ解析、substitute 解析

---

## 20. 設計パターンと判断の記録

最後に、RuVim の設計で採用されたパターンと、その背景にある判断を整理する。

### 依存注入 (Dependency Injection)

すべてのコンポーネントは `App` が生成し、コンストラクタ引数やセッターで注入する。`Editor` は `KeymapManager` や `StreamMixer` への参照を外部からもらう。これにより、テスト時にモックや単純な実装に差し替えられる。

### 遅延ロード (Lazy Loading)

```ruby
module RuVim
  autoload :Clipboard, File.expand_path("clipboard", __dir__)
  autoload :Browser, File.expand_path("browser", __dir__)
  autoload :SpellChecker, File.expand_path("spell_checker", __dir__)
  autoload :FileWatcher, File.expand_path("file_watcher", __dir__)
end
```

クリップボード、ブラウザ、スペルチェッカー、ファイルウォッチャー、すべての言語モジュール、Git/GitHub インテグレーションは、初めて参照されるまでロードされない。起動時間を短縮するための重要な戦略だ。

### フリーズしたシングルトン

言語モジュールは `@instance ||= new.freeze` というパターンでインスタンスを提供する。`freeze` することで、ハイライト処理中に誤って状態を変更する可能性を排除する。

### コールバックとしてのラムダ

`Editor` は `@suspend_handler`、`@shell_executor`、`@confirm_key_reader` といったコールバックをラムダとして保持する。これにより、Editor が Terminal や Input の存在を知らなくても、必要な操作を実行できる。

```ruby
@editor.shell_executor = ->(command) {
  result = @terminal.suspend_for_shell(command)
  @screen.invalidate_cache!
  result
}
```

### 状態機械としてのペンディング状態

`KeyHandler` の各ペンディング状態（オペレータ、レジスタ、マーク等）は、明示的なフラグとして管理される。有限状態機械の各状態に対応するメソッドが呼ばれ、次の入力に応じて遷移する。

複雑さを制御するため、`PendingState`、`MacroDot`、`InsertMode` の 3 つのモジュールに分割している。

### エラー境界としての CommandError

すべてのコマンドエラーは `RuVim::CommandError` として送出され、`KeyHandler#handle` と `Dispatcher#dispatch` で捕捉される。

```ruby
def handle(key)
  # ... キー処理 ...
rescue RuVim::CommandError => e
  @editor.echo_error(e.message)
  false
end
```

どんなコマンドがエラーを起こしても、エディタ自体はクラッシュせず、エラーメッセージを表示して通常動作を続ける。

### モノトニッククロックの一貫した使用

時刻が関わる処理（タイムアウト、パフォーマンス計測、メッセージの有効期限）はすべて `Process.clock_gettime(Process::CLOCK_MONOTONIC)` を使う。`Time.now` は NTP 同期で巻き戻る可能性があるため使わない。

```ruby
def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
rescue StandardError
  Time.now.to_f   # フォールバック
end
```

---

## おわりに

テキストエディタは、小さな世界に見えて驚くほど広い問題空間を持つプログラムだ。ターミナル制御、Unicode、非同期 I/O、状態機械、パフォーマンス最適化 — ソフトウェアエンジニアリングの多くの側面が凝縮されている。

RuVim は Ruby で書かれているが、ホットパスを C 拡張に逃がすデュアル実装パターン、ペースト最適化や差分レンダリングといった実用的な最適化により、日常的な使用に十分な性能を実現している。

この記事が、エディタの内部構造に興味を持つきっかけになれば幸いだ。ソースコードは全公開されているので、気になった部分はぜひ読んでみてほしい。
