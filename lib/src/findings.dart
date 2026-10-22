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
  });

  final String rule;
  final String file;
  final int line;
  final String message;

  Map<String, Object> toJson() => <String, Object>{
    'rule': rule,
    'file': file,
    'line': line,
    'message': message,
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

/// Reads the answer of the model: `{"findings": [...]}`.
///
/// Some models wrap JSON in a Markdown code block, so the fences are removed
/// first.
List<Finding> parseFindings(String answer) {
  String text = answer.trim();
  if (text.startsWith('```')) {
    text = text.substring(text.indexOf('\n') + 1);
    final int end = text.lastIndexOf('```');
    if (end >= 0) {
      text = text.substring(0, end);
    }
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw InvalidAnswerException('The answer is not JSON: ${error.message}');
  }
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
    findings.add(Finding(rule: rule, file: file, line: line, message: message));
  }
  return findings;
}

/// Keeps only the findings that cite a known rule and a line of the diff.
///
/// This is the safety net against invented rules and invented lines: a remark
/// that fails these checks is never posted.
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
    } else if (!file.commentableLines.contains(finding.line)) {
      rejected.add(RejectedFinding(finding, 'line not in the diff'));
    } else {
      accepted.add(finding);
    }
  }
  return (accepted: accepted, rejected: rejected);
}
