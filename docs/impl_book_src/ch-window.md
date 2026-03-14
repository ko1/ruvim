# ウィンドウ — バッファへの窓

> 「窓は世界を切り取る額縁である」 — 安藤忠雄

`Window` はバッファの特定の領域を表示するビューポートだ。1 つのバッファに対して複数のウィンドウを開ける。ウィンドウはカーソル位置とスクロールオフセットを持つ。

## グラフェム単位のカーソル移動

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

## 垂直移動と preferred_x

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

## スクロールの確保

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
