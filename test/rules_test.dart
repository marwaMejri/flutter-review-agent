import 'dart:io';

import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  test('reads every rule of the v1 files', () {
    final List<String> ids = <String>[
      for (final String name in <String>[
        'rules/performance.md',
        'rules/memory.md',
        'rules/dart.md',
        'rules/tests.md',
        'packs/material_ui_migration.md',
      ])
        ...parseRules(File(name).readAsStringSync()).map((Rule r) => r.id),
    ];

    expect(ids, <String>[
      'P1', 'P2', 'P3', 'P5', 'P9', //
      'B2', 'MEM1', 'MEM2', 'MEM3', //
      'B4', 'B5', //
      'T3', 'T4', 'T5', //
      'M1', 'M2', 'M3', 'M4',
    ]);
  });

  test('keeps the whole section of a rule', () {
    final Rule rule = parseRules(
      File('rules/performance.md').readAsStringSync(),
    ).first;

    expect(rule.title, 'Expensive work in `build()`');
    expect(rule.text, contains('**Do not flag when:**'));
    expect(rule.text, isNot(contains('## P2.')));
  });

  test('reads the triggers and leaves them out of the text', () {
    final Rule rule = parseRules(
      File('rules/performance.md').readAsStringSync(),
    ).firstWhere((Rule r) => r.id == 'P5');

    expect(rule.triggers, <String>[
      'ListView(',
      'GridView(',
      'Column(',
      'SliverChildListDelegate(',
      'SingleChildScrollView(',
    ]);
    expect(rule.text, isNot(contains('Triggers')));
  });

  test('applies a rule only when a trigger matches', () {
    final Rule rule = Rule(
      id: 'X1',
      title: 't',
      text: 't',
      triggers: <String>['AnimatedBuilder', 'file:test/'],
    );

    expect(
      rule.isTriggeredBy(
        paths: <String>['lib/a.dart'],
        addedCode: <String>['return AnimatedBuilder('],
      ),
      isTrue,
    );
    expect(
      rule.isTriggeredBy(
        paths: <String>['test/a_test.dart'],
        addedCode: <String>['expect(x, 1);'],
      ),
      isTrue,
    );
    expect(
      rule.isTriggeredBy(
        paths: <String>['lib/a.dart'],
        addedCode: <String>['Text(title)'],
      ),
      isFalse,
    );
    expect(
      Rule(
        id: 'X2',
        title: 't',
        text: 't',
      ).isTriggeredBy(paths: <String>[], addedCode: <String>[]),
      isTrue,
    );
  });

  test('finds a trigger around: on the unchanged lines of a hunk', () {
    // Pull request #14 adds `name:` inside a `GoRoute(` that it does not
    // change.
    final DiffFile file = parseDiff('''
diff --git a/lib/app/router.dart b/lib/app/router.dart
--- a/lib/app/router.dart
+++ b/lib/app/router.dart
@@ -40,2 +40,3 @@
           GoRoute(
             path: 'settings',
+            name: 'settings',
''').single;
    final Rule around = Rule(
      id: 'X1',
      title: 't',
      text: 't',
      triggers: <String>['around:GoRoute'],
    );
    final Rule added = Rule(
      id: 'X2',
      title: 't',
      text: 't',
      triggers: <String>['GoRoute'],
    );

    for (final (Rule rule, bool expected) in <(Rule, bool)>[
      (around, true),
      (added, false),
    ]) {
      expect(
        rule.isTriggeredBy(
          paths: <String>[file.path],
          addedCode: file.addedCode,
          aroundCode: file.aroundCode,
        ),
        expected,
        reason: rule.id,
      );
    }
  });

  test('every step of Decide says what to do when the answer is no', () {
    final RegExp step = RegExp(r'\n  \d+\. ');
    final RegExp whenNo = RegExp(
      r'If\s+(no|not|there\s+is\s+none|there\s+is\s+no)\b',
    );
    for (final String name in <String>[
      'rules/performance.md',
      'rules/memory.md',
      'rules/dart.md',
      'rules/tests.md',
      'packs/material_ui_migration.md',
    ]) {
      for (final Rule rule in parseRules(File(name).readAsStringSync())) {
        final int start = rule.text.indexOf('- **Decide:**');
        final int end = rule.text.indexOf('\n- **Bad', start);
        expect(start, isNot(-1), reason: rule.id);
        final List<String> steps = rule.text
            .substring(start, end)
            .split(step)
            .skip(1)
            .toList();
        expect(steps, isNotEmpty, reason: rule.id);
        for (int i = 0; i < steps.length; i++) {
          expect(steps[i], matches(whenNo), reason: '${rule.id} step ${i + 1}');
        }
      }
    }
  });

  test('reads the level and the source of a rule', () {
    final Rule rule = parseRules(
      File('rules/memory.md').readAsStringSync(),
    ).firstWhere((Rule r) => r.id == 'B2');

    expect(rule.level, 'issue');
    expect(
      rule.source,
      startsWith('[StatefulWidget, Performance considerations]'),
    );
    expect(rule.source, contains('[TextEditingController]'));
  });

  test('reads which rules keep one remark per pull request', () {
    final List<Rule> rules = parseRules(
      File('rules/tests.md').readAsStringSync(),
    );

    final Rule t3 = rules.firstWhere((Rule r) => r.id == 'T3');
    final Rule t4 = rules.firstWhere((Rule r) => r.id == 'T4');

    expect(t3.onePerPullRequest, isTrue);
    expect(t4.onePerPullRequest, isFalse);
    expect(t3.needsBehaviorLine, isTrue);
    expect(t4.needsBehaviorLine, isFalse);
  });

  test('reads the texts that the line of a remark must contain', () {
    final List<Rule> rules = parseRules(
      File('rules/dart.md').readAsStringSync(),
    );

    final Rule b5 = rules.firstWhere((Rule r) => r.id == 'B5');

    expect(b5.remarkOnNullableReturn, isTrue);
    expect(b5.remarkLine, isEmpty);
    expect(rules.firstWhere((Rule r) => r.id == 'B4').remarkLine, isEmpty);
    expect(
      Rule(
        id: 'X1',
        title: 't',
        text: '## X1. t\n\n- **Remark line:** contains `>?`',
      ).remarkLine,
      <String>['>?'],
    );
  });

  test('reads which rules need a widget that is not const', () {
    final Rule p9 = parseRules(
      File('rules/performance.md').readAsStringSync(),
    ).firstWhere((Rule r) => r.id == 'P9');
    final Rule b5 = parseRules(
      File('rules/dart.md').readAsStringSync(),
    ).firstWhere((Rule r) => r.id == 'B5');

    expect(p9.remarkOnNonConstWidget, isTrue);
    expect(p9.remarkLine, isEmpty);
    expect(b5.remarkOnNonConstWidget, isFalse);
  });

  test('reads the rules that win on the same line', () {
    final List<Rule> rules = parseRules(
      File('rules/memory.md').readAsStringSync(),
    );

    expect(rules.firstWhere((Rule r) => r.id == 'MEM1').notOnLineOf, <String>[
      'B2',
    ]);
    expect(rules.firstWhere((Rule r) => r.id == 'B2').notOnLineOf, isEmpty);
  });
}
