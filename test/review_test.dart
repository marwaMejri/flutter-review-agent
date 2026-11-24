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
    expect(isReviewed('packages/core/pubspec.yaml'), isTrue);
    expect(isReviewed('packages/core/lib/a.dart'), isTrue);
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

    // The second request asks the conventions again, alone.
    expect(calls, 2);
    expect(result.sentRules, <String>['CONVENTION']);
    expect(result.accepted.single.rule, 'CONVENTION');
    expect(result.checks.single.rule, 'CONVENTION');
  });

  group('a CONVENTION remark', () {
    String finding(String id) =>
        '{"checks": [], "findings": [{"rule": "CONVENTION", "file": '
        '"lib/a.dart", "line": 11, "evidence": "final int z;", "message": '
        '"m", "convention": "$id"}]}';
    const String none =
        '{"checks": [{"rule": "CONVENTION", "applies": false, "reason": '
        '"Names: no convention broken."}], "findings": []}';
    const String conventions =
        '## Names\n- Fields are named x.\n- Fields are final.';

    ModelClient clientOf(List<String> answers, List<String> prompts) =>
        ModelClient(
          provider: 'test-provider',
          baseUrl: 'https://example.com/v1/',
          models: <String>['test-model'],
          apiKey: 'test-key',
          httpClient: MockClient((http.Request request) async {
            prompts.add(request.body);
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Object>[
                  <String, Object>{
                    'message': <String, String>{
                      'content': answers[prompts.length - 1],
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );

    test('is kept when the second answer flags it too', () async {
      final List<String> prompts = <String>[];
      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: <Rule>[],
        client: clientOf(<String>[finding('C1'), finding('C1')], prompts),
        conventions: conventions,
      );

      expect(prompts, hasLength(2));
      expect(result.accepted.single.convention, 'Fields are named x.');
      expect(
        result.note,
        'The conventions were asked a second time, alone: each convention '
        'remark below is flagged by both answers.',
      );
    });

    test('is refused when the second answer flags nothing', () async {
      final List<String> prompts = <String>[];
      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: <Rule>[],
        client: clientOf(<String>[finding('C1'), none], prompts),
        conventions: conventions,
      );

      expect(prompts, hasLength(2));
      expect(result.accepted, isEmpty);
      expect(
        result.rejected.single.reason,
        'convention not flagged again by a second answer',
      );
    });

    test(
      'is refused when the second answer flags another convention',
      () async {
        final List<String> prompts = <String>[];
        final ReviewResult result = await review(
          diff: sampleDiff,
          rules: <Rule>[],
          client: clientOf(<String>[finding('C1'), finding('C2')], prompts),
          conventions: conventions,
        );

        expect(result.accepted, isEmpty);
        expect(
          result.rejected.single.reason,
          'convention not flagged again by a second answer',
        );
      },
    );

    test('is asked again once, with the conventions and no rule', () async {
      final List<String> prompts = <String>[];
      await review(
        diff: sampleDiff,
        rules: <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')],
        client: clientOf(<String>[
          '{"checks": [], "findings": ['
              '{"rule": "CONVENTION", "file": "lib/a.dart", "line": 11, '
              '"evidence": "final int z;", "message": "m", '
              '"convention": "C1"}, '
              '{"rule": "CONVENTION", "file": "lib/a.dart", "line": 12, '
              '"evidence": "final int w;", "message": "m", '
              '"convention": "C2"}]}',
          finding('C1'),
        ], prompts),
        conventions: conventions,
      );

      expect(prompts, hasLength(2));
      expect(prompts.last, contains('# Project conventions'));
      expect(prompts.last, isNot(contains('## P1. t')));
    });

    test(
      'keeps the model of the review when the second request fails',
      () async {
        // Pull request #30: Gemini was busy for the second request, and the
        // review named no model.
        int calls = 0;
        final ModelClient client = ModelClient(
          provider: 'test-provider',
          baseUrl: 'https://example.com/v1/',
          models: <String>['test-model'],
          apiKey: 'test-key',
          maxAttempts: 1,
          httpClient: MockClient((http.Request request) async {
            calls++;
            if (calls > 1) {
              return http.Response('busy', 503);
            }
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Object>[
                  <String, Object>{
                    'message': <String, String>{'content': finding('C1')},
                  },
                ],
              }),
              200,
            );
          }),
        );

        final ReviewResult result = await review(
          diff: sampleDiff,
          rules: <Rule>[],
          client: client,
          conventions: conventions,
        );

        expect(calls, 2);
        expect(result.accepted.single.rule, 'CONVENTION');
        expect(
          result.note,
          'The conventions could not be asked a second time: the first answer '
          'is kept.',
        );
        expect(client.answeredBy, 'test-model');
      },
    );

    test('is not asked again when no convention is flagged', () async {
      final List<String> prompts = <String>[];
      await review(
        diff: sampleDiff,
        rules: <Rule>[],
        client: clientOf(<String>[none], prompts),
        conventions: conventions,
      );

      expect(prompts, hasLength(1));
    });
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

  group('a rule marked Confirm', () {
    // A test file with an added check: the model judges whether it tests the
    // new code.
    const String tested =
        '$sampleDiff'
        'diff --git a/test/a_test.dart b/test/a_test.dart\n'
        'new file mode 100644\n'
        '--- /dev/null\n'
        '+++ b/test/a_test.dart\n'
        '@@ -0,0 +1,1 @@\n'
        '+  test(\'z\', () => expect(A().z, 1));\n';
    final Rule t3 = Rule(
      id: 'T3',
      title: 't',
      text:
          '## T3. t\n\n- **Confirm:** when a test of the pull request has an '
          'added check, or when its only new behavior is a lifecycle method',
    );
    const String flagged =
        '{"checks": [], "findings": [{"rule": "T3", "file": "lib/a.dart", '
        '"line": 11, "evidence": "final int z;", "message": "Test it."}]}';
    const String notFlagged =
        '{"checks": [{"rule": "T3", "applies": false, "reason": "Step 4: '
        'yes, a_test.dart checks z."}], "findings": []}';

    ModelClient clientOf(List<String> answers, List<String> prompts) =>
        ModelClient(
          provider: 'test-provider',
          baseUrl: 'https://example.com/v1/',
          models: <String>['test-model'],
          apiKey: 'test-key',
          httpClient: MockClient((http.Request request) async {
            prompts.add(request.body);
            return http.Response(
              jsonEncode(<String, Object>{
                'choices': <Object>[
                  <String, Object>{
                    'message': <String, String>{
                      'content': answers[prompts.length - 1],
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );

    test('is refused when the second answer does not flag it', () async {
      final List<String> prompts = <String>[];
      final ReviewResult result = await review(
        diff: tested,
        rules: <Rule>[t3],
        client: clientOf(<String>[flagged, notFlagged], prompts),
      );

      expect(prompts, hasLength(2));
      expect(result.accepted, isEmpty);
      expect(
        result.rejected.single.reason,
        'not flagged again by a second answer: Step 4: yes, a_test.dart '
        'checks z.',
      );
    });

    test('is kept when the second answer flags it too', () async {
      final List<String> prompts = <String>[];
      final ReviewResult result = await review(
        diff: tested,
        rules: <Rule>[t3],
        client: clientOf(<String>[flagged, flagged], prompts),
      );

      expect(prompts, hasLength(2));
      expect(result.accepted.single.rule, 'T3');
      expect(
        result.note,
        'T3 was asked a second time, alone: both answers flag it.',
      );
    });

    test(
      'is asked again when the only behavior is a lifecycle method',
      () async {
        // flutter/samples #2838: a view model created in initState and disposed
        // in dispose.
        const String wiring =
            'diff --git a/lib/b.dart b/lib/b.dart\n'
            'new file mode 100644\n'
            '--- /dev/null\n'
            '+++ b/lib/b.dart\n'
            '@@ -0,0 +1,6 @@\n'
            '+class _BState extends State<B> {\n'
            '+  @override\n'
            '+  void initState() {\n'
            '+    super.initState();\n'
            '+    _model = Model();\n'
            '+  }\n';
        const String flaggedHere =
            '{"checks": [], "findings": [{"rule": "T3", "file": "lib/b.dart", '
            '"line": 3, "evidence": "void initState() {", "message": "m"}]}';
        final List<String> prompts = <String>[];
        final ReviewResult result = await review(
          diff: wiring,
          rules: <Rule>[t3],
          client: clientOf(<String>[flaggedHere, notFlagged], prompts),
        );

        expect(prompts, hasLength(2));
        expect(result.accepted, isEmpty);
      },
    );

    test('is not asked again when no test has an added check', () async {
      final List<String> prompts = <String>[];
      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: <Rule>[t3],
        client: clientOf(<String>[flagged], prompts),
      );

      expect(prompts, hasLength(1));
      expect(result.accepted.single.rule, 'T3');
    });
  });

  test('keeps one remark of a rule on one line', () async {
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
                      '{"rule": "P1", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "a"}, '
                      '{"rule": "P1", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "b"}]}',
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
      rules: <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')],
      client: client,
    );

    expect(result.accepted.single.message, 'a');
    expect(
      result.rejected.single.reason,
      'the same remark is already on this line',
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

  test('refuses a CONVENTION remark on the line of a rule remark', () async {
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
                      '{"rule": "CONVENTION", "file": "lib/a.dart", '
                      '"line": 11, "evidence": "final int z;", "message": "m", '
                      '"convention": "C1"}, '
                      '{"rule": "P1", "file": "lib/a.dart", "line": 11, '
                      '"evidence": "final int z;", "message": "m"}, '
                      '{"rule": "CONVENTION", "file": "lib/a.dart", '
                      '"line": 12, "evidence": "final int w;", "message": "m", '
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
      rules: <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')],
      client: client,
      conventions: '## Names\n- Fields are named x.',
    );

    expect(
      <String>[for (final Finding f in result.accepted) '${f.rule} ${f.line}'],
      <String>['P1 11', 'CONVENTION 12'],
    );
    expect(
      result.rejected.single.reason,
      'the line already has a remark of P1',
    );
  });

  test('refuses a convention about a package on a line that is no import', () async {
    // Pull request #3: "widgets from flutter/material" on a widget line of a
    // file that does not import package:flutter/material.dart.
    const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
new file mode 100644
--- /dev/null
+++ b/lib/a.dart
@@ -0,0 +1,3 @@
+import 'package:flutter/material.dart';
+
+Widget icon() => const Icon(Icons.info, color: Colors.black);
''';
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
                      '{"rule": "CONVENTION", "file": "lib/a.dart", "line": 3, '
                      '"evidence": "Colors.black", "message": "m", '
                      '"convention": "C1"}, '
                      '{"rule": "CONVENTION", "file": "lib/a.dart", "line": 1, '
                      '"evidence": "import \'package:flutter/material.dart\';", '
                      '"message": "m", "convention": "C1"}]}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: diff,
      rules: <Rule>[],
      client: client,
      conventions:
          '## Design library\n'
          '- Widgets come from `package:material_ui/material_ui.dart`, never '
          'from `package:flutter/material.dart`.',
    );

    expect(result.accepted.single.line, 1);
    expect(
      result.rejected.single.reason,
      'a convention about a package, not on an import or export line',
    );
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

  test('refuses a T5 remark when no added test line has its place', () async {
    // flutter/samples #2819: the router changes, and the pull request adds no
    // test that taps and waits with pumpAndSettle.
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
      diff: sampleDiff,
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

    expect(result.accepted, isEmpty);
    expect(
      result.rejected.single.reason,
      'no added test line contains `pumpAndSettle(`',
    );
  });

  test('moves a T5 remark to the pumpAndSettle after the tap', () async {
    // Pull request #14: the model put T5 on the tap line of a test.
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
                      '"file": "test/a_test.dart", "line": 5, '
                      '"evidence": "tester.tap(", "message": "m"}]}',
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
          'diff --git a/test/a_test.dart b/test/a_test.dart\n'
          'new file mode 100644\n'
          '--- /dev/null\n'
          '+++ b/test/a_test.dart\n'
          '@@ -0,0 +1,7 @@\n'
          '+  await tester.pumpWidget(const App());\n'
          '+  await tester.pumpAndSettle();\n'
          '+\n'
          '+\n'
          '+  await tester.tap(find.text(\'Settings\'));\n'
          '+  await tester.pumpAndSettle();\n'
          '+  expect(find.byType(SettingsView), findsOneWidget);\n',
      rules: <Rule>[
        Rule(
          id: 'T5',
          title: 't',
          text:
              '## T5. t\n\n- **Remark place:** the first added test line '
              'that contains `pumpAndSettle(` right after a `tap(`',
        ),
      ],
      client: client,
    );

    expect(result.accepted.single.line, 6);
  });

  group('an answer cut, or a small part still too large', () {
    final List<Rule> twoRules = <Rule>[
      Rule(id: 'P1', title: 't', text: '## P1. t'),
      Rule(id: 'P2', title: 't', text: '## P2. t'),
    ];
    String findingFor(String body) => body.contains('## P1. t')
        ? '{"rule": "P1", "file": "lib/a.dart", "line": 11, '
              '"evidence": "final int z;", "message": "m"}'
        : '{"rule": "P2", "file": "lib/a.dart", "line": 12, '
              '"evidence": "final int w;", "message": "m"}';
    http.Response answer(String content, {bool cut = false}) => http.Response(
      jsonEncode(<String, Object>{
        'choices': <Object>[
          <String, Object>{
            if (cut) 'finish_reason': 'length',
            'message': <String, String>{'content': content},
          },
        ],
      }),
      200,
    );
    ModelClient clientWith(http.Response Function(String) reply) => ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      httpClient: MockClient(
        (http.Request request) async => reply(request.body),
      ),
    );

    test('asks again with half of the rules in each request', () async {
      int calls = 0;
      final ModelClient client = clientWith((String body) {
        calls++;
        return body.contains('## P1. t') && body.contains('## P2. t')
            ? answer('{"checks": [', cut: true)
            : answer('{"checks": [], "findings": [${findingFor(body)}]}');
      });

      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: twoRules,
        client: client,
      );

      expect(calls, 3);
      expect(result.accepted.map((Finding f) => f.rule), <String>['P1', 'P2']);
      expect(result.note, contains('with a part of the rules in each'));
    });

    test('cuts the rules when a small part is still too large', () async {
      final ModelClient client = clientWith(
        (String body) => body.contains('## P1. t') && body.contains('## P2. t')
            ? http.Response('too large', 413)
            : answer('{"checks": [], "findings": [${findingFor(body)}]}'),
      );

      final ReviewResult result = await review(
        diff: sampleDiff,
        rules: twoRules,
        client: client,
      );

      expect(result.accepted, hasLength(2));
      expect(result.note, contains('reviewed in 2 parts'));
    });
  });

  test(
    'refuses P5 on a Column in a file with no SingleChildScrollView',
    () async {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,1 +1,2 @@
 Widget a() => Padding(
+  child: Column(children: items),
diff --git a/lib/b.dart b/lib/b.dart
--- a/lib/b.dart
+++ b/lib/b.dart
@@ -1,1 +1,2 @@
 Widget b() => SingleChildScrollView(
+  child: Column(children: items),
''';
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
                        '{"rule": "P5", "file": "lib/a.dart", "line": 2, '
                        '"evidence": "child: Column(", "message": "m"}, '
                        '{"rule": "P5", "file": "lib/b.dart", "line": 2, '
                        '"evidence": "child: Column(", "message": "m"}]}',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final ReviewResult result = await review(
        diff: diff,
        rules: <Rule>[
          Rule(
            id: 'P5',
            title: 't',
            text:
                '## P5. t\n\n- **Remark line:** a list widget, or a `Column` or '
                '`Row` in a file with a `SingleChildScrollView`',
          ),
        ],
        client: client,
      );

      expect(result.accepted.single.file, 'lib/b.dart');
      expect(
        result.rejected.single.reason,
        'no SingleChildScrollView in the file',
      );
    },
  );

  test('refuses P1 in a method that no build() calls', () async {
    const String source = '''
class _AState extends State<A> {
  void load() {
    items.sort();
  }

  List<int> _sorted() {
    return items.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final List<int> all = items.toList()..sort();
    return Text(_sorted().join());
  }
}
''';
    final String diff = <String>[
      'diff --git a/lib/a.dart b/lib/a.dart',
      'new file mode 100644',
      '--- /dev/null',
      '+++ b/lib/a.dart',
      '@@ -0,0 +1,15 @@',
      for (final String line in source.trimRight().split('\n')) '+$line',
    ].join('\n');
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
                      '{"rule": "P1", "file": "lib/a.dart", "line": 3, '
                      '"evidence": "items.sort();", "message": "m"}, '
                      '{"rule": "P1", "file": "lib/a.dart", "line": 7, '
                      '"evidence": "items.toList()..sort();", "message": "m"}, '
                      '{"rule": "P1", "file": "lib/a.dart", "line": 12, '
                      '"evidence": "items.toList()..sort();", "message": "m"}'
                      ']}',
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final ReviewResult result = await review(
      diff: diff,
      rules: <Rule>[
        Rule(
          id: 'P1',
          title: 't',
          text:
              '## P1. t\n\n- **Remark line:** in `build()`, or in a method '
              'that a `build()` calls',
        ),
      ],
      client: client,
      readSource: (String path) => path == 'lib/a.dart' ? source : null,
    );

    expect(
      <int>[for (final Finding finding in result.accepted) finding.line],
      <int>[7, 12],
    );
    expect(result.rejected.single.finding.line, 3);
    expect(
      result.rejected.single.reason,
      'not in build(), nor in a method that a build() calls',
    );

    // The same remarks, when a build() of another file of the project, not
    // changed by the pull request, calls load().
    final ReviewResult withProject = await review(
      diff: diff,
      rules: <Rule>[
        Rule(
          id: 'P1',
          title: 't',
          text:
              '## P1. t\n\n- **Remark line:** in `build()`, or in a method '
              'that a `build()` calls',
        ),
      ],
      client: client,
      readSource: (String path) => switch (path) {
        'lib/a.dart' => source,
        'lib/b.dart' =>
          'class B extends StatelessWidget {\n'
              '  @override\n'
              '  Widget build(BuildContext context) {\n'
              '    a.load();\n'
              '    return const SizedBox();\n'
              '  }\n'
              '}\n',
        _ => null,
      },
      projectFiles: () => <String>['lib/a.dart', 'lib/b.dart'],
    );

    expect(withProject.accepted, hasLength(3));
  });

  test('moves P9 to the widget that does not read the animation', () async {
    const String badge = '''
return AnimatedBuilder(
  animation: _controller,
  builder: (BuildContext context, Widget? child) {
    return Opacity(
      opacity: _controller.value,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.primary),
        child: Text('NEW', style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  },
);''';
    const String pulse = '''
return AnimatedBuilder(
  animation: _pulse,
  child: const Icon(Icons.star),
  builder: (BuildContext context, Widget? child) =>
      Opacity(opacity: _pulse.value, child: child),
);''';
    String newFile(String path, String code) => <String>[
      'diff --git a/$path b/$path',
      'new file mode 100644',
      '--- /dev/null',
      '+++ b/$path',
      '@@ -0,0 +1,${code.split('\n').length} @@',
      for (final String line in code.split('\n')) '+$line',
    ].join('\n');
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
                      '{"rule": "P9", "file": "lib/badge.dart", "line": 4, '
                      '"evidence": "return Opacity(", "message": "m"}, '
                      '{"rule": "P9", "file": "lib/pulse.dart", "line": 5, '
                      '"evidence": "Opacity(opacity: _pulse.value", '
                      '"message": "m"}]}',
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
          '${newFile('lib/badge.dart', badge)}\n'
          '${newFile('lib/pulse.dart', pulse)}\n',
      rules: <Rule>[
        Rule(
          id: 'P9',
          title: 't',
          text:
              '## P9. t\n\n- **Remark place:** the outermost widget of the '
              'builder that reads neither the animation nor the value',
        ),
      ],
      client: client,
      readSource: (String path) => switch (path) {
        'lib/badge.dart' => badge,
        'lib/pulse.dart' => pulse,
        _ => null,
      },
    );

    expect(result.accepted.single.file, 'lib/badge.dart');
    expect(result.accepted.single.line, 6);
    expect(
      result.rejected.single.reason,
      'every widget of the builder reads the animation or the value, or is '
      'const',
    );
  });

  test('refuses MEM1 on an object that the file disposes', () {
    // Pull request #24: MEM1 on a line that uses a disposed controller.
    const String traps = '''
class _HighlightsState extends State<Highlights> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListView(controller: _scrollController);
}
''';
    // Pull request #8: the controller is never disposed.
    const String leak = '''
class _ReleasesViewState extends State<ReleasesView> {
  final ScrollController _scrollController = ScrollController();
}
''';
    expect(disposedOnLine(traps, 12), '_scrollController');
    expect(disposedOnLine(traps, 2), '_scrollController');
    expect(disposedOnLine(leak, 2), isNull);
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

    test('cuts between two files, not inside a file', () async {
      // Two new files of 40 lines; the first one starts with a scroll view
      // and ends with the list: the two must stay in the same request.
      String fileDiff(String name, String first, String last) => <String>[
        'diff --git a/lib/$name b/lib/$name',
        'new file mode 100644',
        '--- /dev/null',
        '+++ b/lib/$name',
        '@@ -0,0 +1,40 @@',
        for (int i = 0; i < 40; i++)
          i == 0
              ? '+$first'
              : i == 39
              ? '+$last'
              : '+// $name $i',
      ].join('\n');
      final String twoFiles =
          '${fileDiff('a.dart', '// scroll view', '// list')}\n'
          '${fileDiff('b.dart', '// b first', '// b last')}\n';
      final List<String> parts = <String>[];
      final ModelClient client = clientWith((String body) async {
        if (body.contains('scroll view') && body.contains('b first')) {
          return http.Response('too large', 413);
        }
        parts.add(body);
        return modelAnswer('{"checks": [], "findings": []}');
      });

      await review(diff: twoFiles, rules: rules, client: client);

      expect(parts, hasLength(2));
      expect(parts.first, allOf(contains('scroll view'), contains('// list')));
      expect(parts.last, allOf(contains('b first'), contains('b last')));
    });

    test('cuts one file between two hunks', () async {
      String hunk(int start, String first, String last) => <String>[
        '@@ -$start,0 +$start,30 @@',
        for (int i = 0; i < 30; i++)
          i == 0
              ? '+$first'
              : i == 29
              ? '+$last'
              : '+// line $i',
      ].join('\n');
      final String twoHunks =
          '${<String>['diff --git a/lib/c.dart b/lib/c.dart', '--- a/lib/c.dart', '+++ b/lib/c.dart'].join('\n')}\n'
          '${hunk(1, '// h1 first', '// h1 last')}\n'
          '${hunk(100, '// h2 first', '// h2 last')}\n';
      final List<String> parts = <String>[];
      final ModelClient client = clientWith((String body) async {
        if (body.contains('h1 first') && body.contains('h2 first')) {
          return http.Response('too large', 413);
        }
        parts.add(body);
        return modelAnswer('{"checks": [], "findings": []}');
      });

      await review(diff: twoHunks, rules: rules, client: client);

      expect(parts, hasLength(2));
      expect(parts.first, allOf(contains('h1 first'), contains('h1 last')));
      expect(parts.last, allOf(contains('h2 first'), contains('h2 last')));
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
