import 'dart:convert';

import 'package:flutter_review/flutter_review.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('reviews Dart code written by hand and the pubspec', () {
    expect(isReviewed('lib/main.dart'), isTrue);
    expect(isReviewed('test/main_test.dart'), isTrue);
    expect(isReviewed('pubspec.yaml'), isTrue);
  });

  test('skips generated and other files', () {
    expect(isReviewed('lib/user.g.dart'), isFalse);
    expect(isReviewed('lib/user.freezed.dart'), isFalse);
    expect(isReviewed('test/api.mocks.dart'), isFalse);
    expect(isReviewed('README.md'), isFalse);
    expect(isReviewed('assets/logo.png'), isFalse);
  });

  test('asks again once when the answer is not the expected JSON', () async {
    int calls = 0;
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        calls++;
        final String content = calls == 1
            ? 'Here is my review.'
            : '{"checks": [], "findings": []}';
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{'content': content},
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')],
      client: client,
    );

    expect(calls, 2);
    expect(result.accepted, isEmpty);
  });
}
