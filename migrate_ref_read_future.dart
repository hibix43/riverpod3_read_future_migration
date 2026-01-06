// =============================================================================
// migrate_ref_read_future.dart
// =============================================================================
// 概要:
//   `ref.read(xxxProvider.future)` パターンを検出し、指定したメソッド名に
//   書き換えるマイグレーションスクリプト。
//
// 機能:
//   - 指定ディレクトリ以下の全Dartファイルを再帰的に検索
//   - 括弧のネストを正確に処理
//   - 改行を含む複数行のパターンにも対応
//     (例: `ref\n  .read(xxxProvider.future)`)
//   - 指定されたインポート文を自動追加
//   - ドライランモードで変更内容を事前確認可能
//
// 使用方法:
//   fvm dart run scripts/migrate_ref_read_future.dart [ディレクトリ] [オプション]
//
// 必須オプション:
//   --import <path>   追加するインポート文（例: package:foo/bar.dart）
//
// オプション:
//   --method <name>   置換先のメソッド名（デフォルト: readFirst）
//   --dry-run         変更内容を表示するだけで実際には書き換えない（デフォルト）
//   --apply           実際にファイルを書き換える
//
// 使用例:
//   # ドライラン（変更内容の確認のみ）
//   fvm dart run scripts/migrate_ref_read_future.dart lib/app \
//     --method readFirst \
//     --import "package:project_name/app/common/extensions/ref_extension.dart"
//
//   # 実際に書き換え
//   fvm dart run scripts/migrate_ref_read_future.dart lib/app \
//     --method readFirst \
//     --import "package:project_name/app/common/extensions/ref_extension.dart" \
//     --apply
// =============================================================================

import 'dart:io';

// =============================================================================
// 設定クラス
// =============================================================================

/// コマンドライン引数をパースした設定
class Config {
  /// 検索対象ディレクトリ
  final String targetDir;

  /// 置換先のメソッド名
  final String methodName;

  /// 追加するインポート文
  final String importPath;

  /// 実際にファイルを書き換えるかどうか
  final bool apply;

  Config({
    required this.targetDir,
    required this.methodName,
    required this.importPath,
    required this.apply,
  });
}

// =============================================================================
// データクラス
// =============================================================================

/// マッチ結果を格納するデータクラス
class Match {
  /// マッチが開始する行番号（1始まり）
  final int line;

  /// マッチしたテキスト全体
  final String text;

  /// マッチの開始位置（ファイル先頭からのオフセット）
  final int startOffset;

  /// マッチの終了位置（ファイル先頭からのオフセット）
  final int endOffset;

  Match({
    required this.line,
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });
}

/// ファイル処理結果を格納するデータクラス
class FileResult {
  /// ファイルパス
  final String filePath;

  /// マッチした箇所のリスト
  final List<Match> matches;

  /// インポートが追加されたかどうか
  final bool importAdded;

  FileResult({
    required this.filePath,
    required this.matches,
    required this.importAdded,
  });
}

// =============================================================================
// エントリーポイント
// =============================================================================

void main(List<String> args) {
  // 引数をパース
  final config = parseArgs(args);

  // ディレクトリの存在確認
  final dir = Directory(config.targetDir);
  if (!dir.existsSync()) {
    print('Directory not found: ${config.targetDir}');
    exit(1);
  }

  // モード表示
  if (config.apply) {
    print('<!-- mode: APPLY (実際にファイルを書き換えます) -->');
  } else {
    print('<!-- mode: DRY-RUN (変更内容の確認のみ) -->');
  }
  print('');

  // --import で指定されたファイルのパス部分を抽出（対象外にするため）
  // 例: "package:foo/app/bar.dart" → "app/bar.dart"
  final importPathForExclusion = config.importPath.replaceFirst(
    RegExp(r'^package:[^/]+/'),
    '',
  );

  // 指定ディレクトリ以下の全Dartファイルを取得
  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith(importPathForExclusion)) // import先を除外
      .toList();

  // 結果を収集
  final results = <FileResult>[];

  // 各Dartファイルを処理
  for (final file in dartFiles) {
    final result = processFile(file, config);
    if (result != null) {
      results.add(result);
    }
  }

  // 結果を出力
  outputResults(results, config);
}

// =============================================================================
// 引数パース
// =============================================================================

/// コマンドライン引数をパースして設定を返す
Config parseArgs(List<String> args) {
  String targetDir = 'lib';
  String methodName = 'readFirst';
  String? importPath;
  bool apply = false;

  var i = 0;
  while (i < args.length) {
    final arg = args[i];

    if (arg == '--method') {
      // 次の引数がメソッド名
      if (i + 1 >= args.length) {
        print('Error: --method requires a value');
        exit(1);
      }
      methodName = args[i + 1];
      i += 2;
    } else if (arg == '--import') {
      // 次の引数がインポートパス
      if (i + 1 >= args.length) {
        print('Error: --import requires a value');
        exit(1);
      }
      importPath = args[i + 1];
      i += 2;
    } else if (arg == '--apply') {
      apply = true;
      i++;
    } else if (arg == '--dry-run') {
      apply = false;
      i++;
    } else if (arg.startsWith('-')) {
      print('Error: Unknown option: $arg');
      exit(1);
    } else {
      // 位置引数（ディレクトリ）
      targetDir = arg;
      i++;
    }
  }

  // --import は必須
  if (importPath == null) {
    print('Error: --import is required');
    print('');
    print(
      'Usage: fvm dart run scripts/migrate_ref_read_future.dart [dir] --import <path> [options]',
    );
    exit(1);
  }

  return Config(
    targetDir: targetDir,
    methodName: methodName,
    importPath: importPath,
    apply: apply,
  );
}

// =============================================================================
// ファイル処理
// =============================================================================

/// ファイルを処理し、結果を返す
/// マッチがない場合は null を返す
FileResult? processFile(File file, Config config) {
  var content = file.readAsStringSync();

  // パターンにマッチする箇所を全て検索
  final matches = findRefReadFuture(content);

  // マッチがない場合はスキップ
  if (matches.isEmpty) return null;

  // 置換を実行（後ろから置換することでオフセットがずれない）
  final sortedMatches = List<Match>.from(matches)
    ..sort((a, b) => b.startOffset.compareTo(a.startOffset));

  for (final match in sortedMatches) {
    // ref.read を ref.<method> に置換
    // 改行がある場合も考慮して、.read( を .<method>( に置換
    final original = match.text;
    final replaced = original.replaceFirst(
      RegExp(r'\.read\('),
      '.${config.methodName}(',
    );
    content =
        content.substring(0, match.startOffset) +
        replaced +
        content.substring(match.endOffset);
  }

  // インポートを追加
  final importResult = addImport(content, config.importPath);
  content = importResult.content;
  final importAdded = importResult.added;

  // 実際に書き換える場合はファイルに保存
  if (config.apply) {
    file.writeAsStringSync(content);
  }

  return FileResult(
    filePath: file.path,
    matches: matches,
    importAdded: importAdded,
  );
}

// =============================================================================
// パターン検索
// =============================================================================

/// ファイル内容から `ref.read(xxxProvider.future)` パターンを全て検索する
/// `ref` と `.read(` の間に改行や空白がある場合にも対応
List<Match> findRefReadFuture(String content) {
  final results = <Match>[];
  const refPattern = 'ref';
  var index = 0;

  while (true) {
    // 'ref' を検索
    final refStart = content.indexOf(refPattern, index);
    if (refStart == -1) break;

    // 'ref' の後に空白/改行/ドットをスキップして '.read(' を探す
    final readStart = findReadAfterRef(content, refStart);
    if (readStart == -1) {
      index = refStart + 1;
      continue;
    }

    // 開き括弧の位置を取得
    final parenStart = readStart + '.read('.length - 1;
    final parenEnd = findMatchingParen(content, parenStart);

    if (parenEnd != -1) {
      final inside = content.substring(parenStart + 1, parenEnd);

      // 括弧内が '.future' で終わっているかチェック
      if (RegExp(r'\.future\s*,?\s*$').hasMatch(inside)) {
        final matchText = content.substring(refStart, parenEnd + 1);
        final line = getLineNumber(content, refStart);

        results.add(
          Match(
            line: line,
            text: matchText,
            startOffset: refStart,
            endOffset: parenEnd + 1,
          ),
        );
      }
    }

    index = refStart + 1;
  }

  return results;
}

/// 'ref' の後に空白/改行/ドットをスキップして '.read(' を探す
/// 見つかった場合は '.read(' の開始位置を返す、見つからなければ -1
int findReadAfterRef(String content, int refStart) {
  // 'ref' の終了位置
  final refEnd = refStart + 'ref'.length;

  // 範囲チェック
  if (refEnd >= content.length) return -1;

  var i = refEnd;

  // 空白、改行、ドットをスキップ
  while (i < content.length) {
    final char = content[i];
    if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
      i++;
    } else if (char == '.') {
      // ドットが見つかったら、その後に 'read(' があるかチェック
      if (i + 'read('.length < content.length) {
        final nextPart = content.substring(i + 1, i + 1 + 'read('.length);
        if (nextPart == 'read(') {
          return i; // '.read(' の開始位置（ドットの位置）
        }
      }
      // ドットの後に 'read(' がない場合は終了
      return -1;
    } else {
      // 期待しない文字が見つかった場合は終了
      return -1;
    }
  }

  return -1;
}

/// 対応する閉じ括弧の位置を返す（見つからなければ -1）
int findMatchingParen(String content, int openIndex) {
  if (content[openIndex] != '(') return -1;

  var depth = 1;
  for (var i = openIndex + 1; i < content.length; i++) {
    final char = content[i];

    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return i;
    } else if (char == '"' || char == "'") {
      i = skipString(content, i);
    }
  }

  return -1;
}

/// 文字列リテラルをスキップし、終了位置を返す
int skipString(String content, int start) {
  final quote = content[start];

  for (var i = start + 1; i < content.length; i++) {
    if (content[i] == '\\') {
      i++;
    } else if (content[i] == quote) {
      return i;
    }
  }

  return content.length - 1;
}

/// 指定位置の行番号を計算する（1始まり）
int getLineNumber(String content, int index) {
  return content.substring(0, index).split('\n').length;
}

// =============================================================================
// インポート追加
// =============================================================================

/// インポート追加の結果
class ImportResult {
  final String content;
  final bool added;
  ImportResult(this.content, this.added);
}

/// インポート文を追加する
/// 既に存在する場合は追加しない
ImportResult addImport(String content, String importPath) {
  // 前後の空白を除去
  final trimmedPath = importPath.trim();
  final importStatement = "import '$trimmedPath';";

  // 既にインポートが存在するかチェック
  if (content.contains(importStatement)) {
    return ImportResult(content, false);
  }

  // インポート部分のパターンも確認（引用符の違いを考慮）
  final altImportStatement = 'import "$trimmedPath";';
  if (content.contains(altImportStatement)) {
    return ImportResult(content, false);
  }

  // 最後のimport文の位置を探す
  final importRegex = RegExp(
    r"""^import\s+['\"].*['\"];?\s*$""",
    multiLine: true,
  );
  final matches = importRegex.allMatches(content).toList();

  if (matches.isEmpty) {
    // import文がない場合は先頭に追加
    return ImportResult('$importStatement\n\n$content', true);
  }

  // 最後のimport文の後に追加
  final lastMatch = matches.last;
  final insertPosition = lastMatch.end;

  final newContent =
      content.substring(0, insertPosition) +
      '\n$importStatement' +
      content.substring(insertPosition);

  return ImportResult(newContent, true);
}

// =============================================================================
// 結果出力
// =============================================================================

/// 結果をMarkdown形式で出力する
void outputResults(List<FileResult> results, Config config) {
  var totalCount = 0;

  for (final result in results) {
    totalCount += result.matches.length;

    // ファイル名を取得
    final fileName = result.filePath.split('/').last;

    print('- **$fileName**\n');
    print('  ${result.filePath}');

    // マッチ結果を出力
    for (final match in result.matches) {
      final singleLineText = match.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final replacedText = singleLineText.replaceFirst(
        RegExp(r'\.read\('),
        '.${config.methodName}(',
      );
      print('  - `$singleLineText` → `$replacedText` (L${match.line})');
    }

    // インポート追加の表示
    if (result.importAdded) {
      final importFileName = config.importPath.split('/').last;
      print('  - import追加: `$importFileName`');
    }

    print('');
  }

  // サマリー
  print('---\n');
  if (config.apply) {
    print('**完了:** ${results.length} ファイル / $totalCount 箇所を書き換えました');
  } else {
    print('**検出:** ${results.length} ファイル / $totalCount 箇所\n');
    print('実際に書き換えるには `--apply` オプションを追加してください。');
  }
}
