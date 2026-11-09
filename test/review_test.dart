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

  test('does not ask again when the answer was cut', () async {
    int calls = 0;
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'finish_reason': 'length',
                'message': <String, String>{'content': '{"checks": ['},
              },
            ],
          }),
          200,
        );
      }),
    );

    await expectLater(
      review(
        diff: sampleDiff,
        rules: <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')],
        client: client,
      ),
      throwsA(
        isA<InvalidAnswerException>().having(
          (InvalidAnswerException e) => e.message,
          'message',
          contains('finish_reason: length'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('checks the conventions when no rule is triggered', () async {
    int calls = 0;
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{
                  'content':
                      '{"checks": [{"rule": "CONVENTION", "reason": "Fields '
                      'are named x", "applies": true}], "findings": [{"rule": '
                      '"CONVENTION", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "Name it x.", '
                      '"convention": "C1"}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[
        Rule(
          id: 'P1',
          title: 't',
          text: '## P1. t',
          triggers: <String>['sort('],
        ),
      ],
      client: client,
      conventions: '- Fields are named x.',
    );

    expect(calls, 1);
    expect(result.sentRules, <String>['CONVENTION']);
    expect(result.accepted.single.rule, 'CONVENTION');
    expect(result.checks.single.rule, 'CONVENTION');
  });

  test('does not call the model when nothing applies', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        fail('The model must not be called.');
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[
        Rule(
          id: 'P1',
          title: 't',
          text: '## P1. t',
          triggers: <String>['sort('],
        ),
      ],
      client: client,
    );

    expect(result.sentRules, isEmpty);
  });

  test('keeps one remark of a rule marked one per pull request', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{
                  'content':
                      '{"checks": [], "findings": ['
                      '{"rule": "T3", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "Test it."}, '
                      '{"rule": "T3", "file": "lib/a.dart", "line": 12, '
                      '"evidence": "final int w;", "message": "Test it."}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[
        Rule(
          id: 'T3',
          title: 't',
          text: '## T3. t\n\n- **Remarks:** one per pull request',
          triggers: <String>['file:lib/'],
        ),
      ],
      client: client,
    );

    expect(result.accepted.single.line, 11);
    expect(result.rejected.single.finding.line, 12);
    expect(
      result.rejected.single.reason,
      'one remark of this rule per pull request',
    );
  });

  test('refuses MEM1 on a line that has B2', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{
                  'content':
                      '{"checks": [], "findings": ['
                      '{"rule": "B2", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "m"}, '
                      '{"rule": "MEM1", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "m"}, '
                      '{"rule": "MEM1", "file": "lib/a.dart", "line": 12, '
                      '"evidence": "final int w;", "message": "m"}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[
        Rule(id: 'B2', title: 't', text: '## B2. t'),
        Rule(
          id: 'MEM1',
          title: 't',
          text: '## MEM1. t\n\n- **Not on a line of:** B2',
        ),
      ],
      client: client,
    );

    expect(result.accepted.map((Finding f) => '${f.rule}:${f.line}'), <String>[
      'B2:11',
      'MEM1:12',
    ]);
    expect(result.rejected.single.reason, 'B2 is on the same line');
  });

  test('refuses T3 when no added line shows a behavior, and invented '
      'conventions', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{
                  'content':
                      '{"checks": [], "findings": ['
                      '{"rule": "T3", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "m"}, '
                      '{"rule": "CONVENTION", "file": "lib/a.dart", '
                      '"line": 11, "evidence": "final int z;", "message": "m", '
                      '"convention": "[C1]"}, '
                      '{"rule": "CONVENTION", "file": "lib/a.dart", '
                      '"line": 12, "evidence": "final int w;", "message": "m", '
                      '"convention": "C9"}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: sampleDiff,
      rules: <Rule>[
        Rule(
          id: 'T3',
          title: 't',
          text:
              '## T3. t\n\n- **Only when:** an added line under `lib/` '
              'shows a behavior',
        ),
      ],
      client: client,
      conventions: '## Names\n- Fields are named x.',
    );

    expect(result.accepted.single.convention, 'Fields are named x.');
    expect(result.rejected.map((RejectedFinding r) => r.reason), <String>[
      'no added line under lib/ shows a behavior',
      'convention not found in the conventions',
    ]);
  });

  test('moves a T5 remark to the test line with pumpAndSettle', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{
                  'content':
                      '{"checks": [], "findings": [{"rule": "T5", '
                      '"file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "m"}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff:
          '$sampleDiff'
          'diff --git a/test/a_test.dart b/test/a_test.dart\n'
          '--- a/test/a_test.dart\n'
          '+++ b/test/a_test.dart\n'
          '@@ -1,1 +1,3 @@\n'
          '   await tester.tap(find.text(\'Settings\'));\n'
          '+  await tester.pumpAndSettle();\n'
          '+  expect(find.byType(SettingsView), findsOneWidget);\n',
      rules: <Rule>[
        Rule(
          id: 'T5',
          title: 't',
          text:
              '## T5. t\n\n- **Remark place:** the first added test line '
              'that contains `pumpAndSettle(`',
        ),
      ],
      client: client,
    );

    expect(result.accepted.single.file, 'test/a_test.dart');
    expect(result.accepted.single.line, 2);
  });

  group('a request too large for the provider', () {
    // A new file of 120 lines: line 1 is "// first line", line 120 is
    // "// last line".
    final String bigDiff = <String>[
      'diff --git a/lib/big.dart b/lib/big.dart',
      'new file mode 100644',
      '--- /dev/null',
      '+++ b/lib/big.dart',
      '@@ -0,0 +1,120 @@',
      for (int i = 0; i < 120; i++)
        i == 0
            ? '+// first line'
            : i == 119
            ? '+// last line'
            : '+// line $i',
      '',
    ].join('\n');
    final List<Rule> rules = <Rule>[
      Rule(id: 'P1', title: 't', text: '## P1. t'),
    ];

    http.Response modelAnswer(String content) => http.Response(
      jsonEncode(<String, Object>{
        'choices': <Object>[
          <String, Object>{
            'message': <String, String>{'content': content},
          },
        ],
      }),
      200,
    );

    ModelClient clientWith(Future<http.Response> Function(String) answer) =>
        ModelClient(
          provider: 'test-provider',
          baseUrl: 'https://example.com/v1/',
          models: <String>['test-model'],
          apiKey: 'test-key',
          httpClient: MockClient(
            (http.Request request) async => answer(request.body),
          ),
        );

    test('is sent again with the changed parts only', () async {
      int calls = 0;
      final ModelClient client = clientWith((String body) async {
        calls++;
        return body.contains('(whole file)')
            ? http.Response('too large', 413)
            : modelAnswer('{"checks": [], "findings": []}');
      });

      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: rules,
        client: client,
        readSource: (String path) => 'line\n' * 14,
      );

      expect(calls, 2);
      expect(result.note, contains('with the changed parts only'));
    });

    test('is cut in two parts, and the answers are put together', () async {
      int calls = 0;
      final ModelClient client = clientWith((String body) async {
        calls++;
        final bool first = body.contains('first line');
        final bool last = body.contains('last line');
        if (first && last) {
          return http.Response('too large', 413);
        }
        return modelAnswer(
          first
              ? '{"checks": [{"rule": "P1", "reason": "a", "applies": false}], '
                    '"findings": [{"rule": "P1", "file": "lib/big.dart", '
                    '"line": 1, "evidence": "// first line", "message": "m"}]}'
              : '{"checks": [{"rule": "P1", "reason": "b", "applies": true}], '
                    '"findings": [{"rule": "P1", "file": "lib/big.dart", '
                    '"line": 120, "evidence": "// last line", '
                    '"message": "m"}]}',
        );
      });

      final ReviewResult result = await review(
        diff: bigDiff,
        rules: rules,
        client: client,
      );

      expect(calls, 3);
      expect(result.accepted.map((Finding f) => f.line), <int>[1, 120]);
      expect(result.checks.single.reason, 'b');
      expect(result.note, contains('reviewed in 2 parts'));
    });

    test(
      'stops with a clear error when a small part is still too large',
      () async {
        final ModelClient client = clientWith(
          (String body) async => http.Response('too large', 413),
        );

        await expectLater(
          review(diff: bigDiff, rules: rules, client: client),
          throwsA(
            isA<RequestTooLargeException>().having(
              (RequestTooLargeException e) => e.message,
              'message',
              allOf(contains('still too large'), contains('Last refusal')),
            ),
          ),
        );
      },
    );
  });
}
