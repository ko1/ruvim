# Vimとの違い

## RuVim の独自機能

- **[Ruby DSL 設定](ch-config.md)**: init.rb で Ruby の全機能を利用可能（Vim script 不要）
- **[`:ruby` コマンド](ch-plugin-api.md)**: 実行中に Ruby eval が可能
- **[Rich View モード](ch-rich-view.md)**: TSV/CSV/Markdown/JSON/画像の構造化表示
- **[Follow mode](ch-streams.md#follow-コマンド)**: `:follow` / `-f` でファイル追従（`tail -f` 相当）
- **[ストリーム連携](ch-streams.md)**: stdin パイプ、`:run` でリアルタイム出力表示
- **検索は [Ruby 正規表現](ch-search-replace.md#検索)**: Vim regex ではなく Ruby の Regexp を使用
- **[ネスト分割](ch-windows.md#ネスト分割)**: ツリー構造のウィンドウレイアウト
- **Shift+矢印キー**: スマート分割（1ウィンドウなら分割、2つ以上ならフォーカス移動）

## 動作の差分

- undo 粒度は簡略化（Insert mode は入ってから出るまでが 1 undo 単位）
- `.` repeat のカウント互換は完全ではない
- word motion の単語境界定義が Vim と一致しない場合がある
- 文字幅は近似（East Asian Width 完全互換ではない）
- `:w\!` は現状 `:w` とほぼ同じ（権限昇格は未実装）
- Visual blockwise は最小対応
- option 名の短縮（`nu`, `ts` 等）は未対応
- `:set` の `+=`, `-=` は未対応

## 未実装の主要機能

- Vim script 互換
- folds
- LSP / diagnostics
- job / channel / terminal
- swap / backup（undofile は実装済み）
- diff mode, session（placeholder のみ）
