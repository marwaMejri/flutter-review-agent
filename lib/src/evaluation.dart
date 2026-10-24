import 'findings.dart';

/// A problem that a test case contains on purpose.
class ExpectedProblem {
  ExpectedProblem({
    required this.rule,
    required this.file,
    required this.lines,
  });

  factory ExpectedProblem.fromJson(Map<String, Object?> json) =>
      ExpectedProblem(
        rule: json['rule']! as String,
        file: json['file']! as String,
        lines: <int>{
          for (final Object? line in json['lines']! as List<Object?>)
            line! as int,
        },
      );

  final String rule;
  final String file;

  /// Any of these lines is a correct place for the remark.
  final Set<int> lines;

  bool matches(Finding finding) =>
      finding.rule == rule &&
      finding.file == file &&
      lines.contains(finding.line);
}

/// One test case: a diff, and the problems it contains on purpose.
///
/// A case whose name ends with `-ok` contains no problem: every remark on it
/// is a false remark.
class EvalCase {
  EvalCase({
    required this.name,
    required this.expected,
    this.allowed = const <ExpectedProblem>[],
  });

  factory EvalCase.fromJson(Map<String, Object?> json) => EvalCase(
    name: json['name']! as String,
    expected: <ExpectedProblem>[
      for (final Object? item in json['expected']! as List<Object?>)
        ExpectedProblem.fromJson(item! as Map<String, Object?>),
    ],
    allowed: <ExpectedProblem>[
      for (final Object? item
          in (json['allowed'] as List<Object?>?) ?? const <Object?>[])
        ExpectedProblem.fromJson(item! as Map<String, Object?>),
    ],
  );

  final String name;
  final List<ExpectedProblem> expected;

  /// Remarks that are acceptable but not required: a careful reviewer could
  /// make them. They count neither as found nor as invented.
  final List<ExpectedProblem> allowed;
}

/// How the remarks of the agent compare with the expected problems.
class CaseScore {
  CaseScore({
    required this.found,
    required this.missed,
    required this.duplicates,
    required this.invented,
    this.allowed = const <Finding>[],
  });

  /// Expected problems with at least one correct remark.
  final List<ExpectedProblem> found;

  /// Expected problems with no correct remark.
  final List<ExpectedProblem> missed;

  /// Correct remarks about a problem that already had one.
  final List<Finding> duplicates;

  /// Remarks that match no expected problem.
  final List<Finding> invented;

  /// Remarks that match an allowed problem.
  final List<Finding> allowed;
}

/// Compares the remarks of the agent with the expected problems of a case.
CaseScore scoreCase(EvalCase evalCase, List<Finding> findings) {
  final List<ExpectedProblem> found = <ExpectedProblem>[];
  final List<Finding> duplicates = <Finding>[];
  final List<Finding> invented = <Finding>[];
  final List<Finding> allowed = <Finding>[];

  for (final Finding finding in findings) {
    final ExpectedProblem? problem = evalCase.expected
        .where((ExpectedProblem p) => p.matches(finding))
        .firstOrNull;
    if (problem == null &&
        evalCase.allowed.any((ExpectedProblem p) => p.matches(finding))) {
      allowed.add(finding);
    } else if (problem == null) {
      invented.add(finding);
    } else if (found.contains(problem)) {
      duplicates.add(finding);
    } else {
      found.add(problem);
    }
  }

  return CaseScore(
    found: found,
    missed: <ExpectedProblem>[
      for (final ExpectedProblem p in evalCase.expected)
        if (!found.contains(p)) p,
    ],
    duplicates: duplicates,
    invented: invented,
    allowed: allowed,
  );
}
