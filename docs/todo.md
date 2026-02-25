# RuVim TODO

## 方針

- まずは「日常的に触れる Vim ライク編集体験」を優先
- その次に「拡張性（`:command`, `:ruby`, keymap layering）」を強化
- 最後に「性能・互換性・品質」を詰める
- このファイルは未完了項目を管理する
- 完了済みの項目は `docs/done.md` に移動して管理する

作業時のルール:
- 着手時にこのファイルを編集する（`DOING` にするなど）
- 実装に合わせて docs を更新する
  - `docs/spec.md`
  - `docs/tutorial.md`
  - `docs/binding.md`
  - `docs/command.md`
  - `docs/config.md`
  - `docs/vim_diff.md`

## TODO Vim 互換性の精度向上

- Vim 互換性の精度向上（word motion / paste / visual 挙動）
  - `w`, `b`, `e` の境界判定を Vim に寄せる
  - `p`, `P` のカーソル位置ルールを調整
  - Visual mode の端点/inclusive ルールを整理

## TODO 永続化

- 永続 undo / セッション
  - undo history 保存
  - session file（開いている buffer / cursor 位置）

## TODO 長期（規模大）

### P3: 長期（人気はあるが規模大）

- LSP / diagnostics（中長期）
  - language server 起動管理
  - diagnostics 表示
  - definition / references ジャンプ

- LSP diagnostics + jump（最小）
  - 効果: 高
  - コスト: 高
  - 依存:
    - job/process 管理
    - diagnostics モデル
    - 画面表示（sign/underline/一覧）

- fuzzy finder（file/buffer/grep）
  - 効果: 高
  - コスト: 高
  - 依存:
    - picker UI
    - grep/検索基盤
    - preview（任意）

## メモ（方針）

- Vim 完全互換の CLI を目指すより、よく使うフラグから互換寄りに実装する
- Ruby DSL 前提なので、Vim の `-u NONE` / `-U NONE` は RuVim 向けに意味を再定義してよい

