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

  test('reads the evidence when there is one', () {
    final List<Finding> findings = parseFindings(
      '{"findings": [{"rule": "P1", "file": "lib/a.dart", "line": 11, '
      '"evidence": "final int z;", "message": "m"}]}',
    );

    expect(findings.single.evidence, 'final int z;');
  });

  test('keeps only known rules on lines of the diff', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(
        rule: 'P1',
        file: 'lib/a.dart',
        line: 11,
        message: 'ok',
        evidence: 'final int z',
      ),
      Finding(rule: 'X9', file: 'lib/a.dart', line: 11, message: 'invented'),
      Finding(rule: 'P1', file: 'lib/b.dart', line: 11, message: 'other file'),
      Finding(rule: 'P1', file: 'lib/a.dart', line: 99, message: 'other line'),
      Finding(rule: 'P1', file: 'lib/a.dart', line: 10, message: 'unchanged'),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted.map((Finding f) => f.message), <String>['ok']);
    expect(result.rejected.map((RejectedFinding r) => r.reason), <String>[
      'unknown rule X9',
      'file not in the diff',
      'line not in the diff',
      'line not changed by the pull request',
    ]);
  });

  test('refuses a remark whose evidence is missing or not in the code', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(rule: 'P1', file: 'lib/a.dart', line: 11, message: 'none'),
      Finding(
        rule: 'P1',
        file: 'lib/a.dart',
        line: 11,
        message: 'invented code',
        evidence: 'final int q;',
      ),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted, isEmpty);
    expect(result.rejected.map((RejectedFinding r) => r.reason), <String>[
      'no evidence',
      'evidence not found near the line',
    ]);
  });

  test('moves a remark to the nearby added line that holds the evidence', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(
        rule: 'P1',
        file: 'lib/a.dart',
        line: 10,
        message: 'one line too high',
        evidence: '  final   int w;',
      ),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted.single.line, 12);
  });

  test('finds evidence copied on one line from several lines, or with a +', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(
        rule: 'P1',
        file: 'lib/a.dart',
        line: 11,
        message: 'two lines',
        evidence: 'final int z; final int w;',
      ),
      Finding(
        rule: 'P1',
        file: 'lib/a.dart',
        line: 12,
        message: 'diff marker',
        evidence: '+  final int w;',
      ),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted.map((Finding f) => f.line), <int>[11, 12]);
  });

  test('reads the check of each rule, and skips malformed ones', () {
    final List<RuleCheck> checks = parseChecks(
      '{"checks": [{"rule": "P1", "reason": "sorts in build", "applies": true},'
      ' {"rule": "P9"}], "findings": []}',
    );

    expect(checks.single.rule, 'P1');
    expect(checks.single.applies, isTrue);
    expect(parseChecks('{"findings": []}'), isEmpty);
  });

  test('ignores the trailing commas that the formatter adds', () {
    final List<DiffFile> files = parseDiff('''
diff --git a/lib/c.dart b/lib/c.dart
new file mode 100644
--- /dev/null
+++ b/lib/c.dart
@@ -0,0 +1,3 @@
+    onPressed: () => show(
+      context,
+    ),
''');
    final Finding finding = Finding(
      rule: 'P1',
      file: 'lib/c.dart',
      line: 1,
      message: 'm',
      evidence: 'onPressed: () => show(context)',
    );

    expect(
      validateFindings(
        <Finding>[finding],
        files: files,
        ruleIds: <String>{'P1'},
      ).accepted,
      hasLength(1),
    );
  });

  test('fixes a wrong folder when one file of the diff has the same name', () {
    final List<DiffFile> files = parseDiff(sampleDiff);
    final List<Finding> findings = <Finding>[
      Finding(
        rule: 'P1',
        file: 'lib/widgets/a.dart',
        line: 11,
        message: 'wrong folder',
        evidence: 'final int z;',
      ),
      Finding(
        rule: 'P1',
        file: 'lib/widgets/a.dart',
        line: 11,
        message: 'wrong folder, invented code',
        evidence: 'final int q;',
      ),
    ];

    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(findings, files: files, ruleIds: <String>{'P1'});

    expect(result.accepted.single.file, 'lib/a.dart');
    expect(result.rejected.single.reason, 'file not in the diff');
  });

  test(
    'refuses a remark outside the files of a rule that has a file scope',
    () {
      final List<DiffFile> files = parseDiff(sampleDiff);
      final Finding finding = Finding(
        rule: 'T3',
        file: 'lib/a.dart',
        line: 11,
        message: 'm',
        evidence: 'final int z;',
      );

      expect(
        validateFindings(
          <Finding>[finding],
          files: files,
          ruleIds: <String>{'T3'},
          fileScopes: <String, List<String>>{
            'T3': <String>['test/'],
          },
        ).rejected.single.reason,
        'file outside the scope of T3',
      );
      expect(
        validateFindings(
          <Finding>[finding],
          files: files,
          ruleIds: <String>{'T3'},
          fileScopes: <String, List<String>>{
            'T3': <String>['lib/'],
          },
        ).accepted,
        hasLength(1),
      );
    },
  );

  test('reads the JSON even when the model writes text around it', () {
    final List<Finding> findings = parseFindings(
      'Here is my review:\n{"findings": [{"rule": "P1", "file": "lib/a.dart", '
      '"line": 11, "message": "m"}]}\nI hope this helps.',
    );

    expect(findings.single.rule, 'P1');
  });
}
