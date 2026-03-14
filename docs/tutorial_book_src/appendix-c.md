# オプション全一覧（51個）

## Window-local

| 名前 | 型 | デフォルト | 状態 | 使い方の例 |
|------|------|-----------|------|-----------|
| `number` | bool | false | DONE | `使い方: :set number` — 行番号を表示してコードの行数を把握しやすくする |
| `relativenumber` | bool | false | DONE | `使い方: :set relativenumber` — 相対行番号表示でカウント付きジャンプを効率化 |
| `wrap` | bool | true | PARTIAL | `使い方: :set nowrap` — 長い行を折り返さず横スクロールで表示 |
| `linebreak` | bool | false | PARTIAL | `使い方: :set linebreak` — 単語の途中で折り返さず空白位置で改行 |
| `breakindent` | bool | false | PARTIAL | `使い方: :set breakindent` — 折り返し行にもインデントを反映して読みやすくする |
| `cursorline` | bool | false | DONE | `使い方: :set cursorline` — 現在行を背景色でハイライトして見失いを防止 |
| `scrolloff` | int | 0 | DONE | `使い方: :set scrolloff=5` — カーソルの上下に常に5行の余白を確保 |
| `sidescrolloff` | int | 0 | DONE | `使い方: :set sidescrolloff=10` — カーソルの左右に10桁の余白を確保 |
| `numberwidth` | int | 4 | DONE | `使い方: :set numberwidth=6` — 行番号列を6桁に広げて大きなファイルに対応 |
| `colorcolumn` | string | nil | DONE | `使い方: :set colorcolumn=80` — 80桁目にガイド線を表示して行長を意識 |
| `signcolumn` | string | "auto" | PARTIAL | `使い方: :set signcolumn=yes` — サイン列を常に表示してレイアウトのずれを防止 |
| `list` | bool | false | PARTIAL | `使い方: :set list` — タブや末尾空白を可視化して意図しない空白を発見 |
| `listchars` | string | "tab:>-,trail:-,nbsp:+" | PARTIAL | `使い方: :set listchars=tab:▸\ ,trail:·` — 不可視文字の表示記号をカスタマイズ |
| `showbreak` | string | "" | PARTIAL | `使い方: :set showbreak=↪\ ` — 折り返し行の先頭に矢印を表示 |

## Global

| 名前 | 型 | デフォルト | 状態 | 使い方の例 |
|------|------|-----------|------|-----------|
| `showmatch` | bool | false | PARTIAL | `使い方: :set showmatch` — 閉じ括弧入力時に対応する開き括弧を一瞬ハイライト |
| `matchtime` | int | 5 | PARTIAL | `使い方: :set matchtime=3` — showmatch のハイライト時間を 0.3 秒に短縮 |
| `whichwrap` | string | "" | PARTIAL | `使い方: :set whichwrap=h,l` — h/l で行をまたいで移動可能にする |
| `virtualedit` | string | "" | PARTIAL | `使い方: :set virtualedit=all` — 文字のない位置にもカーソルを置けるようにする |
| `ignorecase` | bool | false | DONE | `使い方: :set ignorecase` — 検索時に大文字小文字を区別しない |
| `smartcase` | bool | false | DONE | `使い方: :set smartcase` — 大文字を含む検索パターンだけ case-sensitive にする |
| `hlsearch` | bool | true | DONE | `使い方: :set nohlsearch` — 検索マッチのハイライトを無効化 |
| `incsearch` | bool | false | PARTIAL | `使い方: :set incsearch` — 検索パターン入力中にリアルタイムでマッチを表示 |
| `splitbelow` | bool | false | DONE | `使い方: :set splitbelow` — :split 時に新ウィンドウを下に配置 |
| `splitright` | bool | false | DONE | `使い方: :set splitright` — :vsplit 時に新ウィンドウを右に配置 |
| `hidden` | bool | false | PARTIAL | `使い方: :set hidden` — 未保存バッファがあっても別バッファへの切替を許可 |
| `autowrite` | bool | false | PARTIAL | `使い方: :set autowrite` — バッファ切替時に変更済みバッファを自動保存 |
| `clipboard` | string | "" | PARTIAL | `使い方: :set clipboard=unnamedplus` — yank/paste をシステムクリップボードと連携 |
| `timeoutlen` | int | 1000 | DONE | `使い方: :set timeoutlen=500` — キーマップの入力待ち時間を 500ms に短縮 |
| `ttimeoutlen` | int | 50 | DONE | `使い方: :set ttimeoutlen=10` — ESC キーの応答を高速化 |
| `backspace` | string | "indent,eol,start" | PARTIAL | `使い方: :set backspace=indent,eol,start` — Backspace が越えられる境界を設定 |
| `completeopt` | string | "menu,menuone,noselect" | PARTIAL | `使い方: :set completeopt=menu,menuone` — 補完メニューの挙動を調整 |
| `pumheight` | int | 10 | PARTIAL | `使い方: :set pumheight=20` — 補完候補の表示件数を最大20件に増加 |
| `wildmode` | string | "full" | PARTIAL | `使い方: :set wildmode=longest` — Tab 補完で最長共通部分まで展開 |
| `wildignore` | string | "" | DONE | `使い方: :set wildignore=*.o,*.pyc` — 補完候補から不要なファイルを除外 |
| `wildignorecase` | bool | false | DONE | `使い方: :set wildignorecase` — ファイル名補完で大文字小文字を無視 |
| `wildmenu` | bool | false | PARTIAL | `使い方: :set wildmenu` — コマンドライン補完候補を一覧表示 |
| `termguicolors` | bool | false | PARTIAL | `使い方: :set termguicolors` — 24bit truecolor 描画を有効化 |
| `undofile` | bool | true | DONE | `使い方: :set noundofile` — undo 履歴の永続化を無効にする |
| `undodir` | string | nil | DONE | `使い方: :set undodir=~/.ruvim/undo` — undo ファイルの保存先を変更 |
| `syncload` | bool | false | DONE | `使い方: :set syncload` — 大ファイルを非同期ではなく同期的に読み込む |
| `grepprg` | string | "grep -nH" | DONE | `使い方: :set grepprg=rg\ --vimgrep` — grep コマンドを ripgrep に変更 |
| `grepformat` | string | "%f:%l:%m" | DONE | `使い方: :set grepformat=%f:%l:%c:%m` — grep 出力のパース書式を調整 |
| `sixel` | string | "auto" | — | `使い方: :set sixel=on` — sixel 画像表示を強制的に有効にする |

## Buffer-local

| 名前 | 型 | デフォルト | 状態 | 使い方の例 |
|------|------|-----------|------|-----------|
| `path` | string | nil | PARTIAL | `使い方: :set path=.,lib,test` — gf でファイルを探索するディレクトリを指定 |
| `suffixesadd` | string | nil | PARTIAL | `使い方: :set suffixesadd=.rb,.rake` — gf で拡張子を自動補完 |
| `textwidth` | int | 0 | 定義のみ | `使い方: :set textwidth=80` — 自動改行の桁数（将来実装予定） |
| `formatoptions` | string | nil | 定義のみ | `使い方: :set formatoptions=tcq` — テキスト整形オプション（将来実装予定） |
| `expandtab` | bool | false | DONE | `使い方: :set expandtab` — Tab キーでスペースを挿入する |
| `shiftwidth` | int | 2 | PARTIAL | `使い方: :set shiftwidth=4` — インデント幅を4に変更 |
| `softtabstop` | int | 0 | PARTIAL | `使い方: :set softtabstop=4` — Tab 入力時の編集上の幅を4に設定 |
| `autoindent` | bool | true | DONE | `使い方: :set noautoindent` — 改行時のインデント引き継ぎを無効化 |
| `smartindent` | bool | true | PARTIAL | `使い方: :set nosmartindent` — 括弧ベースの自動インデントを無効化 |
| `iskeyword` | string | nil | PARTIAL | `使い方: :setlocal iskeyword=@,48-57,_,-` — 単語境界の定義を変更 |
| `tabstop` | int | 2 | DONE | `使い方: :set tabstop=4` — タブ文字の表示幅を4に変更 |
| `filetype` | string | nil | DONE | `使い方: :set filetype=python` — ファイルタイプを手動で設定 |
| `spell` | bool | false | DONE | `使い方: :set spell` — スペルチェックを有効にする |
| `spelllang` | string | "en" | 定義のみ | `使い方: :set spelllang=en` — スペルチェックの言語（将来実装予定） |
| `onsavehook` | bool | true | DONE | `使い方: :set noonsavehook` — 保存時の構文チェックフックを無効化 |
