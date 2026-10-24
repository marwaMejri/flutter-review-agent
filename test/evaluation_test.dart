import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  final EvalCase flagCase = EvalCase(
    name: 'P1-flag',
    expected: <ExpectedProblem>[
      ExpectedProblem(rule: 'P1', file: 'lib/a.dart', lines: <int>{10, 11}),
    ],
  );

  Finding remark(String rule, int line) =>
      Finding(rule: rule, file: 'lib/a.dart', line: line, message: 'm');

  test('counts a remark with the right rule on an accepted line', () {
    final CaseScore score = scoreCase(flagCase, <Finding>[remark('P1', 11)]);

    expect(score.found, hasLength(1));
    expect(score.missed, isEmpty);
    expect(score.invented, isEmpty);
  });

  test('counts a missed problem', () {
    final CaseScore score = scoreCase(flagCase, <Finding>[]);

    expect(score.missed, hasLength(1));
  });

  test('counts the wrong rule or the wrong line as invented', () {
    final CaseScore score = scoreCase(flagCase, <Finding>[
      remark('P2', 11),
      remark('P1', 30),
    ]);

    expect(score.found, isEmpty);
    expect(score.invented, hasLength(2));
  });

  test('counts a second remark on the same problem as a duplicate', () {
    final CaseScore score = scoreCase(flagCase, <Finding>[
      remark('P1', 10),
      remark('P1', 11),
    ]);

    expect(score.found, hasLength(1));
    expect(score.duplicates, hasLength(1));
    expect(score.invented, isEmpty);
  });

  test('counts every remark on an -ok case as invented', () {
    final CaseScore score = scoreCase(
      EvalCase(name: 'P1-ok', expected: <ExpectedProblem>[]),
      <Finding>[remark('P1', 10)],
    );

    expect(score.invented, hasLength(1));
  });

  test('counts an allowed remark neither as found nor as invented', () {
    final CaseScore score = scoreCase(
      EvalCase(
        name: 'P5-ok',
        expected: <ExpectedProblem>[],
        allowed: <ExpectedProblem>[
          ExpectedProblem(rule: 'T5', file: 'lib/a.dart', lines: <int>{10}),
        ],
      ),
      <Finding>[remark('T5', 10)],
    );

    expect(score.allowed, hasLength(1));
    expect(score.invented, isEmpty);
  });
}
