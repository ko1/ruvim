# 設計パターンと判断の記録

> 「迷ったら原点に戻れ」 — 松下幸之助

最後に、RuVim の設計で採用された[設計パターン](#index:設計パターン)と、その背景にある判断を整理する。

## 依存注入 (Dependency Injection)

すべてのコンポーネントは `App` が生成し、コンストラクタ引数やセッターで注入する。`Editor` は `KeymapManager` や `StreamMixer` への参照を外部からもらう。これにより、テスト時にモックや単純な実装に差し替えられる。

> [!TIP]
> 実際のテストでの DI の活用例は[テスト戦略](ch-testing.md)の `fresh_editor` を参照。

## 遅延ロード (Lazy Loading)

```ruby
module RuVim
  autoload :Clipboard, File.expand_path("clipboard", __dir__)
  autoload :Browser, File.expand_path("browser", __dir__)
  autoload :SpellChecker, File.expand_path("spell_checker", __dir__)
  autoload :FileWatcher, File.expand_path("file_watcher", __dir__)
end
```

クリップボード、ブラウザ、スペルチェッカー、ファイルウォッチャー、すべての言語モジュール、Git/GitHub インテグレーションは、初めて参照されるまでロードされない。起動時間を短縮するための重要な戦略だ。

> [!NOTE]
> autoload は Ruby のスレッドセーフな遅延ロード機構だ。初回アクセス時にのみファイルが `require` される。

## フリーズしたシングルトン

言語モジュールは `@instance ||= new.freeze` というパターンでインスタンスを提供する。`freeze` することで、ハイライト処理中に誤って状態を変更する可能性を排除する。

## コールバックとしてのラムダ

`Editor` は `@suspend_handler`、`@shell_executor`、`@confirm_key_reader` といったコールバックをラムダとして保持する。これにより、Editor が Terminal や Input の存在を知らなくても、必要な操作を実行できる。

```ruby
@editor.shell_executor = ->(command) {
  result = @terminal.suspend_for_shell(command)
  @screen.invalidate_cache!
  result
}
```

## 状態機械としてのペンディング状態

`KeyHandler` の各ペンディング状態（オペレータ、レジスタ、マーク等）は、明示的なフラグとして管理される。有限状態機械の各状態に対応するメソッドが呼ばれ、次の入力に応じて遷移する。

複雑さを制御するため、`PendingState`、`MacroDot`、`InsertMode` の 3 つのモジュールに分割している。

## エラー境界としての CommandError

すべてのコマンドエラーは `RuVim::CommandError` として送出され、`KeyHandler#handle` と `Dispatcher#dispatch` で捕捉される。

```ruby
def handle(key)
  # ... キー処理 ...
rescue RuVim::CommandError => e
  @editor.echo_error(e.message)
  false
end
```

どんなコマンドがエラーを起こしても、エディタ自体はクラッシュせず、エラーメッセージを表示して通常動作を続ける。

## モノトニッククロックの一貫した使用

時刻が関わる処理（タイムアウト、パフォーマンス計測、メッセージの有効期限）はすべて `Process.clock_gettime(Process::CLOCK_MONOTONIC)` を使う。`Time.now` は NTP 同期で巻き戻る可能性があるため使わない。

```ruby
def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
rescue StandardError
  Time.now.to_f   # フォールバック
end
```
