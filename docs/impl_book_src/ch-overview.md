# 全体像 — エディタとは何をするプログラムか

> 「簡素にして品格あり」 — 千利休

テキストエディタは、一見シンプルなプログラムに見える。テキストを読み込み、ユーザーの入力に応じて編集し、ファイルに保存する。しかし実際に作ってみると、そこには驚くほど多くの技術的課題がある。

- **ターミナル制御**: 端末をロー（raw）モードに切り替え、エスケープシーケンスで画面を制御する
- **キー入力の解釈**: マルチバイトのエスケープシーケンスを正しくパースし、タイムアウトで曖昧さを解消する
- **モード管理**: Normal, Insert, Visual, Command-line など複数のモードで異なる振る舞いをする
- **テキスト操作**: undo/redo、テキストオブジェクト、レジスタ、マクロなど
- **Unicode**: 結合文字、CJK 全角文字、絵文字の表示幅を正しく扱う
- **非同期 I/O**: 外部コマンドの実行結果をリアルタイムに表示する
- **画面描画の最適化**: フレームごとの差分だけを端末に送る

RuVim のアーキテクチャは、これらの関心事を明確に分離している。

```
CLI (exe/ruvim) → CLI.parse() → App.new() → App.run_ui_loop()
  Input.read_key() → KeymapManager.resolve() → Dispatcher.dispatch()
  → GlobalCommands.<method>() → Editor state update → Screen.render() → Terminal.write()
```

主要なオブジェクトの依存関係は以下の通りだ。

```
App
├── Terminal ──── stdin/stdout I/O
├── Input ─────── キーボード入力パース（Terminal から読む）
├── Screen ────── 描画（Terminal に書く）
├── KeymapManager ── キーからコマンドへの解決
├── Dispatcher ──── コマンドルーティング
├── Editor ──────── バッファ、ウィンドウ、モード等の状態
├── StreamMixer ─── 非同期ストリームの調整
├── KeyHandler ──── キー処理、モード遷移、ペンディング状態
└── ConfigLoader ── ユーザー設定の読み込み
```

すべてのオブジェクトは `App` が生成し、依存注入（Dependency Injection）で結合する。グローバル変数やグローバルなシングルトンへの暗黙的な依存は避け、テスタビリティを確保している。
