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
    expect(calls, 4);
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
}
