import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/services/control_center_endpoint.dart';

void main() {
  group('ControlCenterEndpoint', () {
    test('normaliza un endpoint con slash final', () {
      expect(
        ControlCenterEndpoint.normalize('https://example.com/'),
        'https://example.com',
      );
    });

    test('quita el sufijo api/v1 si ya viene en la configuración', () {
      expect(
        ControlCenterEndpoint.normalize('https://example.com/api/v1'),
        'https://example.com',
      );
    });

    test('construye la ruta de activación sin duplicar api/v1', () {
      expect(
        ControlCenterEndpoint.activationUrl('https://example.com/api/v1'),
        'https://example.com/api/v1/licenses/activate',
      );
    });


    test('rechaza HTTP externo para no exponer tokens', () {
      expect(
        () => ControlCenterEndpoint.normalize('http://example.com'),
        throwsFormatException,
      );
    });

    test('permite HTTP únicamente en localhost para desarrollo', () {
      expect(
        ControlCenterEndpoint.normalize('http://127.0.0.1:3000/api/v1'),
        'http://127.0.0.1:3000',
      );
    });

    test('rechaza credenciales embebidas en la URL', () {
      expect(
        () => ControlCenterEndpoint.normalize('https://user:pass@example.com'),
        throwsFormatException,
      );
    });
  });
}
