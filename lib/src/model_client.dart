import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the model provider cannot give an answer.
class ModelException implements Exception {
  ModelException(this.message);

  final String message;

  @override
  String toString() => 'ModelException: $message';
}

/// Calls any provider that offers an OpenAI-compatible chat API
/// (Gemini, Groq, OpenAI, and others).
///
/// For every provider:
/// - a busy model is tried again a few times, then the next model is used;
/// - a model that does not exist is skipped;
/// - when none of [models] can answer, the provider's own list of models is
///   read, and the newest model that matches [modelPattern] is used;
/// - a setting the model refuses (`temperature`, `response_format`) is
///   removed and the request is sent again.
class ModelClient {
  ModelClient({
    required this.provider,
    required this.baseUrl,
    required this.models,
    required this.apiKey,
    this.modelPattern,
    http.Client? httpClient,
    this.maxAttempts = 4,
    this.firstDelay = const Duration(seconds: 2),
    this.requestTimeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client();

  /// The provider name, used in messages.
  final String provider;
  final String baseUrl;
  final List<String> models;
  final String apiKey;

  /// How to recognise a suitable model in the provider's list. When null, the
  /// list is never read.
  final String? modelPattern;

  final http.Client _http;

  /// How many times a request is sent to one model when it is busy.
  final int maxAttempts;

  /// Wait before the second attempt. It doubles after each attempt.
  final Duration firstDelay;

  /// Longest wait for one answer. A request that takes longer counts as a
  /// busy attempt, so a stuck connection never blocks the review.
  final Duration requestTimeout;

  /// The model that gave the last answer.
  String? answeredBy;

  /// Whether that model was found in the provider's list, and not one of
  /// [models]. Such a model was not measured by the evaluation.
  bool answeredByDiscoveredModel = false;

  /// "Busy, try again later": too many requests (429) and service
  /// unavailable (503).
  static const Set<int> _busyStatus = <int>{429, 503};

  /// "The key is refused": unauthorized (401) and forbidden (403).
  static const Set<int> _refusedStatus = <int>{401, 403};

  /// Settings that some models refuse. They are removed when refused.
  static const List<String> _optionalSettings = <String>[
    'temperature',
    'response_format',
  ];

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  Uri _endpoint(String path) =>
      Uri.parse(baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl/$path');

  /// Sends the two messages and returns the text of the answer.
  Future<String> complete({
    required String system,
    required String user,
  }) async {
    final List<String> skipped = <String>[];
    final Set<String> tried = <String>{};

    Future<String?> tryModel(String model) async {
      tried.add(model);
      try {
        final String text = await _completeWith(model, system, user);
        answeredBy = model;
        return text;
      } on _SkipModelException catch (error) {
        skipped.add('$model: ${error.reason}');
        return null;
      }
    }

    for (final String model in models) {
      final String? text = await tryModel(model);
      if (text != null) {
        return text;
      }
    }

    if (modelPattern != null) {
      final RegExp pattern = RegExp(modelPattern!);
      final List<String> discovered =
          (await listModels())
              .where((String id) => pattern.hasMatch(id) && !tried.contains(id))
              .toList()
            ..sort(_newestFirst);
      if (discovered.isEmpty) {
        skipped.add('no other suitable model in the list of $provider');
      }
      for (final String model in discovered) {
        final String? text = await tryModel(model);
        if (text != null) {
          answeredByDiscoveredModel = true;
          return text;
        }
      }
    }

    throw ModelException(
      'No model of $provider could answer (${skipped.join('; ')}). '
      'Try again later, or choose a model with FLUTTER_REVIEW_MODEL.',
    );
  }

  /// Reads the provider's list of models: `GET {baseUrl}/models`.
  ///
  /// Returns an empty list when the list cannot be read.
  Future<List<String>> listModels() async {
    final http.Response response;
    try {
      response = await _http
          .get(_endpoint('models'), headers: _headers)
          .timeout(requestTimeout);
    } on TimeoutException {
      return <String>[];
    } on http.ClientException {
      return <String>[];
    }
    if (response.statusCode != 200) {
      return <String>[];
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, Object?> || decoded['data'] is! List<Object?>) {
      return <String>[];
    }
    return <String>[
      for (final Object? item in decoded['data']! as List<Object?>)
        if (item is Map<String, Object?> && item['id'] is String)
          // Gemini writes "models/gemini-3.8-flash".
          (item['id']! as String).replaceFirst('models/', ''),
    ];
  }

  Future<String> _completeWith(String model, String system, String user) async {
    final Map<String, Object> request = <String, Object>{
      'model': model,
      'temperature': 0,
      'response_format': <String, String>{'type': 'json_object'},
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': system},
        <String, String>{'role': 'user', 'content': user},
      ],
    };

    Duration delay = firstDelay;
    int busyAttempts = 0;
    while (true) {
      final http.Response response;
      try {
        response = await _http
            .post(
              _endpoint('chat/completions'),
              headers: _headers,
              body: jsonEncode(request),
            )
            .timeout(requestTimeout);
      } on TimeoutException {
        busyAttempts++;
        if (busyAttempts >= maxAttempts) {
          throw _SkipModelException(
            'no answer within ${requestTimeout.inSeconds} s, '
            '$busyAttempts attempts',
          );
        }
        continue;
      } on http.ClientException catch (error) {
        throw ModelException('Cannot reach $provider: ${error.message}');
      }
      final String body = utf8.decode(response.bodyBytes);
      final int status = response.statusCode;

      if (status == 200) {
        return _readContent(body);
      }
      if (_refusedStatus.contains(status) || _isKeyError(status, body)) {
        throw ModelException(
          'The key was refused by $provider (HTTP $status). '
          'Check that the key comes from $provider.',
        );
      }
      if (status == 404) {
        throw _SkipModelException('model not found (HTTP 404)');
      }
      if (status == 400) {
        final String? refused = _refusedSetting(request, body);
        if (refused != null) {
          request.remove(refused);
          continue;
        }
        throw ModelException('HTTP 400 from $provider ($model): $body');
      }
      if (!_busyStatus.contains(status)) {
        throw ModelException('HTTP $status from $provider ($model): $body');
      }
      busyAttempts++;
      if (busyAttempts >= maxAttempts) {
        throw _SkipModelException(
          'busy, HTTP $status after $busyAttempts attempts',
        );
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  /// Some providers answer 400 for a key that is not valid: Gemini says
  /// "Please pass a valid API key".
  static bool _isKeyError(int status, String body) {
    final String text = body.toLowerCase();
    return status == 400 &&
        (text.contains('api key') || text.contains('api_key'));
  }

  /// The optional setting named in an error message, if it was sent.
  static String? _refusedSetting(Map<String, Object> request, String body) {
    for (final String setting in _optionalSettings) {
      if (request.containsKey(setting) && body.contains(setting)) {
        return setting;
      }
    }
    return null;
  }

  /// Reads the text of the answer, in the OpenAI format:
  /// `choices[0].message.content`.
  String _readContent(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map<String, Object?> &&
        decoded['choices'] is List<Object?> &&
        (decoded['choices']! as List<Object?>).isNotEmpty) {
      final Object? choice = (decoded['choices']! as List<Object?>).first;
      if (choice is Map<String, Object?> &&
          choice['message'] is Map<String, Object?>) {
        final Object? content =
            (choice['message']! as Map<String, Object?>)['content'];
        if (content is String) {
          return content;
        }
      }
    }
    throw ModelException('Unexpected answer from $provider: $body');
  }

  void close() => _http.close();
}

/// Sorts model names so that the highest version numbers come first:
/// `gemini-4.0-flash` before `gemini-3.8-flash`.
int _newestFirst(String a, String b) {
  final List<double> left = _versionNumbers(a);
  final List<double> right = _versionNumbers(b);
  for (int i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) {
      return right[i].compareTo(left[i]);
    }
  }
  return right.length.compareTo(left.length);
}

List<double> _versionNumbers(String name) => <double>[
  for (final Match match in RegExp(r'\d+(\.\d+)?').allMatches(name))
    double.parse(match.group(0)!),
];

/// A model that cannot answer now: the next model is tried.
class _SkipModelException implements Exception {
  _SkipModelException(this.reason);

  final String reason;
}
