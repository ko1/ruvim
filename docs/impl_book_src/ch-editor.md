# エディタ — 状態の統括者

> 「全体は部分の総和以上のものである」 — 西田幾多郎

`Editor` はアプリケーション全体の状態を管理する中心的なオブジェクトだ。

- **バッファの管理**: `@buffers`（id → Buffer のハッシュ）
- **ウィンドウの管理**: `@windows`（id → Window のハッシュ）
- **レイアウトツリー**: `@layout_tree`（ウィンドウ分割の階層構造）
- **タブページ**: `@tabpages`（レイアウトツリーの配列）
- **モード管理**: `@mode`（`:normal`, `:insert`, `:visual_char` など）
- **ビジュアル選択**: `@visual_state`
- **レジスタ**: `@registers`
- **マーク**: `@marks`
- **ジャンプリスト**: `@jump_list`
- **Quickfix / ロケーションリスト**: `@quickfix_items`, `@location_lists`
- **オプション**: グローバル/ウィンドウ/バッファの 3 スコープ

## オプションシステム

Vim のオプションは、スコープ（グローバル、ウィンドウローカル、バッファローカル）と型（boolean, number, string）を持つ。

```ruby
OPTION_DEFS = {
  "number"     => { scope: :window,  type: :bool,   default: false },
  "tabstop"    => { scope: :buffer,  type: :number, default: 2 },
  "filetype"   => { scope: :buffer,  type: :string, default: "" },
  "scrolloff"  => { scope: :global,  type: :number, default: 0 },
  # ... 51 以上のオプション定義
}
```

`effective_option` は、ウィンドウローカル → グローバルの順に値を解決する。

## レイアウトツリー

ウィンドウの分割は木構造で表現される。

```
{ type: :hsplit, children: [
    { type: :window, id: 1 },
    { type: :vsplit, children: [
        { type: :window, id: 2 },
        { type: :window, id: 3 }
    ]}
]}
```

このツリーを再帰的に走査して、各ウィンドウの矩形（行、列、幅、高さ）を計算する。
