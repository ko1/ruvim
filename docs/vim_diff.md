# RuVim と Vim の違い

RuVim は「Vim ライクな Ruby 製ターミナルエディタ」です。Vim 完全互換ではなく、Vim の操作感を優先しつつ一部を独自拡張・簡略化しています。

## RuVim の独自機能・強み

### Ruby ネイティブな拡張性

- 設定ファイルは Ruby DSL（`~/.config/ruvim/init.rb`）
  - `nmap`, `imap`, `map_global`, `command`, `ex_command`, `ex_command_call`
  - Vim script 不要で Ruby の全機能を利用可能
- `:ruby` / `:rb` で実行中に Ruby eval が可能（Vim の `:ruby` とは別物）
- plugin 向け `ctx.editor / ctx.buffer / ctx.window` API

### ネストしたウィンドウ分割（Layout Tree）

- `:vsplit` 後に `:split` すると、対象カラムだけが上下分割される（Vim と同様のツリー構造）
- 同方向の連続分割は自動的にフラット化（例: hsplit の中で hsplit → 1 レベルに統合）
- `Shift+Arrow` キーによるスマート分割
  - 同軸方向に既存ウィンドウがあればフォーカス移動
  - なければ新規分割（cross-direction split にも対応）
  - ツリーパスベースの判定で、別領域のウィンドウに影響されない

### Rich View モード

- TSV / CSV / Markdown をフォーマットして閲覧できる構造化データ表示モード
- CJK 文字幅を考慮したカラム整列

### 検索は Ruby 正規表現

- `/`, `?`, `:s` はすべて Ruby の `Regexp` を使用
- Vim regex と異なる点はあるが、Ruby 利用者には馴染みやすい
- `:help regex` でヘルプ表示

## Vim と同等に実装済みの機能

### モード・編集操作

- Normal / Insert / Command-line / Visual（charwise, linewise, blockwise）
- operator-pending: `d`, `y`, `c` + motion / text object
- text object: `iw/aw`, `ip/ap`, `i"/a"`, `` i`/a` ``, `i)/a)`, `i]/a]`, `i}/a}`
- `.` repeat: `x`, `dd`, `d{motion}`, `p/P`, `r<char>`, `i/a/A/I/o/O`, `cc`, `c{motion}`
  - macro 記録中の `.` は内部再生キーを macro に混ぜない
- word motion: `w`, `b`, `e`（`iskeyword` 対応）
- macros: `q{reg}`, `@{reg}`, `@@`
- marks / jumps: `m`, `'`, `` ` ``, `''`, ` `` `, `<C-o>`, `<C-i>`

### レジスタ

- unnamed（`"`）, named（`"a`〜`"z`, `"A` append）, black hole（`"_`）
- yank `"0`, numbered delete `"1`〜`"9`
- system clipboard `"+`, `"*`（`pbcopy/pbpaste`, `wl-copy/wl-paste`, `xclip`, `xsel`）

### Ex コマンド

- `:w`, `:q`, `:wq`, `:e`, `:buffer`, `:bnext`, `:bprev`, `:ls`, `:split`, `:vsplit`
- `:qa`, `:qa!`, `:wqa`
- quickfix / location list: `:vimgrep`, `:lvimgrep`, `:copen`, `:cnext`, `:lopen`, `:lnext`
- tabpage: `:tabnew`, `:tabnext`, `:tabprev`

### option system

- `:set`, `:setlocal`, `:setglobal`（global / buffer-local / window-local）
- 表示系: `number`, `relativenumber`, `cursorline`, `wrap`, `linebreak`, `breakindent`, `showbreak`, `list`, `listchars`, `colorcolumn`, `signcolumn`, `numberwidth`, `scrolloff`, `sidescrolloff`, `termguicolors`
- インデント: `shiftwidth`, `softtabstop`, `expandtab`, `autoindent`, `smartindent`, `tabstop`
- 検索: `ignorecase`, `smartcase`, `hlsearch`, `incsearch`
- 分割: `splitbelow`, `splitright`
- その他: `hidden`, `autowrite`, `clipboard`, `timeoutlen`, `ttimeoutlen`, `backspace`, `whichwrap`, `iskeyword`, `filetype`, `path`, `suffixesadd`, `grepprg`, `grepformat`, 補完系（`completeopt`, `pumheight`, `wildmode`, `wildmenu`, `wildignore`, `wildignorecase`）

### その他

- filetype 検出（拡張子 + shebang）/ ftplugin
- syntax highlight: Ruby（Prism lexer）, JSON, Markdown, Scheme, TSV/CSV
- 補完: Ex コマンド名 + 引数補完, Insert mode buffer words（`Ctrl-n` / `Ctrl-p`）
- CLI: `--help`, `--version`, `--clean`, `-u`, `-R`, `-M`, `-Z`, `-o/-O/-p`, `-c`, `+{cmd}`, `-V`, `--startuptime`, `--cmd`

## 動作の微細な差分

- undo 粒度は簡略化（Insert mode は「入ってから出るまで」が 1 undo 単位）
- `.` repeat のカウント互換は完全ではない
- word motion の単語境界定義が Vim と一致しない場合がある
- paste のカーソル位置ルールに Vim との差がある可能性がある
- 文字幅対応は近似（CJK / emoji 幅2 / grapheme cluster は対応するが、East Asian Width 完全互換ではない）
- ANSI + raw mode の自前描画（行キャッシュによる簡易差分描画で Vim の描画最適化とは別実装）
- `SIGWINCH + self-pipe + IO.select` でリサイズ追従
- `:w!` は現状 `:w` とほぼ同じ（権限昇格や readonly 強制保存は未実装）
- `:command` は Ex 文字列エイリアス展開の簡易実装
- Visual blockwise は矩形選択 + `y/d` の最小対応（blockwise text object / paste の Vim 互換挙動は未実装）
- option 名短縮（`nu`, `ts` 等）は未対応
- `:set` の高度な構文（`+=`, `-=`, `^=` 等）は未対応
- small delete register `"-` は未実装

## 未実装の主要機能

- Vim script 互換 / プラグイン互換
- folds
- LSP / diagnostics
- job / channel / terminal 連携
- `:grep`, `:make`, `:cfile`, `:lgrep`
- substitute の高度なフラグ群（現状は `:%s/.../.../g` のみ）
- swap / backup / undofile（永続 undo）
- `-d`（diff mode）, `-q`（quickfix mode）, `-S`（session）は placeholder のみ
