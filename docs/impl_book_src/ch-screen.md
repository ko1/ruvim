# 画面描画 — Screen と差分レンダリング

> 「見えるものだけが全てではない、しかし見えなければ始まらない」 — 小津安二郎

`Screen` クラスは、エディタの状態を端末の文字列に変換する。

## 2 フェーズレンダリング

[差分レンダリング](#index:差分レンダリング)の描画は 2 フェーズで行われる。

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

## キャッシュ

パフォーマンスのために 2 つのキャッシュを維持する。

```ruby
@syntax_color_cache = {}       # バッファ行内容 → 色情報（上限 2048 エントリ）
@wrapped_segments_cache = {}   # 行内容 → 折り返しセグメント（上限 1024 エントリ）
```

同じ行の内容が変わらない限り、シンタックスハイライトの計算をスキップできる。LRU ではなくサイズ上限付きのハッシュだが、描画ループでは通常画面に表示されている行だけが参照されるため、実用的には十分だ。

## レイアウト合成 — 分割ウィンドウの描画

複数ウィンドウが分割されているとき、それぞれのウィンドウを正しい位置に描画する必要がある。この処理は 3 段階で行われる。

## 1. 矩形の計算

レイアウトツリーを再帰的に走査し、各ウィンドウに **矩形（top, left, height, width）** を割り当てる。

```ruby
def compute_tree_rects(node, top:, left:, height:, width:)
  if node[:type] == :window
    return { node[:id] => { top:, left:, height:, width: } }
  end

  children = node[:children]
  case node[:type]
  when :vsplit
    sep_count = children.length - 1
    usable = width - sep_count        # セパレータ 1 カラム分を差し引く
    widths = weighted_split_sizes(usable, children.length, node[:weights])
    cur_left = left
    children.each_with_index do |child, i|
      w = widths[i]
      rects.merge!(compute_tree_rects(child, top:, left: cur_left, height:, width: w))
      cur_left += w + 1               # +1 はセパレータ分
    end
  when :hsplit
    # 同様に height を分割し、cur_top を進める
  end
end
```

`:vsplit` では幅を子ノード数で分割し、子と子の間に 1 カラムのセパレータ用スペースを確保する。`:hsplit` では高さを分割し、1 行分のセパレータ行を挟む。`:weights` がある場合は重み付き分割（ユーザーが `Ctrl-W >` でリサイズした結果）を使う。

ウィンドウが 1 つだけなら、画面全体がそのウィンドウの矩形になる。

## 2. 各ウィンドウの事前描画

矩形が決まったら、全ウィンドウの内容を **先に** 文字列の配列として描画しておく。

```ruby
editor.window_order.each do |win_id|
  rect = rects[win_id]
  gutter_w = number_column_width(editor, window, buffer)
  content_w = rect[:width] - gutter_w
  window_rows_cache[win_id] = window_render_rows(editor, window, buffer,
    height: rect[:height], gutter_w:, content_w:)
end
```

各ウィンドウは自分に割り当てられた矩形の幅と高さだけを気にし、画面全体の座標は知らない。

## 3. 行計画（row plan）による合成

最後に、画面の各行について「何を左から右に並べるか」を記述した **行計画** を構築する。

```ruby
def fill_row_plans(node, rects, plans, ...)
  if node[:type] == :window
    rect[:height].times do |dy|
      row_no = rect[:top] + dy
      plans[row_no] << { type: :window, id: node[:id] }
    end
  elsif node[:type] == :vsplit
    children.each_with_index do |child, i|
      fill_row_plans(child, ...)
      # 子と子の間にセパレータを挿入
      plans[row_no] << { type: :vsep } if i < children.length - 1
    end
  elsif node[:type] == :hsplit
    children.each_with_index do |child, i|
      fill_row_plans(child, ...)
      # 子と子の間に水平セパレータ行を挿入
      plans[sep_row] << { type: :hsep, width: w } if i < children.length - 1
    end
  end
end
```

行計画のピース型は 4 つある。

| ピース型 | 描画内容 |
|----------|----------|
| `:window` | そのウィンドウの事前描画済み行（`window_rows_cache` から取得） |
| `:vsep` | 垂直セパレータ `\|`（1 カラム） |
| `:hsep` | 水平セパレータ `-` の繰り返し |
| `:blank` | 空白埋め |

最終出力では、各画面行の行計画を左から順に連結するだけだ。

```ruby
1.upto(text_rows) do |row_no|
  pieces = +""
  row_plans[row_no].each do |piece|
    case piece[:type]
    when :window then pieces << window_rows_cache[piece[:id]][dy]
    when :vsep   then pieces << "|"
    when :hsep   then pieces << "-" * piece[:width]
    end
  end
  lines[row_no] = pieces
end
```

具体例として、3 分割のレイアウトを見てみよう。

```
{ type: :hsplit, children: [
    { type: :window, id: 1 },                    # 上半分
    { type: :vsplit, children: [
        { type: :window, id: 2 },                # 左下
        { type: :window, id: 3 }                 # 右下
    ]}
]}
```

ターミナルが 80×24 の場合、矩形は次のように計算される。

```
Window 1: top=1,  left=1,  height=11, width=80   ← 上半分
----------- 水平セパレータ行（row 12）-----------
Window 2: top=13, left=1,  height=11, width=39   ← 左下
|  ← 垂直セパレータ（col 40）
Window 3: top=13, left=41, height=11, width=40   ← 右下
```

row 12 の行計画は `[{ type: :hsep, width: 80 }]`、row 13〜23 の行計画は `[{ type: :window, id: 2 }, { type: :vsep }, { type: :window, id: 3 }]` となる。

## バッファ文字列から画面セルへの変換

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

## 描画のレイヤー構造

Cell 配列ができたら、各セルに色を重ねていく。色の決定は **優先度順** で、最初にマッチした条件が採用される（カーソル > ビジュアル選択 > 検索 > シンタックス色 > 素の文字）。色レイヤーの詳細は [13. シンタックスハイライト — 色を付ける](#13-シンタックスハイライト--色を付ける) の「描画時の色レイヤー統合」を参照。

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

> [!NOTE]
> この統一インターフェースの設計は[シンタックスハイライト](ch-syntax.md)で詳しく解説している。

## 高速パス — 色も特殊文字もない行

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

> [!TIP]
> `can_bulk_render_line?` の条件を見ると、パフォーマンスが重要な場面（大きなログファイルの閲覧など）では `cursorline` や `hlsearch` をオフにすると描画が高速化することがわかる。

## 編集による再描画の流れ

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

## 座標系の変換

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

## 折り返し（Wrap）

`wrap` オプション（デフォルト有効）が有効なとき、ウィンドウ幅に収まらない長い行は **複数の表示行に折り返される**。水平スクロールの代わりに、行を分割して表示するのだ。

## セグメント分割

折り返しの単位は **セグメント** と呼ぶ。1 つのバッファ行が N 個のセグメントに分割され、各セグメントが 1 つの表示行になる。

```ruby
def compute_wrapped_segments(line, width:, tabstop:, linebreak:, showbreak:, indent_prefix:)
  segs = []
  start_col = 0
  first = true

  while start_col < line.length
    display_prefix = first ? "" : "#{showbreak}#{indent_prefix}"
    prefix_w = DisplayWidth.display_width(display_prefix, tabstop:)
    avail = [width - prefix_w, 1].max

    # 利用可能な幅に収まるだけの Cell を切り出す
    cells, = TextMetrics.clip_cells_for_width(line[start_col..], avail, ...)
    break if cells.empty?

    # linebreak: 単語の途中で折り返さない
    if linebreak && cells.length > 1
      break_idx = linebreak_break_index(cells, line)
      cells = cells[0..break_idx] if break_idx
    end

    segs << { source_col_start: start_col, display_prefix: display_prefix }
    start_col = cells.last.source_col + 1
  end
  segs.freeze
end
```

処理の流れはこうだ。

1. `clip_cells_for_width` で、利用可能な幅に収まるだけの Cell を取得する
2. `linebreak` オプションが有効なら、空白位置で折り返して単語を分断しない
3. 各セグメントに `source_col_start`（バッファ行内の開始文字位置）と `display_prefix`（折り返し行の先頭に表示する文字列）を記録する

## 折り返し関連オプション

| オプション | 効果 |
|-----------|------|
| `wrap` | 折り返しの有効/無効。無効の場合は水平スクロール |
| `linebreak` | 単語の途中で折り返さない（空白位置で分割） |
| `showbreak` | 折り返し行の先頭に表示する文字列（例: `"↪ "`） |
| `breakindent` | 折り返し行に元の行のインデントを引き継ぐ |

`showbreak` と `breakindent` は **`display_prefix`** として結合され、2 行目以降のセグメントの先頭に表示される。例えば `showbreak` が `"↪ "` で元の行が 4 スペースインデントなら、`display_prefix` は `"↪     "` になる。この分だけ利用可能な幅（`avail`）が減る。

## 描画

`wrapped_window_render_rows` は、セグメント単位でループする。

```ruby
def wrapped_window_render_rows(editor, window, buffer, height:, gutter_w:, content_w:)
  rows = []
  row_idx = window.row_offset
  seg_skip = window.wrap_seg_offset      # 先頭行の先頭セグメントのスキップ数

  while rows.length < height
    line = buffer.line_at(row_idx)
    segments = wrapped_segments_for_line(editor, window, buffer, line, width: content_w)

    segments.each_with_index do |seg, seg_i|
      next seg_skip -= 1 if seg_skip > 0  # スクロール済みセグメントをスキップ
      break if rows.length >= height

      # 行番号は各バッファ行の最初のセグメントにだけ表示
      gutter = render_gutter_prefix(editor, window, buffer,
                 seg_i.zero? ? row_idx : nil, gutter_w)
      rows << gutter + render_text_segment(line, ...,
                source_col_start: seg[:source_col_start],
                display_prefix: seg[:display_prefix])
    end
    row_idx += 1
  end
  rows
end
```

行番号ガターは各バッファ行の **最初のセグメントにだけ** 表示し、折り返し行は空白ガターにする。これにより、折り返しが起きていても元のバッファ行の区切りが視覚的にわかる。

## スクロールとカーソル追従

折り返しモードでは、ウィンドウは 2 つのオフセットでスクロール位置を管理する。

- **`row_offset`**: 画面最上部に表示するバッファ行番号
- **`wrap_seg_offset`**: その行の先頭から何セグメントスキップするか

`ensure_visible_under_wrap` は、カーソルが画面内に収まるようにこの 2 つを調整する。

```
1. カーソルがある行のセグメントを計算
2. row_offset からカーソル行までの視覚行数を積算
3. カーソル行が画面に収まらない → row_offset を進める（上の行を押し出す）
4. カーソル行自体が画面より長い → wrap_seg_offset でセグメント単位スキップ
```

重要なのは、折り返しモードでは `col_offset`（水平スクロール）は使わないことだ。すべての文字が折り返しによって表示されるため、水平スクロールが不要になる。
