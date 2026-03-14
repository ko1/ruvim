# シンタックスハイライト — 色を付ける

> 「色は匂えど散りぬるを」 — いろは歌

## Lang::Base — 色付けの基盤

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

## Lang::Ruby — Prism による正確なハイライト

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

## 色の重ね方 — apply_regex の優先度制御

正規表現ベースの言語モジュールでは、`color_columns` の中で `apply_regex` を **呼ぶ順序** が色の優先度を決める。

C 言語の例を見てみよう。

```ruby
def color_columns(text)
  cols = {}
  apply_regex(cols, text, CHAR_RE, STRING_COLOR)         # 1. 文字リテラル
  apply_regex(cols, text, STRING_RE, STRING_COLOR)        # 2. 文字列
  apply_regex(cols, text, KEYWORD_RE, KEYWORD_COLOR)      # 3. キーワード
  apply_regex(cols, text, NUMBER_RE, NUMBER_COLOR)        # 4. 数値
  apply_regex(cols, text, CONSTANT_RE, CONSTANT_COLOR)    # 5. 定数
  apply_regex(cols, text, PREPROCESSOR_RE, "\e[35m")      # 6. プリプロセッサ
  apply_regex(cols, text, BLOCK_COMMENT_RE, COMMENT_COLOR, override: true)  # 7. ブロックコメント
  apply_regex(cols, text, LINE_COMMENT_RE, COMMENT_COLOR, override: true)   # 8. 行コメント
  cols
end
```

`apply_regex` は `cols` ハッシュに `{ 文字位置 => 色 }` を書き込む。デフォルトでは **既に色が付いている位置はスキップする**（`override: false`）。

```ruby
def apply_regex(cols, text, regex, color, override: false)
  text.to_enum(:scan, regex).each do
    m = Regexp.last_match
    (m.begin(0)...m.end(0)).each do |idx|
      next if cols.key?(idx) && !override  # 既に色があればスキップ
      cols[idx] = color
    end
  end
end
```

つまり、**先に呼ばれた regex が勝つ**。文字列中の `if` がキーワード色にならないのは、`STRING_RE` が先に適用されて文字列内の位置に色が付いており、後から `KEYWORD_RE` がマッチしてもスキップされるからだ。

ただし `override: true` を指定すると、既存の色を上書きする。コメントに使われるのがこのパターンだ。`// TODO: fix this` のような行では、まず `KEYWORD_RE` 等が個別のトークンに色を付けるが、最後に `LINE_COMMENT_RE` が `override: true` で全体をコメント色に塗り替える。

この仕組みにより、各言語モジュールは正規表現の適用順序を変えるだけで、色の優先度を柔軟に制御できる。

## 描画時の色レイヤー統合

言語モジュールが返す `{ 文字位置 => 色 }` ハッシュは、描画パイプラインでさらに他の色情報と重ね合わされる。`render_cells` では以下の優先度でチェックする。

```
1. カーソル位置      → 反転表示 (\e[7m)
2. ビジュアル選択    → 反転表示 (\e[7m)
3. 検索ハイライト    → 黄色背景 (\e[43m)
4. カラーカラム      → 灰色背景
5. カーソル行背景    → 背景色
6. シンタックス色    → 各言語モジュールの色（スペルチェック下線と併用可）
7. スペルチェック    → 赤下線 (\e[4;31m)
8. なし              → 素の文字
```

重要なポイントは、すべての色情報が **同じインターフェース**（`{ 文字位置 => 値 }` のハッシュ）で提供されることだ。シンタックスハイライト、検索マッチ、スペルチェックが同じ形式なので、描画コードは色の出所を知る必要がない。

シンタックス色とスペルチェックだけは **併用可能** だ。文字にシンタックス色がある位置がスペルミスでもある場合、`"#{syntax_color}\e[4;31m#{glyph}\e[m"` のように ANSI コードを連結して、色付き + 赤下線の両方を適用する。

## キャッシュ

シンタックスハイライトの計算結果は `[言語モジュール, 行テキスト]` をキーとしてキャッシュされる（上限 2048 エントリ）。行が編集されると新しい文字列オブジェクトが生成されるため、自動的にキャッシュミスし、再計算される。明示的な invalidation は不要だ。

## インデント支援

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

## on_save フック

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
