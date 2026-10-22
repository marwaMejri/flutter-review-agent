import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('reads the findings, even inside a Markdown code block', () {
    const String answer = '''
```json
{"findings": [{"rule": "P1", "file": "lib/a.dart", "line": 11, "message": "Move it."}]}
```''';

    final List<Finding> findings = parseFindings(answer);

    expect(findings.single.rule, 'P1');
    expect(findings.single.line, 11);
  });

  test('refuses an answer that is not the expected JSON', () {
    expect(
      () => parseFindings('No problems found.'),
      throwsA(isA<InvalidAnswerException>()),
    );
  });

  test('keeps only known rules on lines of the diff', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(rule: 'P1', file: 'lib/a.dart', line: 11, message: 'ok'),
      Finding(rule: 'X9', file: 'lib/a.dart', line: 11, message: 'invented'),
      Finding(rule: 'P1', file: 'lib/b.dart', line: 11, message: 'other file'),
      Finding(rule: 'P1', file: 'lib/a.dart', line: 99, message: 'other line'),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted.map((Finding f) => f.message), <String>['ok']);
    expect(result.rejected.map((RejectedFinding r) => r.reason), <String>[
      'unknown rule X9',
      'file not in the diff',
      'line not in the diff',
    ]);
  });
}
