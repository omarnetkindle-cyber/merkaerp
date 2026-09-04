import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/app_bootstrap.dart';

void main() {
  group('AppBootstrap', () {
    test('falla cerrado cuando la base no puede inicializarse', () async {
      final result = await AppBootstrap.initialize(
        configureDatabase: () async {
          throw StateError('fallo simulado');
        },
        preloadTheme: () async {},
        startServices: () async {},
      );

      expect(result.ready, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });
}
