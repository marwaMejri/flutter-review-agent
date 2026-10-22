import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  test('uses the preset of a known provider', () {
    final ReviewConfig config = resolveConfig(<String, String>{
      apiKeyVariable: 'key',
      providerVariable: 'Gemini',
    });

    expect(config.provider, 'gemini');
    expect(config.tested, isTrue);
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

  test('marks the experimental presets as not measured', () {
    for (final String provider in <String>['groq', 'openai']) {
      final ReviewConfig config = resolveConfig(<String, String>{
        apiKeyVariable: 'key',
        providerVariable: provider,
      });

      expect(config.tested, isFalse, reason: provider);
      expect(config.models, isNotEmpty, reason: provider);
    }
  });
}
