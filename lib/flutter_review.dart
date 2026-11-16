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
export 'src/github.dart';
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
    this.note,
  });

  /// Remarks that cite a known rule and a line of the diff.
  final List<Finding> accepted;

  /// Remarks the model made but the agent refused, with the reason.
  final List<RejectedFinding> rejected;

  /// Files the agent looked at.
  final List<String> reviewedFiles;

  /// Rules sent to the model, after the triggers, then `CONVENTION` when the
  /// project has conventions. Empty when nothing applies: then the model is
  /// not called at all.
  final List<String> sentRules;

  /// The model's answer for each rule sent, with its reason.
  final List<RuleCheck> checks;

  /// What the agent changed to get a review, for example a pull request
  /// reviewed in several parts. Null when nothing changed.
  final String? note;
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
          aroundCode: <String>[
            for (final DiffFile file in files) ...file.aroundCode,
          ],
        ),
      )
      .toList();

  // The conventions are checked on every change to a reviewed file, even
  // when no rule is triggered: they have no triggers.
  final bool hasConventions =
      conventions != null && conventions.trim().isNotEmpty;
  if (files.isEmpty || (sent.isEmpty && !hasConventions)) {
    return ReviewResult(
      accepted: <Finding>[],
      rejected: <RejectedFinding>[],
      reviewedFiles: <String>[for (final DiffFile file in files) file.path],
    );
  }

  final List<DiffFile> deleted = parseDeletedFiles(
    diff,
  ).where((DiffFile file) => isReviewed(file.path)).toList();
  final Map<String, String> sources = <String, String>{
    if (readSource != null)
      for (final DiffFile file in files)
        if (readSource(file.path) case final String source) file.path: source,
  };

  final List<String> testFiles = <String>[
    for (final DiffFile file in files)
      if (isTestFile(file.path)) file.path,
  ];
  final int testExpects = addedExpects(files);
  final String? packageName = packageNameOf(readSource?.call('pubspec.yaml'));

  // A request too large for the provider is sent again with the changed
  // parts only, then cut in two until each part fits: the diff while it is
  // long, then the rules. An answer cut by the length limit of the provider
  // is asked again with half of the rules in each request, so that each
  // answer is shorter.
  final List<String> answers = <String>[];
  String? lastRefusal;
  bool changedPartsOnly = false;
  bool rulesCut = false;
  Future<void> reviewPart(
    List<Rule> partRules,
    bool withConventions,
    List<DiffFile> part, {
    required bool whole,
  }) async {
    final int units = partRules.length + (withConventions ? 1 : 0);
    Future<void> cutRules() async {
      rulesCut = true;
      final int first = units ~/ 2;
      await reviewPart(partRules.sublist(0, first), false, part, whole: whole);
      await reviewPart(
        partRules.sublist(first),
        withConventions,
        part,
        whole: whole,
      );
    }

    try {
      answers.add(
        await _ask(
          client,
          buildUserPrompt(
            rules: partRules,
            files: part,
            conventions: withConventions ? conventions : null,
            sources: whole ? sources : const <String, String>{},
            testFiles: testFiles,
            testExpects: testExpects,
            packageName: packageName,
          ),
        ),
      );
    } on AnswerCutException {
      if (units <= 1) {
        rethrow;
      }
      await cutRules();
    } on RequestTooLargeException catch (error) {
      lastRefusal = error.message;
      if (whole) {
        changedPartsOnly = true;
        await reviewPart(partRules, withConventions, part, whole: false);
      } else if (_lineCount(part) > minPartLines) {
        final (List<DiffFile>, List<DiffFile>) halves = _halves(part);
        await reviewPart(partRules, withConventions, halves.$1, whole: false);
        await reviewPart(partRules, withConventions, halves.$2, whole: false);
      } else if (units > 1) {
        await cutRules();
      } else {
        throw RequestTooLargeException(
          'The request is still too large for ${client.provider} with a part '
          'of ${_lineCount(part)} lines of diff and one rule. Last refusal: '
          '$lastRefusal',
        );
      }
    }
  }

  await reviewPart(sent, hasConventions, <DiffFile>[
    ...files,
    ...deleted,
  ], whole: sources.isNotEmpty);
  String? note;
  if (answers.length > 1 || changedPartsOnly) {
    final List<String> how = <String>[
      if (changedPartsOnly) 'with the changed parts only',
      if (rulesCut) 'with a part of the rules in each',
    ];
    note = answers.length == 1
        ? 'The pull request was too large for one request to '
              '${client.provider} with the whole files: it was reviewed with '
              'the changed parts only.'
        : 'The pull request was too large for one request to '
              '${client.provider}: it was reviewed in ${answers.length} parts'
              '${how.isEmpty ? '' : ', ${how.join(' and ')}'}. Each part was '
              'reviewed without the others.';
  }
  final List<Finding> findings = <Finding>[
    for (final String answer in answers) ...parseFindings(answer),
  ];

  final Set<String> ruleIds = <String>{
    for (final Rule rule in sent) rule.id,
    if (hasConventions) conventionRuleId,
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
        remarkLines: <String, List<String>>{
          for (final Rule rule in sent)
            if (rule.remarkLine.isNotEmpty) rule.id: rule.remarkLine,
        },
        nullableReturnRules: <String>{
          for (final Rule rule in sent)
            if (rule.remarkOnNullableReturn) rule.id,
        },
        nonConstRules: <String>{
          for (final Rule rule in sent)
            if (rule.remarkOnNonConstWidget) rule.id,
        },
      );

  // A rule with a "Remark place", such as T5, gets its remark on the test
  // line that shows the problem, when the model put it on another file.
  for (int i = 0; i < checked.accepted.length; i++) {
    final Finding finding = checked.accepted[i];
    final String? place = <String?>[
      for (final Rule rule in sent)
        if (rule.id == finding.rule) rule.remarkPlace,
    ].firstOrNull;
    if (place == null || isTestFile(finding.file)) {
      continue;
    }
    for (final DiffFile file in files.where(
      (DiffFile f) => isTestFile(f.path),
    )) {
      final int? line = (file.addedLines.toList()..sort())
          .where((int n) => (file.newLineText[n] ?? '').contains(place))
          .firstOrNull;
      if (line != null) {
        checked.accepted[i] = Finding(
          rule: finding.rule,
          file: file.path,
          line: line,
          message: finding.message,
          evidence: file.newLineText[line]!.trim(),
          convention: finding.convention,
        );
        break;
      }
    }
  }

  // A rule marked "one per pull request" keeps its first remark only.
  final Set<String> seen = <String>{};
  final List<Finding> accepted = <Finding>[];
  final List<RejectedFinding> rejected = <RejectedFinding>[...checked.rejected];
  for (final Finding finding in checked.accepted) {
    final bool once = sent.any(
      (Rule rule) => rule.id == finding.rule && rule.onePerPullRequest,
    );
    if (once && !seen.add(finding.rule)) {
      rejected.add(
        RejectedFinding(finding, 'one remark of this rule per pull request'),
      );
    } else {
      accepted.add(finding);
    }
  }

  // A rule marked "Not on a line of" gives way to the other rule on the same
  // line: an object created in build() is B2, never MEM1.
  final List<Finding> kept = <Finding>[];
  for (final Finding finding in accepted) {
    final List<String> others = <String>[
      for (final Rule rule in sent)
        if (rule.id == finding.rule) ...rule.notOnLineOf,
    ];
    final Finding? other = accepted
        .where(
          (Finding f) =>
              others.contains(f.rule) &&
              f.file == finding.file &&
              f.line == finding.line,
        )
        .firstOrNull;
    if (other != null) {
      rejected.add(
        RejectedFinding(finding, '${other.rule} is on the same line'),
      );
    } else {
      kept.add(finding);
    }
  }

  // A rule marked "Only when an added line under lib/ shows a behavior",
  // such as T3: with no such line, the pull request has nothing to test.
  final bool behavior = files.any(
    (DiffFile file) =>
        file.path.startsWith('lib/') &&
        !isTestFile(file.path) &&
        file.addedCode.any(showsBehavior),
  );
  // A CONVENTION remark must cite the ID of a convention of CONVENTIONS.md:
  // a model can invent one. The remark then shows the text of the file.
  final Map<String, String> conventionTexts = hasConventions
      ? numberedConventions(conventions)
      : const <String, String>{};
  final List<Finding> checkedKept = <Finding>[];
  for (final Finding finding in kept) {
    final bool needsBehavior = sent.any(
      (Rule rule) => rule.id == finding.rule && rule.needsBehaviorLine,
    );
    if (needsBehavior && !behavior) {
      rejected.add(
        RejectedFinding(finding, 'no added line under lib/ shows a behavior'),
      );
    } else if (_columnWithNoScrollView(finding, sent, files, sources)) {
      rejected.add(
        RejectedFinding(finding, 'no SingleChildScrollView in the file'),
      );
    } else if (finding.rule == conventionRuleId) {
      final String? text = conventionTexts[conventionId(finding)];
      if (text == null) {
        rejected.add(
          RejectedFinding(finding, 'convention not found in the conventions'),
        );
      } else {
        checkedKept.add(
          Finding(
            rule: finding.rule,
            file: finding.file,
            line: finding.line,
            message: finding.message,
            evidence: finding.evidence,
            convention: text,
          ),
        );
      }
    } else {
      checkedKept.add(finding);
    }
  }

  return ReviewResult(
    accepted: checkedKept,
    rejected: rejected,
    reviewedFiles: <String>[for (final DiffFile file in files) file.path],
    sentRules: <String>[
      for (final Rule rule in sent) rule.id,
      if (hasConventions) conventionRuleId,
    ],
    checks: _mergeChecks(<List<RuleCheck>>[
      for (final String answer in answers) parseChecks(answer),
    ]),
    note: note,
  );
}

/// Whether [finding] is a remark of a rule like P5 on a `Column` or a `Row`,
/// in a file that has no `SingleChildScrollView`: such a `Column` is not a
/// scrolling list, so the rule does not apply to it.
bool _columnWithNoScrollView(
  Finding finding,
  List<Rule> rules,
  List<DiffFile> files,
  Map<String, String> sources,
) {
  if (!rules.any(
    (Rule rule) => rule.id == finding.rule && rule.remarkInScrollView,
  )) {
    return false;
  }
  final DiffFile? file = files
      .where((DiffFile f) => f.path == finding.file)
      .firstOrNull;
  if (file == null) {
    return false;
  }
  final String code = file.newLineText[finding.line] ?? '';
  if (!RegExp(r'\b(Column|Row)\s*\(').hasMatch(code) ||
      RegExp(
        r'\b(ListView|GridView|SliverChildListDelegate)\b',
      ).hasMatch(code)) {
    return false;
  }
  final String fileCode =
      sources[file.path] ?? file.newLineText.values.join('\n');
  return !fileCode.contains('SingleChildScrollView');
}

/// Sends one request, and asks once more when the answer is not the expected
/// JSON: the same question usually gets a correct answer the second time. A
/// cut answer would be cut again: asking again would only use the quota.
Future<String> _ask(ModelClient client, String user) async {
  for (int attempt = 1; ; attempt++) {
    final String answer = await client.complete(
      system: systemPrompt,
      user: user,
    );
    try {
      parseFindings(answer);
      return answer;
    } on InvalidAnswerException catch (error) {
      if (client.finishReason == 'length') {
        throw _cutAnswer(error);
      }
      if (attempt == 2) {
        rethrow;
      }
    }
  }
}

/// Smallest part of a diff sent alone, in lines. Under it, cutting would only
/// repeat the rules and the conventions in more requests.
const int minPartLines = 50;

int _lineCount(List<DiffFile> files) =>
    files.fold(0, (int count, DiffFile file) => count + file.annotated.length);

/// Cuts [files] in two parts with the same number of diff lines. A file in
/// the middle is cut too.
(List<DiffFile>, List<DiffFile>) _halves(List<DiffFile> files) {
  int left = _lineCount(files) ~/ 2;
  final List<DiffFile> first = <DiffFile>[];
  final List<DiffFile> second = <DiffFile>[];
  for (final DiffFile file in files) {
    final int length = file.annotated.length;
    if (left >= length) {
      first.add(file);
      left -= length;
    } else if (left > 0) {
      first.add(file.part(0, left));
      second.add(file.part(left, length));
      left = 0;
    } else {
      second.add(file);
    }
  }
  return (first, second);
}

/// The checks of several parts. For each rule: the checks that say it
/// applies, or the first one when no part does.
List<RuleCheck> _mergeChecks(List<List<RuleCheck>> parts) {
  if (parts.length == 1) {
    return parts.single;
  }
  final Map<String, List<RuleCheck>> byRule = <String, List<RuleCheck>>{};
  for (final List<RuleCheck> part in parts) {
    for (final RuleCheck check in part) {
      byRule.putIfAbsent(check.rule, () => <RuleCheck>[]).add(check);
    }
  }
  return <RuleCheck>[
    for (final List<RuleCheck> checks in byRule.values)
      if (checks.any((RuleCheck check) => check.applies))
        ...checks.where((RuleCheck check) => check.applies)
      else
        checks.first,
  ];
}

AnswerCutException _cutAnswer(InvalidAnswerException error) =>
    AnswerCutException(
      '${error.message} The answer was cut: the model reached its length '
      'limit (finish_reason: length).',
    );
