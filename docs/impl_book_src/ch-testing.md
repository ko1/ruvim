# テスト戦略 — エディタをどうテストするか

> 「備えあれば憂いなし」 — 日本のことわざ

テキストエディタのテストは難しい。ターミナル I/O を使い、ユーザーのキー入力に応答し、画面に出力する。自動テストにはターミナルを模擬する必要がある。

## テストヘルパー

```ruby
# test/test_helper.rb
module RuVimTestHelpers
  def fresh_editor
    editor = RuVim::Editor.new
    editor.ensure_bootstrap_buffer!
    editor
  end
end
```

`fresh_editor` は、ターミナルを持たない裸の `Editor` を生成する。入力も描画もなく、純粋にエディタの状態だけをテストできる。

## 統合テスト — AppScenarioTest

より高レベルのテストでは、`App` を生成し、キー入力をプログラム的に注入する。

```ruby
class AppScenarioTest < Minitest::Test
  def setup
    @app = RuVim::App.new(clean: true, ...)
    @editor = @app.instance_variable_get(:@editor)
    @dispatcher = @app.instance_variable_get(:@dispatcher)
    @key_handler = @app.instance_variable_get(:@key_handler)
  end

  def feed(keys)
    keys.each_char { |ch| @key_handler.handle(ch) }
  end

  def test_insert_hello
    feed("iHello\e")   # Insert モードに入り、"Hello" と打ち、ESC で Normal に戻る
    assert_equal "Hello", @editor.current_buffer.line_at(0)
    assert_equal :normal, @editor.mode
  end
end
```

`feed` メソッドでキーシーケンスを送り、エディタの状態をアサートする。画面描画は行わないが、バッファの内容、カーソル位置、モード、レジスタの中身など、すべての内部状態を検証できる。

テストスイートは 300 以上のアサーションを含み、挿入、検索、ビジュアルモード、ドットリピート、インデント、テキストオブジェクトなど幅広い操作をカバーしている。

## ユニットテスト

各コンポーネントは独立してテスト可能だ。

- `buffer_test` — バッファの行操作、undo/redo、ファイル I/O
- `window_test` — カーソル移動、スクロール、クランプ
- `keymap_manager_test` — キーの登録と解決
- `display_width_test` — Unicode 文字幅
- `text_metrics_test` — グラフェム境界、画面列変換
- `highlighter_test` — 各言語の色付け
- `dispatcher_test` — レンジ解析、substitute 解析
