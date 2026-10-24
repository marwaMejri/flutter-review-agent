/// Names of the settings, read from environment variables.
///
/// In GitHub Actions or GitLab CI, the project maps its own secret to
/// [apiKeyVariable], whatever the secret is called.
const String apiKeyVariable = 'FLUTTER_REVIEW_API_KEY';
const String providerVariable = 'FLUTTER_REVIEW_PROVIDER';
const String baseUrlVariable = 'FLUTTER_REVIEW_BASE_URL';
const String modelVariable = 'FLUTTER_REVIEW_MODEL';
const String timeoutVariable = 'FLUTTER_REVIEW_TIMEOUT';

/// Longest time for one review when [timeoutVariable] is not set.
const Duration defaultReviewTimeout = Duration(minutes: 3);

/// What the agent knows about a provider.
class ProviderPreset {
  const ProviderPreset({
    required this.baseUrl,
    required this.models,
    required this.modelPattern,
    required this.tested,
  });

  /// The address of its OpenAI-compatible API. It rarely changes.
  final String baseUrl;

  /// Models to try first, in order of preference.
  final List<String> models;

  /// How to recognise a suitable model in the provider's list, when none of
  /// [models] can answer (for example after the provider removed them).
  final String modelPattern;

  /// Whether the preset was measured on the evaluation cases.
  final bool tested;
}

/// Providers with a preset.
const Map<String, ProviderPreset> providerPresets = <String, ProviderPreset>{
  // https://ai.google.dev/gemini-api/docs/openai
  'gemini': ProviderPreset(
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
    models: <String>[
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-3.5-flash',
    ],
    // Stable Flash models only: no preview, lite, image, audio or live model.
    modelPattern: r'^gemini-\d+(\.\d+)?-flash$',
    tested: true,
  ),
  // https://console.groq.com/docs/models (production models). The Llama
  // models were shut down on 16 August 2026, except for Enterprise plans:
  // https://console.groq.com/docs/deprecations
  'groq': ProviderPreset(
    baseUrl: 'https://api.groq.com/openai/v1/',
    models: <String>['openai/gpt-oss-120b', 'openai/gpt-oss-20b'],
    // GPT-OSS chat models only: not the safeguard (moderation) models.
    modelPattern: r'^openai/gpt-oss-\d+b$',
    tested: false,
  ),
  // https://developers.openai.com/api/docs/models/gpt-5.6-terra
  'openai': ProviderPreset(
    baseUrl: 'https://api.openai.com/v1/',
    models: <String>['gpt-5.6-terra'],
    modelPattern: r'^gpt-\d+(\.\d+)?-(terra|mini)$',
    tested: false,
  ),
};

/// Thrown when the settings are missing or contradict each other.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The settings the agent runs with.
class ReviewConfig {
  ReviewConfig({
    required this.provider,
    required this.baseUrl,
    required this.models,
    required this.apiKey,
    this.modelPattern,
    this.tested = false,
    this.timeout = defaultReviewTimeout,
  });

  /// The provider name, used in messages. `custom` when none is given.
  final String provider;
  final String baseUrl;
  final List<String> models;
  final String apiKey;

  /// See [ProviderPreset.modelPattern]. Null for a custom provider.
  final String? modelPattern;

  /// Whether this provider was measured on the evaluation cases.
  final bool tested;

  /// Longest time for one review, waits for a busy provider included.
  final Duration timeout;
}

/// Builds the settings from environment variables (or command options with the
/// same names).
///
/// The agent never guesses the provider: a key sent to the wrong provider
/// would only fail later, with a confusing error.
ReviewConfig resolveConfig(Map<String, String> settings) {
  String? read(String name) {
    final String? value = settings[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final String? apiKey = read(apiKeyVariable);
  final String? provider = read(providerVariable)?.toLowerCase();
  final String? baseUrl = read(baseUrlVariable);
  final List<String>? models = read(modelVariable)
      ?.split(',')
      .map((String name) => name.trim())
      .where((String name) => name.isNotEmpty)
      .toList();

  if (apiKey == null) {
    throw ConfigException('$apiKeyVariable is not set.');
  }

  final String? timeoutText = read(timeoutVariable);
  final int? timeoutSeconds = timeoutText == null
      ? null
      : int.tryParse(timeoutText);
  if (timeoutText != null && (timeoutSeconds == null || timeoutSeconds <= 0)) {
    throw ConfigException(
      '$timeoutVariable must be a number of seconds, for example 180.',
    );
  }
  final Duration timeout = timeoutSeconds == null
      ? defaultReviewTimeout
      : Duration(seconds: timeoutSeconds);

  final ProviderPreset? preset = provider == null
      ? null
      : providerPresets[provider];

  if (preset != null) {
    return ReviewConfig(
      provider: provider!,
      baseUrl: baseUrl ?? preset.baseUrl,
      models: models ?? preset.models,
      apiKey: apiKey,
      modelPattern: preset.modelPattern,
      tested: preset.tested && models == null && baseUrl == null,
      timeout: timeout,
    );
  }

  if (baseUrl != null && models != null && models.isNotEmpty) {
    return ReviewConfig(
      provider: provider ?? 'custom',
      baseUrl: baseUrl,
      models: models,
      apiKey: apiKey,
      timeout: timeout,
    );
  }

  final String known = providerPresets.keys.join(', ');
  throw ConfigException(
    provider == null
        ? '$providerVariable is not set. Set it to one of: $known. '
              'For another provider, set $baseUrlVariable and $modelVariable.'
        : 'No preset for the provider "$provider". Known providers: $known. '
              'For another provider, set $baseUrlVariable and $modelVariable.',
  );
}
