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
}
