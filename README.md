# ref.read(xxxProvider.future) マイグレーションスクリプト

> ⚠️ **注意**
>
> このスクリプトは簡易的なツールです。エッジケースは考慮していません。
> また、メンテナンスの予定はありません。使用は自己責任でお願いします。

Riverpod 3 へのマイグレーションを支援するDartスクリプトです。

## 概要

`ref.read(xxxProvider.future)` パターンを検出し、指定したメソッド（例: `readFirst`）に自動で書き換えます。

## 機能

- 指定ディレクトリ以下の全Dartファイルを再帰的に検索
- 括弧のネストを正確に処理
- 改行を含む複数行のパターンにも対応
- 指定されたインポート文を自動追加
- ドライランモードで変更内容を事前確認可能

## 使用方法

```bash
fvm dart run migrate_ref_read_future.dart [ディレクトリ] [オプション]
```

### 必須オプション

| オプション | 説明 |
|-----------|------|
| `--import <path>` | 追加するインポート文（例: `package:foo/bar.dart`） |

### オプション

| オプション | 説明 |
|-----------|------|
| `--method <name>` | 置換先のメソッド名（デフォルト: `readFirst`） |
| `--dry-run` | 変更内容を表示するだけで実際には書き換えない（デフォルト） |
| `--apply` | 実際にファイルを書き換える |

## 使用例

### ドライラン（変更内容の確認のみ）

```bash
fvm dart run migrate_ref_read_future.dart lib/app \
  --method readFirst \
  --import "package:project_name/app/common/extensions/ref_extension.dart"
```

### 実際に書き換え

```bash
fvm dart run migrate_ref_read_future.dart lib/app \
  --method readFirst \
  --import "package:project_name/app/common/extensions/ref_extension.dart" \
  --apply
```

## 変換例

```dart
// Before
final value = await ref.read(userProvider.future);

// After
final value = await ref.readFirst(userProvider.future);
```

---

## readFirst のサンプル

```dart
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref;
import 'package:hooks_riverpod/misc.dart' show Refreshable;

extension RefExtension on Ref {
  /// `ref.read(provider.future)` の代替として、一度きりの読み取りを行う。
  ///
  /// ## なぜこのメソッドが必要か
  ///
  /// Riverpod 3では、`await ref.read(provider.future)` が使用できなくなった。
  /// 以下の問題が発生するため：
  ///
  /// 1. **無限待機**: プロバイダーがリスナーを持たない場合、
  ///    autoDispose により dispose されて Future が永遠に完了しない。
  ///    See: https://github.com/rrousselGit/riverpod/issues/3745
  ///
  /// 2. **disposed during loading エラー**: StreamProvider 等で
  ///    ローディング中に dispose されると例外がスローされる。
  ///    See: https://github.com/rrousselGit/riverpod/issues/4339
  ///
  /// ## 解決策
  ///
  /// `ref.listen` を使用してサブスクリプションを保持することで、
  /// プロバイダーが dispose されることを防ぎ、一度きりの読み取りを安全に行う。
  ///
  /// ### なぜ `readFirst` という命名か
  ///
  /// See: https://github.com/rrousselGit/riverpod/issues/4339#issuecomment-3553945908
  ///
  Future<T> readFirst<T>(Refreshable<Future<T>> listenable) async {
    final subscription = listen(listenable, (p, n) {});
    try {
      return await subscription.read();
    } finally {
      subscription.close();
    }
  }
}

```
