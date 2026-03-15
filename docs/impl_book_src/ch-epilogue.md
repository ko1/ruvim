# おわりに

> 「初心忘るべからず」 — 世阿弥

テキストエディタは、小さな世界に見えて驚くほど広い問題空間を持つプログラムだ。ターミナル制御、Unicode、非同期 I/O、状態機械、パフォーマンス最適化 — ソフトウェアエンジニアリングの多くの側面が凝縮されている。

RuVim は Ruby で書かれているが、ホットパスを C 拡張に逃がすデュアル実装パターン、ペースト最適化や差分レンダリングといった実用的な最適化により、日常的な使用に十分な性能を実現している。

この記事が、エディタの内部構造に興味を持つきっかけになれば幸いだ。ソースコードは全公開されているので、気になった部分はぜひ読んでみてほしい。

> [!TIP]
> 各章で解説したソースファイルの場所は以下の通りだ:
> - [全体像](ch-overview.md): `lib/ruvim/app.rb`
> - [ターミナル](ch-terminal.md): `lib/ruvim/terminal.rb`
> - [キー入力](ch-key-input.md): `lib/ruvim/input.rb`
> - [キーマッピング](ch-keymap.md): `lib/ruvim/keymap_manager.rb`
> - [バッファ](ch-buffer.md): `lib/ruvim/buffer.rb`
> - [画面描画](ch-screen.md): `lib/ruvim/screen.rb`
> - [Unicode](ch-unicode.md): `lib/ruvim/display_width.rb`, `lib/ruvim/text_metrics.rb`
> - [C 拡張](ch-c-extension.md): `ext/ruvim/ruvim_ext.c`
> - [Sixel](ch-sixel.md): `lib/ruvim/sixel.rb`
