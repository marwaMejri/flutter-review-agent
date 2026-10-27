// Runs the agent on every case of eval/cases/ and compares its remarks with
// eval/expected.json.
//
// The agent must work with any model, so the evaluation measures each model
// on its own: one model per pass, with no fallback to another model. A pass
// that mixed models could not tell which model missed a problem.
//
//   dart run tool/eval.dart              every model of the provider, once
//   dart run tool/eval.dart --model X    only model X
//   dart run tool/eval.dart --runs 3     every case three times (stability)
//   dart run tool/eval.dart --case P2-ok only some cases
//   dart run tool/eval.dart --case 'P*'  the cases whose name starts with P
//   dart run tool/eval.dart --pause 10   wait 10 s between reviews (default 0)
//
// When the provider is busy, the evaluation waits as long as the provider
// asks, so a pass is slow on a free plan but never mixes models.
//
// Settings are read like the agent: FLUTTER_REVIEW_API_KEY,
// FLUTTER_REVIEW_PROVIDER, and so on.
//
// Each case is eval/cases/<name>.diff. The full new version of its changed
// files is in eval/files/<name>/.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_review/flutter_review.dart';

Future<void> main(List<String> arguments) async {
  final ArgResults options =
      (ArgParser()
            ..addOption('runs', defaultsTo: '1')
            ..addOption('pause', defaultsTo: '0')
            ..addMultiOption('case')
            ..addOption('provider')
            ..addOption('base-url')
            ..addOption('model'))
          .parse(arguments);

  final ReviewConfig config;
  try {
    config = resolveConfig(<String, String>{
      ...Platform.environment,
      if (options.option('provider') case final String value)
        providerVariable: value,
      if (options.option('base-url') case final String value)
        baseUrlVariable: value,
      if (options.option('model') case final String value) modelVariable: value,
    });
  } on ConfigException catch (error) {
    stderr.writeln(error);
    exitCode = 78;
    return;
  }

  final int runs = int.parse(options.option('runs')!);
  final Duration pause = Duration(seconds: int.parse(options.option('pause')!));
  final List<String> only = options.multiOption('case');
  final Map<String, Object?> expected =
      jsonDecode(File('eval/expected.json').readAsStringSync())
          as Map<String, Object?>;
  final List<EvalCase> cases =
      <EvalCase>[
            for (final Object? item in expected['cases']! as List<Object?>)
              EvalCase.fromJson(item! as Map<String, Object?>),
          ]
          .where((EvalCase c) => only.isEmpty || only.any(c.name.matchesCase))
          .toList();

  // The example app is a material_ui project, so the migration pack is on.
  final List<Rule> rules = readRules(
    rulesFolder: 'rules',
    packs: <String>['material_ui_migration'],
  );

  final String stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final File output = File('eval/results/eval-$stamp.json');
  output.parent.createSync(recursive: true);

  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  final Map<String, _Totals> totalsByModel = <String, _Totals>{};

  for (final String model in config.models) {
    // One model, no fallback and no discovery: this pass measures this model
    // only. It waits for a busy provider instead of giving up.
    final ModelClient client = ModelClient(
      provider: config.provider,
      baseUrl: config.baseUrl,
      models: <String>[model],
      apiKey: config.apiKey,
      maxAttempts: 20,
      maxRetryWait: const Duration(minutes: 2),
      totalTimeout: const Duration(minutes: 15),
    );
    int failedInARow = 0;
    final _Totals totals = totalsByModel[model] = _Totals();

    stdout
      ..writeln()
      ..writeln('Model: $model')
      ..writeln(
        '${'case'.padRight(22)} run  found  missed  invented  dup  refused  '
        'seconds  model s  tokens',
      );

    caseLoop:
    for (final EvalCase evalCase in cases) {
      final String diff = File(
        'eval/cases/${evalCase.name}.diff',
      ).readAsStringSync();
      String? readSource(String path) {
        final File file = File('eval/files/${evalCase.name}/$path');
        return file.existsSync() ? file.readAsStringSync() : null;
      }

      for (int run = 1; run <= runs; run++) {
        if (pause > Duration.zero) {
          await Future<void>.delayed(pause);
        }
        final String label =
            '${evalCase.name.padRight(22)} ${'$run'.padRight(4)}';
        final Stopwatch watch = Stopwatch()..start();
        final ReviewResult result;
        try {
          result = await review(
            diff: diff,
            rules: rules,
            client: client,
            readSource: readSource,
          );
        } on ModelException catch (error) {
          stdout.writeln('$label error: $error');
          totals.errors++;
          results.add(<String, Object?>{
            'model': model,
            'case': evalCase.name,
            'run': run,
            'error': error.message,
          });
          // The model is not available now (quota, limit for the day): the
          // other cases would fail too.
          if (++failedInARow >= 2) {
            stdout.writeln(
              'Stopping $model: two reviews in a row could not get an answer.',
            );
            break caseLoop;
          }
          continue;
        } on InvalidAnswerException catch (error) {
          stdout.writeln(
            '$label error: $error '
            '(${client.promptTokens ?? '?'} + ${client.answerTokens ?? '?'} '
            'tokens)',
          );
          totals.errors++;
          results.add(<String, Object?>{
            'model': model,
            'case': evalCase.name,
            'run': run,
            'error': error.message,
            'promptTokens': client.promptTokens,
            'answerTokens': client.answerTokens,
            'finishReason': client.finishReason,
          });
          continue;
        }
        watch.stop();
        failedInARow = 0;

        final CaseScore score = scoreCase(evalCase, result.accepted);
        final double seconds = watch.elapsedMilliseconds / 1000;
        totals.add(evalCase, score, result, seconds);
        if (client.answerTime case final Duration time) {
          totals.answerSeconds.add(time.inMilliseconds / 1000);
        }
        if (client.promptTokens case final int prompt) {
          totals.tokens.add(prompt + (client.answerTokens ?? 0));
        }
        stdout.writeln(
          '$label '
          '${'${score.found.length}/${evalCase.expected.length}'.padRight(6)} '
          '${'${score.missed.length}'.padRight(7)} '
          '${'${score.invented.length}'.padRight(9)} '
          '${'${score.duplicates.length}'.padRight(4)} '
          '${'${result.rejected.length}'.padRight(8)} '
          '${seconds.toStringAsFixed(1).padRight(8)} '
          '${_seconds(client.answerTime).padRight(8)} '
          '${client.promptTokens ?? '?'} + ${client.answerTokens ?? '?'}',
        );
        for (final ExpectedProblem problem in score.missed) {
          final RuleCheck? check = result.checks
              .where((RuleCheck c) => c.rule == problem.rule)
              .firstOrNull;
          stdout.writeln(
            '             missed: [${problem.rule}] '
            '${check == null ? 'no check from the model' : 'model said: ${check.reason}'}',
          );
        }
        for (final Finding finding in score.allowed) {
          stdout.writeln(
            '             allowed: [${finding.rule}] '
            '${finding.file}:${finding.line}  ${finding.message}',
          );
        }
        for (final Finding finding in score.invented) {
          stdout.writeln(
            '             invented: [${finding.rule}] '
            '${finding.file}:${finding.line}  ${finding.message}',
          );
        }
        for (final RejectedFinding rejected in result.rejected) {
          stdout.writeln(
            '             refused: [${rejected.finding.rule}] '
            '${rejected.finding.file}:${rejected.finding.line}  '
            '${rejected.reason}',
          );
        }

        results.add(<String, Object?>{
          'model': model,
          'case': evalCase.name,
          'run': run,
          'seconds': seconds,
          'answerSeconds': client.answerTime == null
              ? null
              : client.answerTime!.inMilliseconds / 1000,
          'promptTokens': client.promptTokens,
          'answerTokens': client.answerTokens,
          'expected': evalCase.expected.length,
          'found': score.found.length,
          'missed': <Map<String, Object>>[
            for (final ExpectedProblem p in score.missed)
              <String, Object>{'rule': p.rule, 'file': p.file},
          ],
          'invented': <Map<String, Object>>[
            for (final Finding f in score.invented) f.toJson(),
          ],
          'duplicates': score.duplicates.length,
          'allowed': <Map<String, Object>>[
            for (final Finding f in score.allowed) f.toJson(),
          ],
          'rulesSent': result.sentRules,
          'checks': <Map<String, Object>>[
            for (final RuleCheck c in result.checks) c.toJson(),
          ],
          'accepted': <Map<String, Object>>[
            for (final Finding f in result.accepted) f.toJson(),
          ],
          'refused': <Map<String, Object>>[
            for (final RejectedFinding r in result.rejected)
              <String, Object>{...r.finding.toJson(), 'reason': r.reason},
          ],
        });
      }
    }
    client.close();
    totals.write(model);

    // Saved after each model, so a long run that stops keeps its results.
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'provider': config.provider,
        'models': config.models,
        'runs': runs,
        'results': results,
      }),
    );
  }

  if (totalsByModel.length > 1) {
    stdout
      ..writeln()
      ..writeln('Summary');
    totalsByModel.forEach(
      (String model, _Totals totals) => stdout.writeln('  $model: $totals'),
    );
  }
  stdout.writeln('Saved: ${output.path}');
}

/// The totals of one model.
class _Totals {
  int expected = 0;
  int found = 0;
  int falseOnClean = 0;
  int otherOnFlag = 0;
  int refused = 0;
  int errors = 0;
  final List<double> seconds = <double>[];
  final List<int> tokens = <int>[];

  /// Time of the model's answer only, without waits for a busy provider.
  final List<double> answerSeconds = <double>[];

  void add(
    EvalCase evalCase,
    CaseScore score,
    ReviewResult result,
    double time,
  ) {
    expected += evalCase.expected.length;
    found += score.found.length;
    // A case with no expected problem is a clean case: every remark on it is
    // a false remark.
    if (evalCase.expected.isEmpty) {
      falseOnClean += score.invented.length;
    } else {
      otherOnFlag += score.invented.length;
    }
    refused += result.rejected.length;
    seconds.add(time);
  }

  /// The middle review time: half of the reviews were faster. Waits for a
  /// busy provider are included.
  double get medianSeconds {
    if (seconds.isEmpty) {
      return 0;
    }
    final List<double> sorted = List<double>.of(seconds)..sort();
    return sorted[sorted.length ~/ 2];
  }

  void write(String model) => stdout
    ..writeln()
    ..writeln('Totals for $model')
    ..writeln('  Expected problems found: $found / $expected')
    ..writeln('  False remarks on clean cases: $falseOnClean')
    ..writeln('  Other remarks on cases with a problem: $otherOnFlag')
    ..writeln('  Remarks refused by the agent: $refused')
    ..writeln('  Reviews that failed: $errors')
    ..writeln(
      '  Median time of a review: ${medianSeconds.toStringAsFixed(1)} s '
      '(waits for a busy provider included)',
    )
    ..writeln(
      '  Median time of the model answer: '
      '${_median(answerSeconds).toStringAsFixed(1)} s',
    )
    ..writeln('  Median tokens of a review: $medianTokens');

  /// The middle number of tokens of a review, question and answer together.
  int get medianTokens {
    if (tokens.isEmpty) {
      return 0;
    }
    final List<int> sorted = List<int>.of(tokens)..sort();
    return sorted[sorted.length ~/ 2];
  }

  @override
  String toString() =>
      'found $found/$expected, false remarks $falseOnClean, '
      'failed $errors, median ${medianSeconds.toStringAsFixed(1)} s, '
      'median $medianTokens tokens';
}

extension on String {
  /// Whether this case name matches [pattern]: the same name, or the same
  /// start when the pattern ends with `*`.
  bool matchesCase(String pattern) => pattern.endsWith('*')
      ? startsWith(pattern.substring(0, pattern.length - 1))
      : this == pattern;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  return sorted[sorted.length ~/ 2];
}

String _seconds(Duration? time) =>
    time == null ? '?' : (time.inMilliseconds / 1000).toStringAsFixed(1);
