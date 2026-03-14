# 対応言語一覧（26言語）

| filetype | 拡張子 | ハイライト方式 | インデント | on_save |
|----------|--------|---------------|-----------|---------|
| ruby | .rb | Prism lexer | あり | ruby -wc |
| json | .json | regex | あり | — |
| jsonl | .jsonl | regex | — | — |
| markdown | .md | regex | — | — |
| scheme | .scm | regex | — | — |
| c | .c, .h | regex | あり | gcc |
| cpp | .cpp, .hpp, .cc | regex（C拡張） | あり | g++ |
| diff | .diff, .patch | regex | — | — |
| yaml | .yml, .yaml | regex | あり | — |
| sh | .sh, .bash | regex | あり | — |
| python | .py | regex | あり | — |
| javascript | .js, .jsx | regex | あり | — |
| typescript | .ts, .tsx | regex（JS拡張） | あり | — |
| html | .html, .htm | regex | — | — |
| toml | .toml | regex | — | — |
| go | .go | regex | あり | — |
| rust | .rs | regex | あり | — |
| make | Makefile | regex | — | — |
| dockerfile | Dockerfile | regex | — | — |
| sql | .sql | regex | — | — |
| elixir | .ex, .exs | regex | あり | — |
| perl | .pl, .pm | regex | あり | — |
| lua | .lua | regex | あり | — |
| ocaml | .ml, .mli | regex | あり | — |
| erb | .erb | regex（HTML+Ruby） | — | — |
| gitcommit | COMMIT_EDITMSG | regex | — | — |

追加の filetype（Rich View 用）:

| filetype | 拡張子 | 用途 |
|----------|--------|------|
| tsv | .tsv | テーブル表示 |
| csv | .csv | テーブル表示 |
| image | .png, .jpg, .gif, .bmp, .webp | 画像表示 |
