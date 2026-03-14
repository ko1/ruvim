# バッファ — テキストの器

> 「器は中身を決め、中身は器を選ぶ」 — 北大路魯山人

`Buffer` はテキストデータを保持する器だ。1 つのファイル（または名前なしバッファ）に対応する。

## データ構造

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

## ファイルの読み込みとエンコーディング

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

## Undo/Redo — スナップショット方式

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

## チェンジグループ

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

## 永続 Undo

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

## ストリーム対応

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
