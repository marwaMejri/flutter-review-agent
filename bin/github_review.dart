// Writes the result of `flutter_review --json` on a pull request: a review
// with one comment on each remarked line, or a comment that says why the
// review is unavailable. Used by the GitHub Action (action.yml).
//
// Settings come from the environment of a GitHub Actions job:
// GitHub_REPOSITORY, GitHub_API_URL and GitHub_TOKEN.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_review/flutter_review.dart';

Future<void> main(List<String> arguments) async {
  final ArgResults options;
  try {
    options =
        (ArgParser()
              ..addOption('result', help: 'JSON written by flutter_review.')
              ..addOption('pull-request', help: 'Number of the pull request.')
              ..addOption('commit', help: 'Last commit of the pull request.'))
            .parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final String? resultPath = options.option('result');
  final int? number = int.tryParse(options.option('pull-request') ?? '');
  final String? commit = options.option('commit');
  final String? repository = Platform.environment['GITHUB_REPOSITORY'];
  final String? token = Platform.environment['GITHUB_TOKEN'];
  if (resultPath == null ||
      number == null ||
      commit == null ||
      repository == null ||
      token == null ||
      token.isEmpty) {
    stderr.writeln(
      'Usage: github_review --result <json> --pull-request <number> '
      '--commit <sha>, with GITHUB_REPOSITORY and GITHUB_TOKEN set.',
    );
    exitCode = 64;
    return;
  }

  final GitHubReviewer reviewer = GitHubReviewer(
    repository: repository,
    token: token,
    apiUrl: Platform.environment['GITHUB_API_URL'] ?? 'https://api.github.com',
  );
  try {
    final Map<String, Object?>? result = _readResult(resultPath);
    if (result == null) {
      await reviewer.postComment(
        number,
        unavailableText(
          'the agent stopped before it wrote its result. The log of the job '
          'says why.',
        ),
      );
    } else if (result['error'] case final String error) {
      await reviewer.postComment(number, unavailableText(error));
    } else {
      await reviewer.postReview(
        number,
        reviewRequest(result, commitId: commit),
      );
    }
  } on GitHubException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    reviewer.close();
  }
}

Map<String, Object?>? _readResult(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
