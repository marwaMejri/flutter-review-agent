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
  });

  final String rule;
  final String file;
  final int line;
  final String message;

  /// The code that shows the problem, copied by the model from the cited line.
  final String evidence;

  /// The same remark on another line.
  Finding atLine(int newLine) => Finding(
    rule: rule,
    file: file,
    line: newLine,
    message: message,
    evidence: evidence,
  );

  Map<String, Object> toJson() => <String, Object>{
    'rule': rule,
    'file': file,
    'line': line,
    'message': message,
    'evidence': evidence,
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
    findings.add(
      Finding(
        rule: rule,
        file: file,
        line: line,
        message: message,
        evidence: evidence is String ? evidence : '',
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
({List<Finding> accepted, List<RejectedFinding> rejected}) validateFindings(
  List<Finding> findings, {
  required List<DiffFile> files,
  required Set<String> ruleIds,
}) {
  final Map<String, DiffFile> filesByPath = <String, DiffFile>{
    for (final DiffFile file in files) file.path: file,
  };
  final List<Finding> accepted = <Finding>[];
  final List<RejectedFinding> rejected = <RejectedFinding>[];

  for (final Finding finding in findings) {
    final DiffFile? file = filesByPath[finding.file];
    if (!ruleIds.contains(finding.rule)) {
      rejected.add(RejectedFinding(finding, 'unknown rule ${finding.rule}'));
    } else if (file == null) {
      rejected.add(RejectedFinding(finding, 'file not in the diff'));
    } else if (_lineWithEvidence(file, finding) case final int line) {
      accepted.add(line == finding.line ? finding : finding.atLine(line));
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

/// How many lines the evidence can span: models often copy a whole
/// statement written on several lines.
const int evidenceSpan = 6;

/// The added line, at most [evidenceWindow] lines from the cited one, where
/// the evidence starts. The nearest line wins.
///
/// Spaces and line breaks are ignored, so the evidence can be copied on one
/// line or on several.
int? _lineWithEvidence(DiffFile file, Finding finding) {
  final String wanted = _cleanEvidence(finding.evidence);
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
        final int index = joined.toString().indexOf(wanted);
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
