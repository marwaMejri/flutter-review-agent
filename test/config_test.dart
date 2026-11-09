import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  test('uses the preset of a known provider', () {
    final ReviewConfig config = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'Gemini',
    });

    expect(config.provider, 'gemini');
    expect(config.baseUrl, providerPresets['gemini']!.baseUrl);
    expect(config.models, providerPresets['gemini']!.models);
  });

  test('lets the project choose its own models for a known provider', () {
    final ReviewConfig config = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'gemini',
      modelVariable: 'model-a, model-b',
    });

    expect(config.models, <String>['model-a', 'model-b']);
  });

  test('accepts any provider with an address and models', () {
    final ReviewConfig config = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      baseUrlVariable: 'https://example.com/v1/',
      modelVariable: 'model-a',
    });

    expect(config.provider, 'custom');
    expect(config.baseUrl, 'https://example.com/v1/');
  });

  test('never guesses the provider', () {
    expect(
      () => resolveConfig(<String, String>{apiKeyVariable: 'key'}),
      throwsA(
        isA<ConfigException>().having(
          (ConfigException e) => e.message,
          'message',
          contains('$providerVariable is not set'),
        ),
      ),
    );
  });

  test('refuses an unknown provider without an address', () {
    expect(
      () => resolveConfig(<String, String>{
        apiKeyVariable: 'key',
        providerVariable: 'unknown',
      }),
      throwsA(isA<ConfigException>()),
    );
  });

  test('requires a key', () {
    expect(
      () => resolveConfig(<String, String>{providerVariable: 'gemini'}),
      throwsA(isA<ConfigException>()),
    );
  });

  test('knows which models were measured', () {
    final ReviewConfig gemini = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'gemini',
      modelVariable: 'gemini-3.5-flash-lite',
    });
    final ReviewConfig groq = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'groq',
    });
    final ReviewConfig openai = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'openai',
    });

    expect(gemini.isMeasured('gemini-3.5-flash-lite'), isTrue);
    expect(gemini.isMeasured('gemini-3.8-flash'), isFalse);
    expect(groq.isMeasured('openai/gpt-oss-120b'), isTrue);
    expect(groq.isMeasured('openai/gpt-oss-20b'), isFalse);
    expect(openai.isMeasured('gpt-5.6-terra'), isFalse);
    expect(gemini.isMeasured(null), isFalse);
  });

  test('measures nothing at another address', () {
    final ReviewConfig config = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'gemini',
      baseUrlVariable: 'https://example.com/v1/',
      modelVariable: 'gemini-3.5-flash-lite',
    });

    expect(config.isMeasured('gemini-3.5-flash-lite'), isFalse);
  });

  test('reads the longest time for one review', () {
    final Map<String, String> settings = <String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'groq',
    };

    expect(resolveConfig(settings).timeout, defaultReviewTimeout);
    expect(
      resolveConfig(<String, String>{
        ...settings,
        timeoutVariable: '60',
      }).timeout,
      const Duration(seconds: 60),
    );
    expect(
      () => resolveConfig(<String, String>{...settings, timeoutVariable: 'x'}),
      throwsA(isA<ConfigException>()),
    );
  });
}
