import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_review/flutter_review.dart';

const String defaultBaseUrl =
    'https://generativelanguage.googleapis.com/v1beta/openai/';
const String defaultModel = 'gemini-3.8-flash';
const String apiKeyVariable = 'FLUTTER_REVIEW_API_KEY';

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
    ..addOption('base-url', defaultsTo: defaultBaseUrl)
    ..addOption('model', defaultsTo: defaultModel)
    ..addOption('json', help: 'Also write the result as JSON to this path.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  if (options.flag('help') || options.option('diff') == null) {
    stdout
      ..writeln('Usage: dart run flutter_review --diff <file>')
      ..writeln()
      ..writeln('The API key is read from $apiKeyVariable.')
      ..writeln(parser.usage);
    return;
  }

  final String? apiKey = Platform.environment[apiKeyVariable];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set the API key in the $apiKeyVariable variable.');
    exitCode = 78;
    return;
  }

  final String diffPath = options.option('diff')!;
  final String diff = diffPath == '-'
      ? await stdin.transform(utf8.decoder).join()
      : await File(diffPath).readAsString();

  final List<Rule> rules = <Rule>[
    ...await _readRules(Directory(options.option('rules')!)),
    for (final String pack in options.multiOption('pack'))
      ...parseRules(
        await File('${options.option('packs')}/$pack.md').readAsString(),
      ),
  ];

  final String? conventionsPath = options.option('conventions');
  final String? conventions =
      conventionsPath != null && File(conventionsPath).existsSync()
      ? await File(conventionsPath).readAsString()
      : null;

  final ModelClient client = ModelClient(
    baseUrl: options.option('base-url')!,
    model: options.option('model')!,
    apiKey: apiKey,
  );
  final ReviewResult result;
  try {
    result = await review(
      diff: diff,
      rules: rules,
      client: client,
      conventions: conventions,
    );
  } on ModelException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  } on InvalidAnswerException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  } finally {
    client.close();
  }

  _printReport(result, rules);

  final String? jsonPath = options.option('json');
  if (jsonPath != null) {
    await File(jsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'model': options.option('model')!,
        'files': result.reviewedFiles,
        'findings': <Map<String, Object>>[
          for (final Finding finding in result.accepted) finding.toJson(),
        ],
        'rejected': <Map<String, Object>>[
          for (final RejectedFinding item in result.rejected)
            <String, Object>{...item.finding.toJson(), 'reason': item.reason},
        ],
      }),
    );
  }
}

/// Reads every rules file of a folder, except its README.
Future<List<Rule>> _readRules(Directory folder) async {
  final List<File> files =
      folder
          .listSync()
          .whereType<File>()
          .where(
            (File file) =>
                file.path.endsWith('.md') && !file.path.endsWith('README.md'),
          )
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  return <Rule>[
    for (final File file in files) ...parseRules(await file.readAsString()),
  ];
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
