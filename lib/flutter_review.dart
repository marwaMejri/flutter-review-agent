/// A pull request review agent for Flutter projects.
library;

import 'src/diff.dart';
import 'src/findings.dart';
import 'src/model_client.dart';
import 'src/prompt.dart';
import 'src/rules.dart';

export 'src/config.dart';
export 'src/diff.dart';
export 'src/findings.dart';
export 'src/model_client.dart';
export 'src/prompt.dart';
export 'src/rules.dart';

/// The result of one review.
class ReviewResult {
  ReviewResult({
    required this.accepted,
    required this.rejected,
    required this.reviewedFiles,
  });

  /// Remarks that cite a known rule and a line of the diff.
  final List<Finding> accepted;

  /// Remarks the model made but the agent refused, with the reason.
  final List<RejectedFinding> rejected;

  /// Files the agent looked at.
  final List<String> reviewedFiles;
}

/// Returns true for the files the agent reviews: Dart code and the pubspec.
bool isReviewed(String path) =>
    path.endsWith('.dart') || path == 'pubspec.yaml';

/// Reviews a diff with the given rules.
Future<ReviewResult> review({
  required String diff,
  required List<Rule> rules,
  required ModelClient client,
  String? conventions,
}) async {
  final List<DiffFile> files = parseDiff(
    diff,
  ).where((DiffFile file) => isReviewed(file.path)).toList();

  if (files.isEmpty) {
    return ReviewResult(
      accepted: <Finding>[],
      rejected: <RejectedFinding>[],
      reviewedFiles: <String>[],
    );
  }

  final String answer = await client.complete(
    system: systemPrompt,
    user: buildUserPrompt(rules: rules, files: files, conventions: conventions),
  );

  final Set<String> ruleIds = <String>{
    for (final Rule rule in rules) rule.id,
    if (conventions != null && conventions.trim().isNotEmpty) conventionRuleId,
  };
  final ({List<Finding> accepted, List<RejectedFinding> rejected}) checked =
      validateFindings(parseFindings(answer), files: files, ruleIds: ruleIds);

  return ReviewResult(
    accepted: checked.accepted,
    rejected: checked.rejected,
    reviewedFiles: <String>[for (final DiffFile file in files) file.path],
  );
}
