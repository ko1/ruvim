# C 拡張 — ホットパスの高速化

> 「適材適所」 — 日本のことわざ

[DisplayWidth](#index:C 拡張/DisplayWidth) と [TextMetrics](#index:C 拡張/TextMetrics) の計算は、[画面描画](ch-screen.md)のたびに何千回も呼ばれるホットパスだ。Ruby で書いた Pure Ruby 実装でも動作するが、C 拡張に置き換えることで大幅に高速化できる。

## デュアル実装パターン

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

> [!IMPORTANT]
> このデュアル実装パターンにより、C コンパイラがない環境でも RuVim は動作する。パフォーマンスは低下するが機能は完全に同一だ。詳しくは[設計パターン](ch-design-patterns.md)を参照。

## C 拡張の実装

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

> [!TIP]
> ベンチマークは `benchmark/cext_compare.rb` で Pure Ruby 版と C 拡張版の性能を比較できる。一般的にC拡張版は3〜5倍高速だ。
