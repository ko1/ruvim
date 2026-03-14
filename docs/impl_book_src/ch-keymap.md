# キーマッピング — 層状の解決とプレフィックスインデックス

> 「重なりの中に秩序あり」 — 柳宗悦

Vim のキーマッピングは奥が深い。`dd`（行削除）、`dw`（ワード削除）、`d3w`（3 ワード削除）のように、複数キーの組み合わせでコマンドが決まる。さらに、ファイルタイプやバッファ固有のマッピングが通常のマッピングを上書きできる。

## LayerMap — プレフィックスインデックス付きハッシュ

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

## 4 層の解決

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

## マッチの 4 状態

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
