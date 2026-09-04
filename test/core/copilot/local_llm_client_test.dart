import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/copilot/copilot_models.dart';
import 'package:merka_erp/core/copilot/local_llm_client.dart';

void main() {
  test('falla cerrado si el endpoint no es local', () async {
    final client = LocalLlmClient();
    await expectLater(
      client.complete(
        configuration: LocalLlmConfiguration(
          enabled: true,
          endpoint: Uri.parse('https://example.com/v1/chat/completions'),
          model: 'test',
        ),
        prompt: 'ventas hoy',
        history: const [],
        tools: const [],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('proveedor desactivado no hace ninguna llamada', () async {
    final result = await LocalLlmClient().complete(
      configuration: LocalLlmConfiguration(
        enabled: false,
        endpoint: Uri.parse('http://127.0.0.1:8080/v1/chat/completions'),
        model: 'test',
      ),
      prompt: 'ventas hoy',
      history: const [],
      tools: const [],
    );
    expect(result, isNull);
  });

  test('interpreta tool calling estructurado de llama-server local', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handling = server.first.then((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join());
      expect(payload['tools'], isNotEmpty);
      expect(payload['temperature'], 0.1);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'type': 'function',
                    'function': {'name': 'sales_today', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        }),
      );
      await request.response.close();
    });

    final result = await LocalLlmClient().complete(
      configuration: LocalLlmConfiguration(
        enabled: true,
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/chat/completions',
        ),
        model: 'modelo-prueba',
      ),
      prompt: 'cuanto vendimos hoy',
      history: const [
        CopilotConversationTurn(role: 'assistant', content: 'Hola'),
      ],
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'sales_today'},
        },
      ],
    );

    await handling;
    await server.close(force: true);
    expect(result?.toolCall?.name, 'sales_today');
    expect(result?.toolCall?.arguments, isEmpty);
  });
}
