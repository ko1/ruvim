# KeyHandler — 状態機械の集合体

> 「変化に処するは静なるをもって」 — 徳川家康

[`KeyHandler`](#index:KeyHandler) はエディタの中で最も複雑なコンポーネントの一つだ。Normal モードのキー入力には、驚くほど多くの「ペンディング状態」がある。

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

> [!NOTE]
> ペンディング状態の管理は[メインループ](ch-mainloop.md#タイムアウトの管理)のタイムアウトと連動する。`timeoutlen` はこのペンディング状態の待ち時間を制御する。

## Normal モードのキー処理

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

## オペレータ + モーション

Vim の `d` + モーション（`dw`, `d$`, `d3j` など）は、オペレータペンディング状態で実現される。

1. `d` が押される → `start_operator_pending(:delete)` でオペレータをセット
2. 次のキー（例えば `w`）が来る → `handle_operator_pending_key` でモーションとして解決
3. 二重オペレータ（`dd`）も特別に処理：オペレータキーが 2 回来たら行全体に適用

テキストオブジェクト（`iw`, `a(`）もモーション接頭辞（`i`, `a`, `g`）として扱い、2 ストロークの入力を待つ。

## ドットリピート

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

## マクロ

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

> [!CAUTION]
> マクロの最大深度（20）を超えると `CommandError` が発生する。無限再帰を防ぐための安全装置だが、意図的に深いネストが必要な場合は定数 `MAX_MACRO_DEPTH` を変更する必要がある。
