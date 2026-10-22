import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the model provider answers with an error.
class ModelException implements Exception {
  ModelException(this.message);

  final String message;

  @override
  String toString() => 'ModelException: $message';
}

/// Calls any provider that offers an OpenAI-compatible chat API
/// (Gemini, Groq, OpenAI, and others).
///
/// Only three settings change from one provider to another: the base URL, the
/// model name and the API key.
class ModelClient {
  ModelClient({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String model;
  final String apiKey;
  final http.Client _http;

  /// Sends the two messages and returns the text of the answer.
  Future<String> complete({
    required String system,
    required String user,
  }) async {
    final Uri uri = Uri.parse(
      baseUrl.endsWith('/')
          ? '${baseUrl}chat/completions'
          : '$baseUrl/chat/completions',
    );
    final http.Response response = await _http.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object>{
        'model': model,
        'temperature': 0,
        'response_format': <String, String>{'type': 'json_object'},
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': system},
          <String, String>{'role': 'user', 'content': user},
        ],
      }),
    );

    final String body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw ModelException('HTTP ${response.statusCode}: $body');
    }

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
    throw ModelException('Unexpected answer: $body');
  }

  void close() => _http.close();
}
