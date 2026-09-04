import 'dart:convert';
import 'dart:io';

import 'copilot_models.dart';

class LocalLlmConfiguration {
  const LocalLlmConfiguration({
    required this.enabled,
    required this.endpoint,
    required this.model,
    this.timeout = const Duration(seconds: 25),
  });

  final bool enabled;
  final Uri endpoint;
  final String model;
  final Duration timeout;

  bool get isLoopback =>
      endpoint.host == '127.0.0.1' || endpoint.host == 'localhost';
}

class LocalLlmResult {
  const LocalLlmResult({this.text, this.toolCall});

  final String? text;
  final CopilotToolCall? toolCall;
}

class LocalLlmClient {
  LocalLlmClient({HttpClient? httpClient}) : _httpClient = httpClient;

  final HttpClient? _httpClient;

  Future<LocalLlmResult?> complete({
    required LocalLlmConfiguration configuration,
    required String prompt,
    required List<CopilotConversationTurn> history,
    required List<Map<String, Object?>> tools,
  }) async {
    if (!configuration.enabled) return null;
    if (!configuration.isLoopback) {
      throw StateError(
        'El proveedor local solo puede conectarse a localhost/127.0.0.1.',
      );
    }

    final client = _httpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(configuration.endpoint);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': configuration.model,
          'temperature': 0.1,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Eres el intérprete local de MerkaERP. No inventes datos, '
                  'no escribas SQL y no afirmes que una acción fue ejecutada. '
                  'Usa únicamente las herramientas disponibles. Si ninguna '
                  'aplica, explica brevemente la limitación en español.',
            },
            ...history.map((turn) => turn.toJson()),
            {'role': 'user', 'content': prompt},
          ],
          'tools': tools,
          'tool_choice': 'auto',
        }),
      );
      final response = await request.close().timeout(configuration.timeout);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'El modelo local respondió HTTP ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        return null;
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map) return null;
      final toolCalls = message['tool_calls'];
      if (toolCalls is List && toolCalls.isNotEmpty && toolCalls.first is Map) {
        final function = (toolCalls.first as Map)['function'];
        if (function is Map) {
          return LocalLlmResult(
            toolCall: CopilotToolCall.fromJson(
              Map<String, Object?>.from(function),
            ),
          );
        }
      }
      return LocalLlmResult(text: message['content']?.toString().trim());
    } finally {
      if (_httpClient == null) client.close(force: true);
    }
  }
}
