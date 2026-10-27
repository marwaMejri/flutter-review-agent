import 'dart:convert';

import 'package:flutter_review/flutter_review.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final Map<String, Object?> result = <String, Object?>{
  'provider': 'groq',
  'model': 'openai/gpt-oss-120b',
  'measured': true,
  'seconds': 4.2,
  'rules': <String>['P1', 'T3'],
  'findings': <Map<String, Object>>[
    <String, Object>{
      'rule': 'P1',
      'file': 'lib/a.dart',
      'line': 12,
      'message': 'Sort once, outside build().',
      'evidence': 'sorted',
      'title': 'Expensive work in `build()`',
      'level': 'issue',
      'source':
          '[Performance best practices](https://docs.flutter.dev/perf/best-practices)',
    },
  ],
};

void main() {
  test('puts each remark on its line, with its rule and source', () {
    final Map<String, Object> request = reviewRequest(result, commitId: 'abc');

    expect(request['commit_id'], 'abc');
    expect(request['event'], 'COMMENT');
    final Map<String, Object> comment =
        (request['comments']! as List<Map<String, Object>>).single;
    expect(comment['path'], 'lib/a.dart');
    expect(comment['line'], 12);
    expect(comment['side'], 'RIGHT');
    expect(
      comment['body'],
      contains('**[P1] Expensive work in `build()`** (issue)'),
    );
    expect(comment['body'], contains('Sort once, outside build().'));
    expect(comment['body'], contains('Source: [Performance best practices]'));
    expect(request['body'], contains('`openai/gpt-oss-120b` (groq) in 4 s'));
    expect(request['body'], contains('Rules checked: P1, T3.'));
    expect(request['body'], contains('1 remark,'));
  });

  test('says when no rule applies', () {
    final Map<String, Object> request = reviewRequest(<String, Object?>{
      'provider': 'groq',
      'model': '',
      'rules': <String>[],
      'findings': <Object>[],
    }, commitId: 'abc');

    expect(request['body'], contains('no rule applies to this change'));
    expect(request['comments'], isEmpty);
  });

  test('says that the pull request is not blocked when the review fails', () {
    expect(
      unavailableText('quota used up'),
      allOf(contains('quota used up'), contains('not blocked')),
    );
  });

  test('posts the review to the pull request', () async {
    late http.Request sent;
    final GitHubReviewer reviewer = GitHubReviewer(
      repository: 'owner/app',
      token: 'token',
      httpClient: MockClient((http.Request request) async {
        sent = request;
        return http.Response('{}', 200);
      }),
    );

    await reviewer.postReview(7, reviewRequest(result, commitId: 'abc'));

    expect(
      sent.url.toString(),
      'https://api.github.com/repos/owner/app/pulls/7/reviews',
    );
    expect(sent.headers['Authorization'], 'Bearer token');
  });

  test('keeps the remarks in the text when GitHub refuses the lines', () async {
    final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
    final GitHubReviewer reviewer = GitHubReviewer(
      repository: 'owner/app',
      token: 'token',
      httpClient: MockClient((http.Request request) async {
        bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        return bodies.length == 1
            ? http.Response('{"message": "Validation Failed"}', 422)
            : http.Response('{}', 200);
      }),
    );

    await reviewer.postReview(7, reviewRequest(result, commitId: 'abc'));

    expect(bodies, hasLength(2));
    expect(bodies.last['comments'], isEmpty);
    expect(bodies.last['body'], contains('`lib/a.dart:12`'));
    expect(bodies.last['body'], contains('Sort once, outside build().'));
  });

  test('posts a comment on the pull request', () async {
    late http.Request sent;
    final GitHubReviewer reviewer = GitHubReviewer(
      repository: 'owner/app',
      token: 'token',
      httpClient: MockClient((http.Request request) async {
        sent = request;
        return http.Response('{}', 201);
      }),
    );

    await reviewer.postComment(7, 'text');

    expect(
      sent.url.toString(),
      'https://api.github.com/repos/owner/app/issues/7/comments',
    );
    expect(jsonDecode(sent.body), <String, String>{'body': 'text'});
  });

  test('explains a request that GitHub refuses', () {
    final GitHubReviewer reviewer = GitHubReviewer(
      repository: 'owner/app',
      token: 'token',
      httpClient: MockClient(
        (http.Request request) async => http.Response('Forbidden', 403),
      ),
    );

    expect(reviewer.postComment(7, 'text'), throwsA(isA<GitHubException>()));
  });
}
