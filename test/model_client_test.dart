import 'dart:convert';

import 'package:flutter_review/flutter_review.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response answer(String content) => http.Response(
  jsonEncode(<String, Object>{
    'choices': <Object>[
      <String, Object>{
        'message': <String, String>{'content': content},
      },
    ],
  }),
  200,
);

ModelClient clientWith(MockClient http, {List<String>? models}) => ModelClient(
  provider: 'test-provider',
  baseUrl: 'https://example.com/v1/',
  models: models ?? <String>['test-model'],
  apiKey: 'test-key',
  httpClient: http,
  firstDelay: Duration.zero,
);

void main() {
  test('sends the key and returns the text of the answer', () async {
    late http.Request sent;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        sent = request;
        return answer('{"findings": []}');
      }),
    );

    final String text = await client.complete(system: 's', user: 'u');

    expect(text, '{"findings": []}');
    expect(sent.url.toString(), 'https://example.com/v1/chat/completions');
    expect(sent.headers['Authorization'], 'Bearer test-key');
  });

  test('tries again when the provider is busy', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        return calls < 3 ? http.Response('busy', 503) : answer('ok');
      }),
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(calls, 3);
  });

  test('stops after the last attempt', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        return http.Response('busy', 503);
      }),
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(isA<ModelException>()),
    );
    expect(calls, 3);
  });

  test('does not try again on other errors', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        return http.Response('bad request', 400);
      }),
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(isA<ModelException>()),
    );
    expect(calls, 1);
  });

  test('uses the next model when one stays busy', () async {
    final List<String> asked = <String>[];
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        final String model =
            (jsonDecode(request.body) as Map<String, Object?>)['model']!
                as String;
        asked.add(model);
        return model == 'busy-model'
            ? http.Response('busy', 503)
            : answer('ok');
      }),
      models: <String>['busy-model', 'free-model'],
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(client.answeredBy, 'free-model');
    expect(asked, <String>[
      'busy-model',
      'busy-model',
      'busy-model',
      'free-model',
    ]);
  });

  test('explains a refused key without trying again', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        return http.Response('bad key', 401);
      }),
      models: <String>['first', 'second'],
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(
        isA<ModelException>().having(
          (ModelException e) => e.message,
          'message',
          contains('refused by test-provider'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('skips a model that does not exist', () async {
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        final String model =
            (jsonDecode(request.body) as Map<String, Object?>)['model']!
                as String;
        return model == 'removed-model'
            ? http.Response('not found', 404)
            : answer('ok');
      }),
      models: <String>['removed-model', 'current-model'],
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(client.answeredBy, 'current-model');
  });

  test('drops a setting the model refuses, and sends again', () async {
    final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        sent.add(body);
        return body.containsKey('temperature')
            ? http.Response('Unsupported value: temperature', 400)
            : answer('ok');
      }),
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(sent, hasLength(2));
    expect(sent.last.containsKey('temperature'), isFalse);
    expect(sent.last.containsKey('response_format'), isTrue);
  });

  test(
    'finds the newest suitable model when the known ones are gone',
    () async {
      final List<String> asked = <String>[];
      final ModelClient client = ModelClient(
        provider: 'test-provider',
        baseUrl: 'https://example.com/v1/',
        models: <String>['gemini-3.8-flash'],
        apiKey: 'test-key',
        modelPattern: r'^gemini-\d+(\.\d+)?-flash$',
        firstDelay: Duration.zero,
        httpClient: MockClient((http.Request request) async {
          if (request.method == 'GET') {
            expect(request.url.path, '/v1/models');
            return http.Response(
              jsonEncode(<String, Object>{
                'data': <Object>[
                  <String, String>{'id': 'models/gemini-4.0-flash'},
                  <String, String>{'id': 'models/gemini-4.1-flash-preview'},
                  <String, String>{'id': 'models/gemini-3.9-flash'},
                  <String, String>{'id': 'models/gemini-4.0-flash-tts'},
                ],
              }),
              200,
            );
          }
          final String model =
              (jsonDecode(request.body) as Map<String, Object?>)['model']!
                  as String;
          asked.add(model);
          return model == 'gemini-3.8-flash'
              ? http.Response('not found', 404)
              : answer('ok');
        }),
      );

      expect(await client.complete(system: 's', user: 'u'), 'ok');
      expect(asked, <String>['gemini-3.8-flash', 'gemini-4.0-flash']);
      expect(client.answeredBy, 'gemini-4.0-flash');
      expect(client.answeredByDiscoveredModel, isTrue);
    },
  );

  test('says so when no suitable model is left', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['gemini-3.8-flash'],
      apiKey: 'test-key',
      modelPattern: r'^gemini-\d+(\.\d+)?-flash$',
      firstDelay: Duration.zero,
      httpClient: MockClient((http.Request request) async {
        if (request.method == 'GET') {
          return http.Response('{"data": []}', 200);
        }
        return http.Response('not found', 404);
      }),
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(
        isA<ModelException>().having(
          (ModelException e) => e.message,
          'message',
          contains('FLUTTER_REVIEW_MODEL'),
        ),
      ),
    );
  });

  test('explains a key that a provider refuses with HTTP 400', () async {
    final ModelClient client = clientWith(
      MockClient(
        (http.Request request) async => http.Response(
          '{"error": {"code": 400, "message": "Please pass a valid API key"}}',
          400,
        ),
      ),
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(
        isA<ModelException>().having(
          (ModelException e) => e.message,
          'message',
          contains('refused by test-provider'),
        ),
      ),
    );
  });

  test('sends again when an answer takes too long', () async {
    int calls = 0;
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      firstDelay: Duration.zero,
      requestTimeout: const Duration(milliseconds: 20),
      httpClient: MockClient((http.Request request) async {
        calls++;
        if (calls == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return answer('ok');
      }),
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(calls, 2);
  });

  test('reads how long the provider asks to wait', () {
    expect(
      parseRetryDelay(
        http.Response('', 429, headers: <String, String>{'retry-after': '7'}),
      ),
      const Duration(seconds: 7),
    );
    expect(
      parseRetryDelay(
        http.Response('{"details": [{"retryDelay": "32s"}]}', 429),
      ),
      const Duration(seconds: 32),
    );
    expect(parseRetryDelay(http.Response('busy', 503)), isNull);
  });

  test(
    'sends again without JSON mode when the provider refuses the JSON',
    () async {
      final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
      final ModelClient client = clientWith(
        MockClient((http.Request request) async {
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
          return sent.length == 1
              ? http.Response(
                  '{"error": {"code": "json_validate_failed"}}',
                  400,
                )
              : answer('ok');
        }),
      );

      expect(await client.complete(system: 's', user: 'u'), 'ok');
      expect(sent.first.containsKey('response_format'), isTrue);
      expect(sent.last.containsKey('response_format'), isFalse);
    },
  );

  test('skips at once a model whose quota is used up', () async {
    final List<String> asked = <String>[];
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        final String model =
            (jsonDecode(request.body) as Map<String, Object?>)['model']!
                as String;
        asked.add(model);
        return model == 'empty-model'
            ? http.Response('You exceeded your current quota', 429)
            : answer('ok');
      }),
      models: <String>['empty-model', 'free-model'],
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(asked, <String>['empty-model', 'free-model']);
  });

  test('stops when the whole call takes too long', () async {
    final ModelClient client = ModelClient(
      provider: 'test-provider',
      baseUrl: 'https://example.com/v1/',
      models: <String>['test-model'],
      apiKey: 'test-key',
      maxAttempts: 100,
      firstDelay: const Duration(milliseconds: 30),
      totalTimeout: const Duration(milliseconds: 100),
      httpClient: MockClient(
        (http.Request request) async => http.Response('busy', 503),
      ),
    );

    await expectLater(
      client.complete(system: 's', user: 'u'),
      throwsA(
        isA<ModelException>().having(
          (ModelException e) => e.message,
          'message',
          contains('No answer from test-provider within'),
        ),
      ),
    );
  });

  test('skips at once a model that asks to wait longer than allowed', () async {
    final List<String> asked = <String>[];
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        final String model =
            (jsonDecode(request.body) as Map<String, Object?>)['model']!
                as String;
        asked.add(model);
        return model == 'tired-model'
            ? http.Response(
                'limit reached',
                429,
                headers: <String, String>{'retry-after': '600'},
              )
            : answer('ok');
      }),
      models: <String>['tired-model', 'free-model'],
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(asked, <String>['tired-model', 'free-model']);
  });

  test('reads how many tokens the call used', () async {
    final ModelClient client = clientWith(
      MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{'content': 'ok'},
              },
            ],
            'usage': <String, int>{
              'prompt_tokens': 1200,
              'completion_tokens': 300,
            },
          }),
          200,
        ),
      ),
    );

    await client.complete(system: 's', user: 'u');

    expect(client.promptTokens, 1200);
    expect(client.answerTokens, 300);
  });

  test('tries again when the connection drops', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('Write failed');
        }
        return answer('ok');
      }),
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(calls, 2);
  });

  test('explains why the list of models cannot be read', () async {
    final ModelClient client = clientWith(
      MockClient((http.Request request) async => http.Response('no', 401)),
    );

    expect(await client.listModels(), isEmpty);
    await expectLater(
      client.fetchModels(),
      throwsA(
        isA<ModelException>().having(
          (ModelException e) => e.message,
          'message',
          contains('refused by test-provider (HTTP 401)'),
        ),
      ),
    );
  });

  test('tries again after an internal error of the provider', () async {
    int calls = 0;
    final ModelClient client = clientWith(
      MockClient((http.Request request) async {
        calls++;
        return calls == 1
            ? http.Response('{"error": {"code": 500}}', 500)
            : answer('ok');
      }),
    );

    expect(await client.complete(system: 's', user: 'u'), 'ok');
    expect(calls, 2);
  });
}
