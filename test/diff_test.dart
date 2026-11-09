import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('reads the line numbers of the new version', () {
    final List<DiffFile> files = parseDiff(sampleDiff);

    expect(files, hasLength(1));
    expect(files.single.path, 'lib/a.dart');
    expect(files.single.addedLines, <int>{11, 12});
    expect(files.single.commentableLines, <int>{10, 11, 12, 13});
  });

  test('skips deleted files', () {
    final List<DiffFile> files = parseDiff(sampleDiff);

    expect(
      files.map((DiffFile file) => file.path),
      isNot(contains('lib/old.dart')),
    );
  });

  test('reads deleted files apart, with their removed lines only', () {
    final DiffFile file = parseDeletedFiles(sampleDiff).single;

    expect(file.path, 'lib/old.dart');
    expect(file.annotated, contains('      |-void old() {}'));
    expect(file.addedLines, isEmpty);
  });

  test('keeps the code of the hunks that add a line', () {
    final DiffFile file = parseDiff(sampleDiff).single;

    expect(file.aroundCode, <String>[
      '  final int x;',
      '  final int z;',
      '  final int w;',
      '  void run() {}',
    ]);
  });

  test('keeps a line that is only re-indented as unchanged', () {
    // A widget wrapped in a Column: its line moves to the right only.
    final DiffFile file = parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +1,4 @@
 child:
-  Text('a'),
+  Column(
+    Text('a'),
+  ),
''').single;

    expect(file.addedLines, <int>{2, 4});
    expect(file.addedCode, <String>['  Column(', '  ),']);
    expect(file.removedBefore, isEmpty);
    expect(file.annotated, contains("    3 |     Text('a'),"));
    expect(file.annotated, isNot(contains("      |-  Text('a'),")));
    expect(file.aroundCode, contains("    Text('a'),"));
  });

  test('puts the line number in front of each line', () {
    final DiffFile file = parseDiff(sampleDiff).single;

    expect(file.annotated, contains('   11 |+  final int z;'));
    expect(file.annotated, contains('      |-  final int y;'));
  });

  test('accepts Windows line endings', () {
    final List<DiffFile> files = parseDiff(sampleDiff.replaceAll('\n', '\r\n'));

    expect(files.single.addedLines, <int>{11, 12});
  });

  test('keeps the code of each line of the new version', () {
    final DiffFile file = parseDiff(sampleDiff).single;

    expect(file.newLineText[10], '  final int x;');
    expect(file.newLineText[12], '  final int w;');
    expect(file.newLineText.containsKey(14), isFalse);
  });
}
