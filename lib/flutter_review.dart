/// A pull request review agent for Flutter projects.
library;

import 'src/builders.dart';
import 'src/diff.dart';
import 'src/findings.dart';
import 'src/model_client.dart';
import 'src/prompt.dart';
import 'src/rules.dart';

export 'src/builders.dart';
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
///
/// [readSource] reads a file of the project by its path, such as
/// `lib/main.dart`. [projectFiles] lists the Dart files of the project under
/// `lib/`: P1 looks for the `build()` methods that call a method.
Future<ReviewResult> review({
  required String diff,
  required List<Rule> rules,
  required ModelClient client,
  String? conventions,
  String? Function(String path)? readSource,
  List<String> Function()? projectFiles,
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
  final List<String> testExpects = addedExpects(files);
  final String? packageName = packageNameOf(readSource?.call('pubspec.yaml'));
  // Read in the whole files, also when the model gets the changed parts only.
  final Map<String, Map<int, String>> routerLines = routerLinesOf(
    files,
    sources,
  );
  final List<String> widgetLines = untestedWidgetLines(
    files,
    sources,
    deletedFiles: deleted,
  );

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
            routerLines: routerLines,
            widgetLines: widgetLines,
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
  // line that shows the problem, wherever the model put it.
  for (int i = 0; i < checked.accepted.length; i++) {
    final Finding finding = checked.accepted[i];
    final Rule? rule = sent
        .where((Rule r) => r.id == finding.rule && r.remarkPlace != null)
        .firstOrNull;
    final (DiffFile, int)? place = rule == null
        ? null
        : _remarkPlace(files, rule.remarkPlace!, rule.remarkPlaceAfter);
    if (place == null) {
      continue;
    }
    final (DiffFile file, int line) = place;
    checked.accepted[i] = Finding(
      rule: finding.rule,
      file: file.path,
      line: line,
      message: finding.message,
      evidence: file.newLineText[line]!.trim(),
      convention: finding.convention,
    );
  }

  // A rule with "Remark place: the list widget built with the loop ...", such
  // as P5, gets its remark on that widget when the model put it on a widget
  // around it, such as the `Column` that holds the list.
  for (int i = 0; i < checked.accepted.length; i++) {
    final Finding finding = checked.accepted[i];
    final String? source = sources[finding.file];
    final DiffFile? file = files
        .where((DiffFile f) => f.path == finding.file)
        .firstOrNull;
    if (source == null ||
        file == null ||
        !sent.any((Rule r) => r.id == finding.rule && r.remarkOnListWithLoop)) {
      continue;
    }
    final int? line = listPlace(source, finding.line);
    if (line != null && file.commentableLines.contains(line)) {
      checked.accepted[i] = Finding(
        rule: finding.rule,
        file: finding.file,
        line: line,
        message: finding.message,
        evidence: file.newLineText[line]!.trim(),
        convention: finding.convention,
      );
    }
  }

  // A rule with "Remark place: the outermost widget of the builder ...",
  // such as P9, gets its remark on the widget that reads neither the
  // animation nor the value, and is refused when the builder has none.
  final List<RejectedFinding> rejected = <RejectedFinding>[...checked.rejected];
  final List<Finding> placed = <Finding>[];
  for (final Finding finding in checked.accepted) {
    final String? source = sources[finding.file];
    final DiffFile? file = files
        .where((DiffFile f) => f.path == finding.file)
        .firstOrNull;
    final BuilderPlace? builder =
        source == null ||
            file == null ||
            !sent.any(
              (Rule r) => r.id == finding.rule && r.remarkOnBuilderChild,
            )
        ? null
        : builderPlaces(source)
              .where(
                (BuilderPlace b) =>
                    b.first <= finding.line && finding.line <= b.last,
              )
              .firstOrNull;
    if (builder == null) {
      placed.add(finding);
    } else if (builder.line == null) {
      rejected.add(
        RejectedFinding(
          finding,
          'every widget of the builder reads the animation or the value, or '
          'is const',
        ),
      );
    } else if (file!.commentableLines.contains(builder.line)) {
      placed.add(
        Finding(
          rule: finding.rule,
          file: finding.file,
          line: builder.line!,
          message: finding.message,
          evidence: file.newLineText[builder.line]!.trim(),
          convention: finding.convention,
        ),
      );
    } else {
      placed.add(finding);
    }
  }

  // A rule marked "one per pull request" keeps its first remark only, and a
  // rule marked "one per field" its first remark for each field.
  final Set<String> seen = <String>{};
  final List<Finding> accepted = <Finding>[];
  for (final Finding finding in placed) {
    final bool once = sent.any(
      (Rule rule) => rule.id == finding.rule && rule.onePerPullRequest,
    );
    final bool perField = sent.any(
      (Rule rule) => rule.id == finding.rule && rule.onePerField,
    );
    final String? field = perField
        ? storedField(
            files
                    .where((DiffFile f) => f.path == finding.file)
                    .firstOrNull
                    ?.newLineText[finding.line] ??
                '',
          )
        : null;
    if (once && !seen.add(finding.rule)) {
      rejected.add(
        RejectedFinding(finding, 'one remark of this rule per pull request'),
      );
    } else if (field != null && !seen.add('${finding.rule} $field')) {
      rejected.add(
        RejectedFinding(
          finding,
          'one remark of this rule for the field $field',
        ),
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
        (file.addedCode.any(showsBehavior) || changesComputation(file)),
  );
  // A CONVENTION remark must cite the ID of a convention of CONVENTIONS.md:
  // a model can invent one. The remark then shows the text of the file.
  final Map<String, String> conventionTexts = hasConventions
      ? numberedConventions(conventions)
      : const <String, String>{};
  // The code of every build() of the project, read once, when a remark
  // needs it.
  String? allBuildCode;
  String buildCode() => allBuildCode ??= _buildCode(<String, String>{
    if (projectFiles != null && readSource != null)
      for (final String path in projectFiles())
        if (readSource(path) case final String code) path: code,
    ...sources,
  });
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
    } else if (_outsideBuild(finding, sent, sources, buildCode)) {
      rejected.add(
        RejectedFinding(
          finding,
          'not in build(), nor in a method that a build() calls',
        ),
      );
    } else if (_disposedName(finding, sent, sources) case final String name) {
      rejected.add(RejectedFinding(finding, 'the file disposes $name'));
    } else if (finding.rule == conventionRuleId) {
      final String? text = conventionTexts[conventionId(finding)];
      final String code =
          files
              .where((DiffFile f) => f.path == finding.file)
              .firstOrNull
              ?.newLineText[finding.line] ??
          '';
      if (text == null) {
        rejected.add(
          RejectedFinding(finding, 'convention not found in the conventions'),
        );
      } else if (_packageUri.hasMatch(text) && !_importLine.hasMatch(code)) {
        // A convention that names a package, such as "never from
        // `package:flutter/material.dart`", is broken by an import or an
        // export: a remark on another line was about a package that the
        // file may not even import.
        rejected.add(
          RejectedFinding(
            finding,
            'a convention about a package, not on an import or export line',
          ),
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

  // A CONVENTION remark on the line of a kept rule remark is refused: the
  // rule remark says it already, with its source.
  final List<Finding> shown = <Finding>[];
  for (final Finding finding in checkedKept) {
    final Finding? ruleRemark = finding.rule != conventionRuleId
        ? null
        : checkedKept
              .where(
                (Finding f) =>
                    f.rule != conventionRuleId &&
                    f.file == finding.file &&
                    f.line == finding.line,
              )
              .firstOrNull;
    if (ruleRemark != null) {
      rejected.add(
        RejectedFinding(
          finding,
          'the line already has a remark of ${ruleRemark.rule}',
        ),
      );
    } else {
      shown.add(finding);
    }
  }

  // A rule marked "Confirm when a test of the pull request has an added
  // check", such as T3: the model then judges whether these checks test the
  // new code, and a model was seen to get it wrong once out of three runs.
  // The rule is asked again, alone, and its remark is kept only when the
  // second answer flags it too. When the agent already gives the lines that
  // no test renders, there is nothing to judge. A failed second request
  // keeps the remark.
  final List<Finding> confirmed = <Finding>[];
  final Map<String, String?> secondAnswers = <String, String?>{};
  for (final Finding finding in shown) {
    final Rule? rule = sent
        .where((Rule r) => r.id == finding.rule && r.confirmWhenChecks)
        .firstOrNull;
    if (rule == null || testExpects.isEmpty || widgetLines.isNotEmpty) {
      confirmed.add(finding);
      continue;
    }
    if (!secondAnswers.containsKey(rule.id)) {
      try {
        secondAnswers[rule.id] = await _ask(
          client,
          buildUserPrompt(
            rules: <Rule>[rule],
            files: files,
            sources: changedPartsOnly ? const <String, String>{} : sources,
            testFiles: testFiles,
            testExpects: testExpects,
            packageName: packageName,
            routerLines: routerLines,
            widgetLines: widgetLines,
          ),
        );
      } on Exception {
        secondAnswers[rule.id] = null;
      }
    }
    final String? again = secondAnswers[rule.id];
    if (again == null ||
        parseFindings(again).any((Finding f) => f.rule == rule.id)) {
      confirmed.add(finding);
    } else {
      final String? reason = parseChecks(
        again,
      ).where((RuleCheck check) => check.rule == rule.id).firstOrNull?.reason;
      rejected.add(
        RejectedFinding(
          finding,
          'not flagged again by a second answer'
          '${reason == null ? '' : ': $reason'}',
        ),
      );
    }
  }

  return ReviewResult(
    accepted: confirmed,
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

/// The field that [code] declares with the type `BuildContext`, or that it
/// assigns `context` to: `_saved` in `BuildContext? _saved;` and in
/// `_saved = context;`, `pageContext` in `..pageContext = context`. Null for
/// any other line.
String? storedField(String code) =>
    (RegExp(r'\bBuildContext\??\s+(\w+)').firstMatch(code) ??
            RegExp(r'([A-Za-z_$][\w$]*)\s*=\s*context\b').firstMatch(code))
        ?.group(1);

/// The added test line that contains [text], in the test files of [files]:
/// the first one whose line before contains [after], else the first one.
/// Null when no added test line contains [text].
(DiffFile, int)? _remarkPlace(
  List<DiffFile> files,
  String text,
  String? after,
) {
  final List<(DiffFile, int)> lines = <(DiffFile, int)>[
    for (final DiffFile file in files.where((DiffFile f) => isTestFile(f.path)))
      for (final int line in file.addedLines.toList()..sort())
        if ((file.newLineText[line] ?? '').contains(text)) (file, line),
  ];
  if (after != null) {
    for (final (DiffFile file, int line) in lines) {
      // The line before, with blank lines skipped.
      int before = line - 1;
      while ((file.newLineText[before] ?? 'x').trim().isEmpty) {
        before--;
      }
      if ((file.newLineText[before] ?? '').contains(after)) {
        return (file, line);
      }
    }
  }
  return lines.firstOrNull;
}

final RegExp _packageUri = RegExp(r'`package:[^`]+`');
final RegExp _importLine = RegExp(r'^\s*(import|export)\s');

/// For a rule marked "Remark line: an object that the file does not
/// dispose", such as MEM1, the object of the line that the file disposes.
String? _disposedName(
  Finding finding,
  List<Rule> rules,
  Map<String, String> sources,
) {
  final String? source = sources[finding.file];
  if (source == null ||
      !rules.any(
        (Rule rule) => rule.id == finding.rule && rule.remarkOnUndisposed,
      )) {
    return null;
  }
  return disposedOnLine(source, finding.line);
}

/// The object on [line] of [source] that the file disposes, for MEM1: a name
/// of the line with `name.dispose()`, `name.cancel()` or `name.close()` in
/// the file. Null when there is none, or when the line also names an object
/// that the file creates (`name = SomeClass(...)`) and never disposes.
String? disposedOnLine(String source, int line) {
  final String text = source.replaceAll('\r\n', '\n');
  final List<String> lines = text.split('\n');
  if (line < 1 || line > lines.length) {
    return null;
  }
  final Set<String> names = <String>{
    for (final Match name in RegExp(
      r'(?<![\w.$])([a-z_$][\w$]*)\b(?!\s*\()',
    ).allMatches(lines[line - 1]))
      name.group(1)!,
  };
  bool disposed(String name) => RegExp(
    '\\b${RegExp.escape(name)}\\??\\.(dispose|cancel|close)\\(',
  ).hasMatch(text);
  bool created(String name) => RegExp(
    '\\b${RegExp.escape(name)}\\s*=\\s*(?:const\\s+)?[A-Z][\\w\$]*'
    '(?:\\.[\\w\$]+)?\\s*(?:<[^;]*?>)?\\(',
  ).hasMatch(text);
  if (names.any((String name) => created(name) && !disposed(name))) {
    return null;
  }
  return names.where(disposed).firstOrNull;
}

/// Whether a remark of a rule that must be in `build()`, such as P1, is in
/// the body of another method that no `build()` names, in [buildCode]. A
/// line in no method body (a getter, a method written with `=>`) or in a
/// file with no source is kept: the agent cannot tell.
bool _outsideBuild(
  Finding finding,
  List<Rule> rules,
  Map<String, String> sources,
  String Function() buildCode,
) {
  final String? source = sources[finding.file];
  if (source == null ||
      !rules.any(
        (Rule rule) => rule.id == finding.rule && rule.remarkInBuild,
      )) {
    return false;
  }
  final String? method = methodAt(openCalls(source), finding.line);
  if (method == null || method == 'build') {
    return false;
  }
  final String name = method.split('.').last;
  return !RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(buildCode());
}

/// The lines of every `build()` method of [sources], joined.
String _buildCode(Map<String, String> sources) => <String>[
  for (final String code in sources.values)
    for (final MapEntry<int, List<String>> line in openCalls(code).entries)
      if (line.value.contains('{build'))
        code.replaceAll('\r\n', '\n').split('\n')[line.key - 1],
].join('\n');

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
