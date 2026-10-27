import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_review/flutter_review.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption('diff', help: 'Path of the diff to review, or - for stdin.')
    ..addOption(
      'rules',
      defaultsTo: 'rules',
      help: 'Folder of the rules that are always on.',
    )
    ..addOption('packs', defaultsTo: 'packs', help: 'Folder of the packs.')
    ..addMultiOption('pack', help: 'Optional pack to turn on, by file name.')
    ..addOption('conventions', help: 'Path of the project CONVENTIONS.md.')
    ..addOption(
      'project',
      help:
          'Folder of the reviewed project. The full changed files are read '
          'from it and sent with the diff.',
    )
    ..addOption(
      'provider',
      help:
          'Provider with a preset (${providerPresets.keys.join(', ')}). '
          'Overrides $providerVariable.',
    )
    ..addOption(
      'base-url',
      help: 'Address of an OpenAI-compatible API. Overrides $baseUrlVariable.',
    )
    ..addOption(
      'model',
      help:
          'Model name, or several separated by commas, in order of '
          'preference. Overrides $modelVariable.',
    )
    ..addOption('json', help: 'Also write the result as JSON to this path.')
    ..addFlag(
      'list-models',
      negatable: false,
      help: 'Print the models of the provider, then stop.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  if (options.flag('help') ||
      (options.option('diff') == null && !options.flag('list-models'))) {
    stdout
      ..writeln('Usage: dart run flutter_review --diff <file>')
      ..writeln()
      ..writeln('Settings are read from environment variables:')
      ..writeln('  $apiKeyVariable   the API key (required)')
      ..writeln('  $providerVariable  ${providerPresets.keys.join(', ')}')
      ..writeln('  $baseUrlVariable and $modelVariable  for another provider')
      ..writeln(
        '  $timeoutVariable  longest time for one review, in seconds '
        '(default ${defaultReviewTimeout.inSeconds})',
      )
      ..writeln(parser.usage);
    return;
  }

  // With --json, a review that cannot run still writes why, so the GitHub
  // Action can say it on the pull request.
  final String? jsonPath = options.option('json');

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
    await _writeError(jsonPath, error.message);
    exitCode = 78;
    return;
  }

  if (options.flag('list-models')) {
    final ModelClient lister = ModelClient(
      provider: config.provider,
      baseUrl: config.baseUrl,
      models: config.models,
      apiKey: config.apiKey,
    );
    final List<String> available;
    try {
      available = await lister.fetchModels();
    } on ModelException catch (error) {
      stderr.writeln(error);
      exitCode = 1;
      return;
    } finally {
      lister.close();
    }
    if (available.isEmpty) {
      stderr.writeln('The list of models of ${config.provider} is empty.');
      exitCode = 1;
      return;
    }
    (available..sort()).forEach(stdout.writeln);
    return;
  }

  final String diffPath = options.option('diff')!;
  final String diff = diffPath == '-'
      ? await stdin.transform(utf8.decoder).join()
      : await File(diffPath).readAsString();

  final List<Rule> rules = readRules(
    rulesFolder: options.option('rules')!,
    packsFolder: options.option('packs')!,
    packs: options.multiOption('pack'),
  );

  final String? conventionsPath = options.option('conventions');
  final String? conventions =
      conventionsPath != null && File(conventionsPath).existsSync()
      ? await File(conventionsPath).readAsString()
      : null;

  final ModelClient client = ModelClient(
    provider: config.provider,
    baseUrl: config.baseUrl,
    models: config.models,
    apiKey: config.apiKey,
    modelPattern: config.modelPattern,
    totalTimeout: config.timeout,
  );
  final Stopwatch watch = Stopwatch()..start();
  final ReviewResult result;
  try {
    result = await review(
      diff: diff,
      rules: rules,
      client: client,
      conventions: conventions,
      readSource: switch (options.option('project')) {
        final String project => (String path) {
          final File file = File('$project/$path');
          return file.existsSync() ? file.readAsStringSync() : null;
        },
        null => null,
      },
    );
  } on ModelException catch (error) {
    stderr.writeln(error);
    await _writeError(jsonPath, error.message);
    exitCode = 1;
    return;
  } on InvalidAnswerException catch (error) {
    stderr.writeln(error);
    await _writeError(jsonPath, error.message);
    exitCode = 1;
    return;
  } finally {
    client.close();
  }
  watch.stop();

  if (result.sentRules.isEmpty) {
    stdout.writeln('No rule applies to this change: the model was not called.');
  } else {
    stdout
      ..writeln('Model: ${client.answeredBy} (${config.provider})')
      ..writeln('Rules applied: ${result.sentRules.join(', ')}');
  }
  if (client.answeredByDiscoveredModel) {
    stdout.writeln(
      'Note: this model was found in the list of ${config.provider}. '
      'It was not measured by the evaluation of the agent.',
    );
  } else if (!config.tested) {
    stdout.writeln(
      'Note: this provider or model was not measured by the evaluation of '
      'the agent yet.',
    );
  }
  _printReport(result, rules);

  if (jsonPath != null) {
    final Map<String, Rule> rulesById = <String, Rule>{
      for (final Rule rule in rules) rule.id: rule,
    };
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'provider': config.provider,
        'model': client.answeredBy ?? '',
        'measured': config.tested && !client.answeredByDiscoveredModel,
        'seconds': watch.elapsedMilliseconds / 1000,
        'files': result.reviewedFiles,
        'rules': result.sentRules,
        'findings': <Map<String, Object>>[
          for (final Finding finding in result.accepted)
            <String, Object>{
              ...finding.toJson(),
              'title': rulesById[finding.rule]?.title ?? 'Project convention',
              if (rulesById[finding.rule]?.level case final String level)
                'level': level,
              if (rulesById[finding.rule]?.source case final String source)
                'source': source,
            },
        ],
        'checks': <Map<String, Object>>[
          for (final RuleCheck check in result.checks) check.toJson(),
        ],
        'rejected': <Map<String, Object>>[
          for (final RejectedFinding item in result.rejected)
            <String, Object>{...item.finding.toJson(), 'reason': item.reason},
        ],
      }),
    );
  }
}

Future<void> _writeError(String? jsonPath, String message) async {
  if (jsonPath != null) {
    await File(
      jsonPath,
    ).writeAsString(jsonEncode(<String, String>{'error': message}));
  }
}

void _printReport(ReviewResult result, List<Rule> rules) {
  final Map<String, Rule> rulesById = <String, Rule>{
    for (final Rule rule in rules) rule.id: rule,
  };
  stdout.writeln('Reviewed: ${result.reviewedFiles.join(', ')}');
  if (result.accepted.isEmpty) {
    stdout.writeln('No remarks.');
  }
  for (final Finding finding in result.accepted) {
    final String title = rulesById[finding.rule]?.title ?? 'Project convention';
    stdout
      ..writeln()
      ..writeln('${finding.file}:${finding.line}  [${finding.rule}] $title')
      ..writeln('  ${finding.message}');
  }
  if (result.rejected.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln('Refused by the agent (${result.rejected.length}):');
    for (final RejectedFinding item in result.rejected) {
      stdout.writeln(
        '  ${item.finding.file}:${item.finding.line} '
        '[${item.finding.rule}] ${item.reason}',
      );
    }
  }
}
