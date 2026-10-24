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
