import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/workspace/selector_modo_screen.dart';

void main() {
  group('Familia de producto fijada por licencia', () {
    test('la reconfiguración manual nunca tiene autoridad', () async {
      final result = await SelectorModoService.tieneAutoridadReconfiguracion(
        db: Object(),
        entidadId: 'ENT-001',
        usuarioId: 'admin',
      );
      expect(result, isFalse);
    });

    test('guardarModo falla de forma cerrada', () async {
      expect(
        () => SelectorModoService.guardarModo(
          database: Object(),
          entidadId: 'ENT-001',
          usuarioId: 'admin',
          modo: ModoOperacion.publica,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
