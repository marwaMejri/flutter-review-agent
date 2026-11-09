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

  test('refuses a remark whose line does not show the problem', () {
    // The false remark of pull request #1, next to a true one.
    const String diff = '''
diff --git a/lib/r.dart b/lib/r.dart
--- a/lib/r.dart
+++ b/lib/r.dart
@@ -1,1 +1,4 @@
 abstract interface class R {
+  /// The release with [id], or null when there is none.
+  Future<Release?> getRelease(int id);
+  List<String>? get headings;
''';
    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(
          <Finding>[
            Finding(
              rule: 'B5',
              file: 'lib/r.dart',
              line: 3,
              message: 'm',
              evidence: 'Future<Release?> getRelease(int id);',
            ),
            Finding(
              rule: 'B5',
              file: 'lib/r.dart',
              line: 4,
              message: 'm',
              evidence: 'List<String>? get headings;',
            ),
          ],
          files: parseDiff(diff),
          ruleIds: <String>{'B5'},
          remarkLines: <String, List<String>>{
            'B5': <String>['>?'],
          },
        );

    expect(result.accepted.single.line, 4);
    expect(result.rejected.single.finding.line, 3);
    expect(result.rejected.single.reason, 'the line has none of: >?');
  });

  test('moves a remark on a doc comment to the member below it', () {
    // gpt-oss-120b put B5 on the comment of the getter, in pull request #23.
    const String diff = '''
diff --git a/lib/v.dart b/lib/v.dart
--- a/lib/v.dart
+++ b/lib/v.dart
@@ -1,1 +1,4 @@
 class V {
+  /// The releases, or null when there is none.
+  List<Release>? get majorReleases {
+  }
''';
    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(
          <Finding>[
            Finding(
              rule: 'B5',
              file: 'lib/v.dart',
              line: 2,
              message: 'm',
              evidence: '/// The releases, or null when there is none.',
            ),
          ],
          files: parseDiff(diff),
          ruleIds: <String>{'B5'},
          remarkLines: <String, List<String>>{
            'B5': <String>['>?'],
          },
        );

    expect(result.accepted.single.line, 3);
  });

  test('refuses a remark on a const widget for P9', () {
    // flash-lite put P9 on a const Padding, in pull request #21.
    const String diff = '''
diff --git a/lib/w.dart b/lib/w.dart
--- a/lib/w.dart
+++ b/lib/w.dart
@@ -1,1 +1,3 @@
 Widget f() =>
+    ? const Padding(padding: EdgeInsets.zero)
+    : DecoratedBox(decoration: d);
''';
    final ({List<Finding> accepted, List<RejectedFinding> rejected}) result =
        validateFindings(
          <Finding>[
            Finding(
              rule: 'P9',
              file: 'lib/w.dart',
              line: 2,
              message: 'm',
              evidence: 'const Padding(',
            ),
            Finding(
              rule: 'P9',
              file: 'lib/w.dart',
              line: 3,
              message: 'm',
              evidence: 'DecoratedBox(',
            ),
          ],
          files: parseDiff(diff),
          ruleIds: <String>{'P9'},
          nonConstRules: <String>{'P9'},
        );

    expect(result.accepted.single.line, 3);
    expect(result.rejected.single.reason, 'the widget on the line is const');
  });

  test('finds the first widget of a line and whether it is const', () {
    expect(startsWithConstWidget('? const Padding('), isTrue);
    expect(startsWithConstWidget('child: const Text("x"),'), isTrue);
    expect(startsWithConstWidget('DecoratedBox('), isFalse);
    expect(
      startsWithConstWidget('Text(widget.title, style: const TextStyle())'),
      isFalse,
    );
    expect(startsWithConstWidget('final int x = 1;'), isFalse);
  });

  test('finds a return type that ends with >?', () {
    expect(
      declaresNullableReturn('List<Release>? get majorReleases {'),
      isTrue,
    );
    expect(
      declaresNullableReturn(
        'List<String>? archivedVersionsBefore(int year) {',
      ),
      isTrue,
    );
    expect(declaresNullableReturn('  Future<int>? load();'), isTrue);
    expect(
      declaresNullableReturn('List<T>? firstOf<T>(List<T> items) {'),
      isTrue,
    );
    // Pull request #24: a field, which B5 does not apply to.
    expect(declaresNullableReturn('  final List<String>? tags;'), isFalse);
    expect(declaresNullableReturn('List<String>? tags = null;'), isFalse);
    expect(declaresNullableReturn('void f(List<int>? ids) {'), isFalse);
    // Pull request #1: only the value of the Future is nullable.
    expect(
      declaresNullableReturn('Future<Release?> getRelease(int id);'),
      isFalse,
    );
  });

  test('finds the added lines that show a behavior', () {
    for (final String code in <String>[
      'if (_isCached) {',
      'onPressed: () {',
      '.where((Release release) => release.isNew)',
      'List<String>? get headings => _headings;',
      'void search(String query) {',
      'final List<Release> releases = await load();',
      '? const Padding(',
    ]) {
      expect(showsBehavior(code), isTrue, reason: code);
    }
    // Pull requests #27, #22 and #17: a constant, a new widget that only
    // shows a text, and a widget wrapped in another one.
    for (final String code in <String>[
      "const String supportEmail = 'support@example.com';",
      "export 'package:flutter/material.dart';",
      'class SectionTitle extends StatelessWidget {',
      'const SectionTitle(this.text, {super.key});',
      'Widget build(BuildContext context) {',
      'child: Text(text, style: Theme.of(context).textTheme.titleMedium),',
      ': MaterialUiCompatibilityBridge(',
      '// if (x) {',
      'String? name;',
    ]) {
      expect(showsBehavior(code), isFalse, reason: code);
    }
  });

  test('reads the ID of the convention that a remark cites', () {
    Finding remark(String convention, [String message = 'm']) => Finding(
      rule: 'CONVENTION',
      file: 'lib/a.dart',
      line: 1,
      message: message,
      convention: convention,
    );

    expect(conventionId(remark('C19')), 'C19');
    expect(conventionId(remark('[C19]')), 'C19');
    expect(
      conventionId(remark('c24: Screens navigate with context.go')),
      'C24',
    );
    expect(conventionId(remark('', 'This breaks C7.')), 'C7');
    expect(conventionId(remark('A view only talks to its view model')), isNull);
  });
}
