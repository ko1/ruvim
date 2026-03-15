# Unicode 対応 — 文字幅の深淵

> 「文字は文化そのものである」 — 白川静

テキストエディタにおける [Unicode](#index:Unicode) 対応は、表面的な「UTF-8 を扱えます」を遥かに超える問題だ。最大の課題は **[表示幅](#index:表示幅/DisplayWidth)** の計算である。

## 問題

ターミナルは固定幅グリッドで文字を表示する。ASCII 文字は 1 セルだが、CJK 文字（漢字、ひらがな等）は 2 セル分の幅を取る。絵文字も通常 2 セルだ。結合文字（例: `e` + `́` → `é`）は前の文字に重なるため幅 0 だ。

これを正しく計算しないと、カーソル位置がずれる。「こんにちは」の「に」にカーソルがあるはずが、「ち」の位置に表示される、といった問題が起きる。

## DisplayWidth モジュール

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

## コードポイント範囲の分類

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

## 曖昧幅文字

Unicode には「曖昧幅（Ambiguous Width）」という文字カテゴリがある。ギリシャ文字（α, β）や罫線文字（─, │）などは、東アジアの端末では幅 2、西洋の端末では幅 1 で表示される。

```ruby
def ambiguous_width
  env = ::ENV["RUVIM_AMBIGUOUS_WIDTH"]
  (env == "2" ? 2 : 1)
end
```

`RUVIM_AMBIGUOUS_WIDTH=2` 環境変数で切り替えられる。

> [!WARNING]
> 曖昧幅の設定はターミナルエミュレータの設定と一致させる必要がある。不一致があるとカーソル位置がずれる原因になる。

## タブの可変幅

タブ文字の幅は固定ではなく、**現在の表示位置** に依存する。

```
位置 0: タブ → 幅 4 (tabstop=4 の場合、次の 4 の倍数まで)
位置 1: タブ → 幅 3
位置 3: タブ → 幅 1
位置 4: タブ → 幅 4
```

`cell_width` が `col:` パラメータを受け取るのはこのためだ。

> [!NOTE]
> 表示幅計算のパフォーマンスが重要な理由は、[画面描画](ch-screen.md)のたびに画面に表示されるすべての文字の幅を計算する必要があるからだ。[C 拡張](ch-c-extension.md)はこのホットパスを高速化する。
