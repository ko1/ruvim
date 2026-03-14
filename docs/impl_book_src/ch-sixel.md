# Sixel — ターミナルに画像を描く

> 「百聞は一見にしかず」 — 日本のことわざ

テキストエディタに画像表示は贅沢に聞こえるが、Markdown のプレビューや画像ファイルの確認など、実用的な場面は多い。RuVim は **Sixel** プロトコルを使って、ターミナル上に画像を直接描画する。

## Sixel プロトコルの仕様

Sixel は DEC 社が 1980 年代に VT300 シリーズ端末のために開発したグラフィックスプロトコルだ。名前の由来は "**six** pix**el**s" — 縦 6 ピクセルを 1 カラム単位で表現する。

## データ構造

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

## ラスター属性

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

## カラーレジスタ

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

## バンドベースのエンコーディング

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

## 色の重ね塗り

Sixel は **色ごと** にバンドを描画する。1 つのバンドで複数の色を使う場合、色を選択（`#番号`）→ データを出力 → `$` で先頭に戻る → 次の色を選択、という手順を繰り返す。最後の色の後は `$` 不要で、`-`（次バンド）か ST（終了）に進む。

```ruby
keys.each_with_index do |idx, ci|
  out << "##{idx}"                                    # 色を選択
  color_data[idx].each { |bits| out << (bits + 63).chr }  # データ
  out << "$" unless ci == keys.length - 1             # 最後以外は CR
end
out << "-" if y < height  # 次のバンドへ
```

## Pure Ruby PNG デコーダ

Sixel エンコードの入力となるのは PNG 画像だ。外部ライブラリへの依存を避けるため、RuVim は Pure Ruby で PNG デコーダを実装している。

## チャンク解析

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

## IDAT の解凍とフィルタリング

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

## 安全対策

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

## 減色 — Median-Cut 量子化

フルカラーの画像を Sixel の 256 色パレットに変換するには、**減色（Color Quantization）** が必要だ。RuVim は **Median-Cut** アルゴリズムを採用している。

## 5 ビットヒストグラム

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

## Median-Cut の分割

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

## パレット色の算出

各箱の代表色は、箱内のエントリの **ピクセル数で重み付けした平均** だ。5 ビットに縮約した値を元の 8 ビット空間に戻す際、`(値 << 3) + 4` として中心値を使う。

最終的に、各ピクセルはルックアップテーブル（LUT）を通じてパレットインデックスに変換される。LUT のキーは 15 ビットの量子化キーなので、検索は O(1) だ。

## リサイズ — Nearest-Neighbor

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

## ターミナル能力の検出

すべてのターミナルが Sixel を表示できるわけではない。RuVim は起動時に 2 つの問い合わせを行う。

## DA1 (Device Attributes) による Sixel 対応検出

```
ESC [ c  →  応答: ESC [ ? <属性リスト> c
```

応答に **属性 4** が含まれていれば、Sixel 対応ターミナルだ。xterm、mlterm、WezTerm、foot など主要なターミナルエミュレータが対応している。

## セルサイズの取得

Sixel はピクセル単位で描画するが、エディタのレイアウトはセル（文字）単位だ。ピクセルをセル数に変換するため、1 セルのピクセルサイズを知る必要がある。

```
ESC [ 16 t  →  応答: ESC [ 6 ; <height> ; <width> t
```

この応答から `cell_width` と `cell_height` が得られる。検出に失敗した場合は、一般的な値 `8×16` をフォールバックとして使う。

## 画面統合 — SIXEL_COVERED マーカー

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

## img2sixel フォールバックと二段構え

Pure Ruby の Sixel エンコーダは依存関係ゼロだが、品質面では専用ツールに劣る。RuVim は **img2sixel**（libsixel のコマンドラインツール）が利用可能なら、そちらを優先する。

```ruby
def load_image(path, ...)
  result = encode_with_img2sixel(full_path, max_px_w, max_px_h, cell_height) ||
           encode_file(full_path, ...)  # フォールバック: Pure Ruby
end
```

img2sixel は高品質なディザリングを提供し、PNG 以外の形式（JPEG, GIF, BMP 等）にも対応する。Pure Ruby 実装はフォールバックとして、img2sixel がインストールされていない環境でも画像表示を可能にする。

## キャッシュ戦略

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

## 画像ファイルの RichView

画像ファイル（PNG, JPEG, GIF, BMP, WEBP）を `:edit` で開くと、自動的に RichView モードになる。`ImageRenderer` はバイナリデータの代わりに `![ファイル名](パス)` という Markdown 画像行を持つ仮想バッファを作成し、Markdown レンダラがこの画像行を Sixel に変換して表示する。

画像ファイルを開くだけで中身が見える。テキストエディタとは思えない体験だが、Sixel プロトコルのおかげでターミナルの中に収まっている。
