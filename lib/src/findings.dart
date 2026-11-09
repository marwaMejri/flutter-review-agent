import 'dart:convert';

import 'diff.dart';

/// The rule ID the model uses for a remark based on the project's
/// `CONVENTIONS.md`.
const String conventionRuleId = 'CONVENTION';

/// One remark of the review.
class Finding {
  Finding({
    required this.rule,
    required this.file,
    required this.line,
    required this.message,
    this.evidence = '',
    this.convention = '',
  });

  final String rule;
  final String file;
  final int line;
  final String message;

  /// The code that shows the problem, copied by the model from the cited line.
  final String evidence;

  /// For a `CONVENTION` remark, the broken convention: its ID (`C3`) in the
  /// answer of the model, then its text, once the agent has checked it.
  /// Empty for a rule.
  final String convention;

  /// The same remark on another line.
  Finding atLine(int newLine) => Finding(
    rule: rule,
    file: file,
    line: newLine,
    message: message,
    evidence: evidence,
    convention: convention,
  );

  Map<String, Object> toJson() => <String, Object>{
    'rule': rule,
    'file': file,
    'line': line,
    'message': message,
    'evidence': evidence,
    if (convention.isNotEmpty) 'convention': convention,
  };
}

/// The model's answer for one rule it was given: whether the rule applies to
/// the added code, and why.
///
/// Asking for one check per rule makes every model go through every rule,
/// instead of stopping at the first problem it sees.
class RuleCheck {
  RuleCheck({required this.rule, required this.applies, required this.reason});

  final String rule;
  final bool applies;
  final String reason;

  Map<String, Object> toJson() => <String, Object>{
    'rule': rule,
    'applies': applies,
    'reason': reason,
  };
}

/// A remark that the agent refused, and why.
class RejectedFinding {
  RejectedFinding(this.finding, this.reason);

  final Finding finding;
  final String reason;
}

/// Thrown when the answer of the model is not the expected JSON.
class InvalidAnswerException implements Exception {
  InvalidAnswerException(this.message);

  final String message;

  @override
  String toString() => 'InvalidAnswerException: $message';
}

/// Reads the JSON of the answer.
///
/// Some models wrap JSON in a Markdown code block, so the fences are removed
/// first.
Object? _decodeAnswer(String answer) {
  String text = answer.trim();
  if (text.startsWith('```')) {
    text = text.substring(text.indexOf('\n') + 1);
    final int end = text.lastIndexOf('```');
    if (end >= 0) {
      text = text.substring(0, end);
    }
  }
  try {
    return jsonDecode(text);
  } on FormatException catch (error) {
    // Some models write a sentence before or after the JSON ("Here is my
    // review: {...}"). The JSON object is then the text from the first `{`
    // to the last `}`.
    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(text.substring(start, end + 1));
      } on FormatException {
        // Not JSON either: the error below explains the first failure.
      }
    }
    throw InvalidAnswerException('The answer is not JSON: ${error.message}');
  }
}

/// Reads the checks of the answer: `{"checks": [...]}`. Checks that are
/// missing or malformed are left out: they only explain the findings.
List<RuleCheck> parseChecks(String answer) {
  final Object? decoded = _decodeAnswer(answer);
  if (decoded is! Map<String, Object?> || decoded['checks'] is! List) {
    return <RuleCheck>[];
  }
  return <RuleCheck>[
    for (final Object? item in decoded['checks']! as List<Object?>)
      if (item is Map<String, Object?> &&
          item['rule'] is String &&
          item['applies'] is bool)
        RuleCheck(
          rule: item['rule']! as String,
          applies: item['applies']! as bool,
          reason: item['reason'] is String ? item['reason']! as String : '',
        ),
  ];
}

/// Reads the findings of the answer: `{"findings": [...]}`.
List<Finding> parseFindings(String answer) {
  final Object? decoded = _decodeAnswer(answer);
  if (decoded is! Map<String, Object?> || decoded['findings'] is! List) {
    throw InvalidAnswerException('The answer has no "findings" list.');
  }

  final List<Finding> findings = <Finding>[];
  for (final Object? item in decoded['findings']! as List<Object?>) {
    if (item is! Map<String, Object?>) {
      throw InvalidAnswerException('A finding is not an object: $item');
    }
    final Object? rule = item['rule'];
    final Object? file = item['file'];
    final Object? line = item['line'];
    final Object? message = item['message'];
    if (rule is! String ||
        file is! String ||
        line is! int ||
        message is! String) {
      throw InvalidAnswerException('A finding has a missing field: $item');
    }
    final Object? evidence = item['evidence'];
    final Object? convention = item['convention'];
    findings.add(
      Finding(
        rule: rule,
        file: file,
        line: line,
        message: message,
        evidence: evidence is String ? evidence : '',
        convention: convention is String ? convention : '',
      ),
    );
  }
  return findings;
}

/// How many lines around the cited line the agent looks for the evidence.
/// Models sometimes cite the line before or after the code they quote.
const int evidenceWindow = 3;

/// Keeps only the findings that cite a known rule, and whose evidence is
/// found on a line that the pull request added or changed.
///
/// This is the safety net against invented rules, invented code and remarks
/// about code the pull request did not touch: a remark that fails these checks
/// is never posted. When the evidence is on a line near the cited one, the
/// remark is moved to that line.
///
/// [remarkLines] gives, for a rule, the texts that the line of its remark
/// must contain. For the rules in [nullableReturnRules], such as B5, the line
/// must declare a return type that ends with `>?`. For the rules in
/// [nonConstRules], such as P9, the first widget of the line must not be
/// `const`.
///
/// A remark on a `///` comment is moved to the member that the comment
/// documents.
({List<Finding> accepted, List<RejectedFinding> rejected}) validateFindings(
  List<Finding> findings, {
  required List<DiffFile> files,
  required Set<String> ruleIds,
  Map<String, List<String>> fileScopes = const <String, List<String>>{},
  Map<String, List<String>> remarkLines = const <String, List<String>>{},
  Set<String> nonConstRules = const <String>{},
  Set<String> nullableReturnRules = const <String>{},
}) {
  final Map<String, DiffFile> filesByPath = <String, DiffFile>{
    for (final DiffFile file in files) file.path: file,
  };
  final List<Finding> accepted = <Finding>[];
  final List<RejectedFinding> rejected = <RejectedFinding>[];

  for (final Finding original in findings) {
    Finding finding = original;
    DiffFile? file = filesByPath[finding.file];
    if (file == null) {
      // Models sometimes get the folder wrong in a pull request with many
      // files (`lib/widgets/a.dart` for `lib/features/a.dart`). When one file
      // of the diff has the same name and holds the evidence, the remark is
      // moved to it.
      final String name = finding.file.split('/').last;
      final List<DiffFile> sameName = <DiffFile>[
        for (final DiffFile candidate in files)
          if (candidate.path.split('/').last == name) candidate,
      ];
      if (sameName.length == 1 &&
          _lineWithEvidence(sameName.single, finding) != null) {
        file = sameName.single;
        finding = Finding(
          rule: finding.rule,
          file: file.path,
          line: finding.line,
          message: finding.message,
          evidence: finding.evidence,
          convention: finding.convention,
        );
      }
    }
    if (!ruleIds.contains(finding.rule)) {
      rejected.add(RejectedFinding(finding, 'unknown rule ${finding.rule}'));
    } else if (file == null) {
      rejected.add(RejectedFinding(finding, 'file not in the diff'));
    } else if (fileScopes[finding.rule] case final List<String> scope
        when !scope.any(file.path.startsWith)) {
      // A rule that only applies to some files, such as T3 to `lib/`, cannot
      // be reported anywhere else.
      rejected.add(
        RejectedFinding(finding, 'file outside the scope of ${finding.rule}'),
      );
    } else if (_lineWithEvidence(file, finding) case final int found) {
      final int line = _memberLine(file, found);
      final Finding placed = line == finding.line
          ? finding
          : finding.atLine(line);
      final List<String>? texts = remarkLines[finding.rule];
      final String code = file.newLineText[line] ?? '';
      if (texts != null && !texts.any(code.contains)) {
        // The model skipped a step of the rule: the line does not show the
        // problem, for example `Future<Release?>` for B5.
        rejected.add(
          RejectedFinding(placed, 'the line has none of: ${texts.join(', ')}'),
        );
      } else if (nullableReturnRules.contains(finding.rule) &&
          !declaresNullableReturn(code)) {
        // A field or a parameter is not a return type, and
        // `Future<Release?>` does not end with `>?`.
        rejected.add(
          RejectedFinding(
            placed,
            'the line declares no return type that ends with >?',
          ),
        );
      } else if (nonConstRules.contains(finding.rule) &&
          startsWithConstWidget(code)) {
        // A `const` widget is built once: the rule does not apply to it.
        rejected.add(
          RejectedFinding(placed, 'the widget on the line is const'),
        );
      } else {
        accepted.add(placed);
      }
    } else if (!file.commentableLines.contains(finding.line)) {
      rejected.add(RejectedFinding(finding, 'line not in the diff'));
    } else if (!file.addedLines.contains(finding.line)) {
      // The pull request did not change this line: the remark is about code
      // that was already there, which is not what the review is for.
      rejected.add(
        RejectedFinding(finding, 'line not changed by the pull request'),
      );
    } else if (_cleanEvidence(finding.evidence).length < 3) {
      rejected.add(RejectedFinding(finding, 'no evidence'));
    } else {
      rejected.add(
        RejectedFinding(finding, 'evidence not found near the line'),
      );
    }
  }
  return (accepted: accepted, rejected: rejected);
}

/// The line of the member that a `///` comment documents, when [line] is
/// such a comment and the pull request added the member. Otherwise [line].
int _memberLine(DiffFile file, int line) {
  if (!(file.newLineText[line] ?? '').trimLeft().startsWith('///')) {
    return line;
  }
  for (int next = line + 1; next <= line + 10; next++) {
    final String? code = file.newLineText[next];
    if (code == null) {
      return line;
    }
    final String trimmed = code.trimLeft();
    if (trimmed.startsWith('///') || trimmed.startsWith('@')) {
      continue;
    }
    return file.addedLines.contains(next) ? next : line;
  }
  return line;
}

/// Whether [code] declares a method, a function or a getter whose return
/// type ends with `>?`, as in `List<Release>? get majorReleases {`. A field
/// (`final List<String>? tags;`) or a parameter does not.
bool declaresNullableReturn(String code) => RegExp(
  r'>\?\s+(get\s+[A-Za-z_$][\w$]*|[A-Za-z_$][\w$]*\s*(<[^()]*>)?\s*\()',
).hasMatch(code);

/// Whether the first widget created on [code] is marked `const`, as in
/// `? const Padding(`.
bool startsWithConstWidget(String code) {
  final Match? widget = RegExp(r'[A-Z]\w*(\.\w+)?\(').firstMatch(code);
  if (widget == null) {
    return false;
  }
  return RegExp(r'\bconst\s+$').hasMatch(code.substring(0, widget.start));
}

/// The ID of the convention that a `CONVENTION` remark cites, such as `C19`:
/// the first one in its "convention" field, as `C19`, `[C19]` or
/// `C19: A view only talks…`, else the first one in its message. Null when
/// there is none.
String? conventionId(Finding finding) {
  final RegExp id = RegExp(r'\bC\s?(\d+)\b', caseSensitive: false);
  final Match? match =
      id.firstMatch(finding.convention) ?? id.firstMatch(finding.message);
  return match == null ? null : 'C${match.group(1)}';
}

/// Whether an added line of code [code] shows a behavior that a test can
/// check: a condition, a callback, a loop, an operation on a collection, a
/// state change, an `await`, or a new method or getter with a body (not
/// `build()`). A constant, an import, a widget that only shows a text, or a
/// widget wrapped in another one shows none.
bool showsBehavior(String code) {
  final String line = code.trim();
  if (line.startsWith('//') || line.startsWith('*') || line.startsWith('/*')) {
    return false;
  }
  return <RegExp>[
    RegExp(r'\bif\s*\('),
    RegExp(r'\bswitch\s*\('),
    RegExp(r'\bcase\b'),
    RegExp(r'(^|\s)\?\s'),
    RegExp(r'\?\?'),
    RegExp(r'\bon[A-Z]\w*\s*:'),
    RegExp(r'\b(for|while)\s*\('),
    RegExp(
      r'\.(where|map|sort|fold|reduce|any|every|firstWhere|lastWhere|expand|'
      r'forEach|whereType)\s*[(<]',
    ),
    RegExp(r'\b(setState|notifyListeners|addListener|removeListener)\s*\('),
    RegExp(r'\.listen\s*\('),
    RegExp(r'\bawait\b'),
    RegExp(r'\bget\s+\w+\s*(\{|=>)'),
    RegExp(
      r'^(?:[\w<>?,\[\]\s]+\s)?(?!build\b)[a-z_]\w*\s*(?:<[^>]*>)?\s*'
      r'\([^;]*\)\s*(?:async\s*)?(?:\{|=>)',
    ),
  ].any((RegExp pattern) => pattern.hasMatch(line));
}

/// How many lines the evidence can span: models often copy a whole
/// statement written on several lines.
const int evidenceSpan = 6;

/// The added line, at most [evidenceWindow] lines from the cited one, where
/// the evidence starts. The nearest line wins.
///
/// Spaces and line breaks are ignored, so the evidence can be copied on one
/// line or on several.
int? _lineWithEvidence(DiffFile file, Finding finding) {
  final String wanted = _withoutTrailingCommas(
    _cleanEvidence(finding.evidence),
  );
  if (wanted.length < 3) {
    return null;
  }
  for (int distance = 0; distance <= evidenceWindow; distance++) {
    for (final int start in <int>{
      finding.line - distance,
      finding.line + distance,
    }) {
      final String? first = file.newLineText[start];
      if (first == null || !file.addedLines.contains(start)) {
        continue;
      }
      final StringBuffer joined = StringBuffer();
      for (int line = start; line < start + evidenceSpan; line++) {
        final String? text = file.newLineText[line];
        if (text == null) {
          break;
        }
        joined.write(_compact(text));
        final int index = _withoutTrailingCommas(
          joined.toString(),
        ).indexOf(wanted);
        if (index >= 0) {
          // The evidence must start on this line, not on a later one.
          if (index < _compact(first).length) {
            return start;
          }
          break;
        }
      }
    }
  }
  return null;
}

/// The evidence without spaces, and without the `+` or the line number that
/// some models copy from the diff.
String _cleanEvidence(String evidence) => <String>[
  for (final String line in evidence.split('\n'))
    _compact(line.replaceFirst(RegExp(r'^\s*(\d+\s*\|)?\s*\+?'), '')),
].join();

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// The code without the trailing commas that `dart format` adds before `)`,
/// `]` and `}`: models often leave them out when they copy code. Applied to
/// code without spaces, after the lines are joined.
String _withoutTrailingCommas(String code) =>
    code.replaceAll(RegExp(r',(?=[)\]}])'), '');
