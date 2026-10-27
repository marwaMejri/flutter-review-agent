/// A pull request review agent for Flutter projects.
library;

import 'src/diff.dart';
import 'src/findings.dart';
import 'src/model_client.dart';
import 'src/prompt.dart';
import 'src/rules.dart';

export 'src/config.dart';
export 'src/diff.dart';
export 'src/evaluation.dart';
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
    this.sentRules = const <String>[],
    this.checks = const <RuleCheck>[],
  });

  /// Remarks that cite a known rule and a line of the diff.
  final List<Finding> accepted;

  /// Remarks the model made but the agent refused, with the reason.
  final List<RejectedFinding> rejected;

  /// Files the agent looked at.
  final List<String> reviewedFiles;

  /// Rules sent to the model, after the triggers. Empty when no rule applies:
  /// then the model is not called at all.
  final List<String> sentRules;

  /// The model's answer for each rule sent, with its reason.
  final List<RuleCheck> checks;
}

/// Suffixes of generated Dart files: nobody writes them by hand, so nobody
/// should review them.
const List<String> generatedSuffixes = <String>[
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.config.dart',
  '.mocks.dart',
];

/// Returns true for the files the agent reviews: Dart code written by hand,
/// and the pubspec.
bool isReviewed(String path) =>
    path == 'pubspec.yaml' ||
    (path.endsWith('.dart') &&
        !generatedSuffixes.any((String suffix) => path.endsWith(suffix)));

/// Reviews a diff with the given rules.
Future<ReviewResult> review({
  required String diff,
  required List<Rule> rules,
  required ModelClient client,
  String? conventions,
  String? Function(String path)? readSource,
}) async {
  final List<DiffFile> files = parseDiff(
    diff,
  ).where((DiffFile file) => isReviewed(file.path)).toList();

  final List<Rule> sent = rules
      .where(
        (Rule rule) => rule.isTriggeredBy(
          paths: <String>[for (final DiffFile file in files) file.path],
          addedCode: <String>[
            for (final DiffFile file in files) ...file.addedCode,
          ],
        ),
      )
      .toList();

  if (files.isEmpty || sent.isEmpty) {
    return ReviewResult(
      accepted: <Finding>[],
      rejected: <RejectedFinding>[],
      reviewedFiles: <String>[for (final DiffFile file in files) file.path],
    );
  }

  final String user = buildUserPrompt(
    rules: sent,
    files: files,
    conventions: conventions,
    sources: <String, String>{
      if (readSource != null)
        for (final DiffFile file in files)
          if (readSource(file.path) case final String source) file.path: source,
    },
  );

  // A model sometimes answers text that is not the expected JSON. The same
  // question usually gets a correct answer the second time. A cut answer
  // would be cut again: asking again would only use the quota.
  String answer = await client.complete(system: systemPrompt, user: user);
  List<Finding> findings;
  try {
    findings = parseFindings(answer);
  } on InvalidAnswerException catch (error) {
    if (client.finishReason == 'length') {
      throw _cutAnswer(error);
    }
    answer = await client.complete(system: systemPrompt, user: user);
    try {
      findings = parseFindings(answer);
    } on InvalidAnswerException catch (error) {
      if (client.finishReason == 'length') {
        throw _cutAnswer(error);
      }
      rethrow;
    }
  }

  final Set<String> ruleIds = <String>{
    for (final Rule rule in sent) rule.id,
    if (conventions != null && conventions.trim().isNotEmpty) conventionRuleId,
  };
  final ({List<Finding> accepted, List<RejectedFinding> rejected}) checked =
      validateFindings(
        findings,
        files: files,
        ruleIds: ruleIds,
        fileScopes: <String, List<String>>{
          for (final Rule rule in sent)
            if (rule.triggers.isNotEmpty &&
                rule.triggers.every((String t) => t.startsWith('file:')))
              rule.id: <String>[
                for (final String t in rule.triggers) t.substring(5),
              ],
        },
      );

  return ReviewResult(
    accepted: checked.accepted,
    rejected: checked.rejected,
    reviewedFiles: <String>[for (final DiffFile file in files) file.path],
    sentRules: <String>[for (final Rule rule in sent) rule.id],
    checks: parseChecks(answer),
  );
}

InvalidAnswerException _cutAnswer(InvalidAnswerException error) =>
    InvalidAnswerException(
      '${error.message} The answer was cut: the model reached its length '
      'limit (finish_reason: length).',
    );
