# コマンドディスパッチ — キーから動作へ

> 「知行合一」 — 王陽明を受けた日本の儒学者たち

キーマッピングの解決によって得られた `CommandInvocation` は、`Dispatcher` によってコマンドハンドラに送られる。

## Normal モードコマンドの実行

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

## Ex コマンドの解析パイプライン

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

## レンジの解析

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

## substitute のパース

`:s/pattern/replacement/flags` は区切り文字（通常は `/`）で分割されるが、実際には任意の文字を区切りに使える（`:s#old#new#g` のように）[^1]。区切り文字の中で `\` によるエスケープも扱う。

[^1]: Vim と同様に、区切り文字はアルファベット以外の任意の文字が使える。ただし `|` はパイプとして解釈される可能性があるため避けるべきだ。

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
