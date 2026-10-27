import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when GitHub refuses a request.
class GitHubException implements Exception {
  GitHubException(this.message);

  final String message;

  @override
  String toString() => 'GitHubException: $message';
}

/// The text of the review for the result of the agent, as written by
/// `flutter_review --json`.
///
/// Every remark becomes a comment on its line, with its rule, its level and
/// its source, so the author can check it.
Map<String, Object> reviewRequest(
  Map<String, Object?> result, {
  required String commitId,
}) {
  final List<Map<String, Object?>> findings = <Map<String, Object?>>[
    for (final Object? item
        in result['findings'] as List<Object?>? ?? <Object?>[])
      item! as Map<String, Object?>,
  ];
  return <String, Object>{
    'commit_id': commitId,
    'event': 'COMMENT',
    'body': reviewSummary(result),
    'comments': <Map<String, Object>>[
      for (final Map<String, Object?> finding in findings)
        <String, Object>{
          'path': finding['file']! as String,
          'line': finding['line']! as int,
          // RIGHT is the new version of the file: the agent only reports lines
          // that the pull request adds.
          'side': 'RIGHT',
          'body': remarkText(finding),
        },
    ],
  };
}

/// The first lines of the review: the model and what was checked.
String reviewSummary(Map<String, Object?> result) {
  final List<Object?> findings =
      result['findings'] as List<Object?>? ?? <Object?>[];
  final List<Object?> rules = result['rules'] as List<Object?>? ?? <Object?>[];
  final StringBuffer text = StringBuffer('**Flutter review**');
  if (rules.isEmpty) {
    text.write(': no rule applies to this change, so no model was called.');
    return text.toString();
  }
  final String model = result['model'] as String? ?? '';
  final String provider = result['provider'] as String? ?? '';
  final Object? seconds = result['seconds'];
  text
    ..write(' by `$model` ($provider)')
    ..write(seconds is num ? ' in ${seconds.toStringAsFixed(0)} s' : '')
    ..writeln('.')
    ..writeln()
    ..writeln('Rules checked: ${rules.join(', ')}.')
    ..write(
      findings.isEmpty
          ? 'No remark.'
          : '${findings.length} remark${findings.length == 1 ? '' : 's'}, '
                'on the lines below.',
    );
  if (result['measured'] == false) {
    text
      ..writeln()
      ..writeln()
      ..write(
        'This provider or model was not measured by the evaluation of the '
        'agent yet.',
      );
  }
  text
    ..writeln()
    ..writeln()
    ..write(
      'The remarks never block the pull request. Each one cites the rule and '
      'its source.',
    );
  return text.toString();
}

/// One remark, as a comment on its line.
String remarkText(Map<String, Object?> finding) {
  final String rule = finding['rule']! as String;
  final String title = finding['title'] as String? ?? '';
  final String? level = finding['level'] as String?;
  final String? source = finding['source'] as String?;
  return <String>[
    '**[$rule] $title**${level == null ? '' : ' ($level)'}',
    finding['message']! as String,
    if (source != null) 'Source: $source',
  ].join('\n\n');
}

/// The comment written when the agent could not review the pull request.
String unavailableText(String reason) =>
    '**Flutter review unavailable**: $reason\n\n'
    'The pull request is not blocked. Push again to try another review.';

/// Writes the review on a pull request with the GitHub REST API.
class GitHubReviewer {
  GitHubReviewer({
    required this.repository,
    required this.token,
    this.apiUrl = 'https://api.github.com',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// `owner/name`, as in `GITHUB_REPOSITORY`.
  final String repository;
  final String token;

  /// As in `GITHUB_API_URL`, which differs on GitHub Enterprise Server.
  final String apiUrl;

  final http.Client _http;

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'Content-Type': 'application/json',
  };

  /// Posts [request] as a review of pull request [number].
  ///
  /// When GitHub refuses the comments on lines (HTTP 422, for example a line
  /// that it does not see in the diff), the review is posted again with the
  /// remarks in its text, so they are never lost.
  Future<void> postReview(int number, Map<String, Object> request) async {
    final Uri uri = Uri.parse(
      '$apiUrl/repos/$repository/pulls/$number/reviews',
    );
    http.Response response = await _http.post(
      uri,
      headers: _headers,
      body: jsonEncode(request),
    );
    final List<Map<String, Object?>> comments =
        (request['comments']! as List<Object?>).cast<Map<String, Object?>>();
    if (response.statusCode == 422 && comments.isNotEmpty) {
      response = await _http.post(
        uri,
        headers: _headers,
        body: jsonEncode(<String, Object>{
          ...request,
          'comments': <Object>[],
          'body': <String>[
            request['body']! as String,
            for (final Map<String, Object?> item in comments)
              '`${item['path']}:${item['line']}`\n\n${item['body']}',
          ].join('\n\n---\n\n'),
        }),
      );
    }
    _check(response, 'post the review');
  }

  /// Posts [text] as a comment on pull request [number].
  Future<void> postComment(int number, String text) async {
    final http.Response response = await _http.post(
      Uri.parse('$apiUrl/repos/$repository/issues/$number/comments'),
      headers: _headers,
      body: jsonEncode(<String, String>{'body': text}),
    );
    _check(response, 'post the comment');
  }

  void _check(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubException(
        'Cannot $action: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  void close() => _http.close();
}
