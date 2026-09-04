import 'package:merka_erp/core/security/action_permission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionService', () {
    final service = PermissionService.instance;

    test('operador puede crear compras pero no anularlas', () {
      expect(
        service.can(
          role: 'operador',
          moduleId: 'purchases',
          action: AppAction.create,
        ),
        isTrue,
      );
      expect(
        service.can(
          role: 'operador',
          moduleId: 'purchases',
          action: AppAction.cancel,
        ),
        isFalse,
      );
    });

    test('cajero puede vender y cerrar caja', () {
      expect(
        service.can(
          role: 'cajero',
          moduleId: 'sales',
          action: AppAction.create,
        ),
        isTrue,
      );
      expect(
        service.can(
          role: 'cajero',
          moduleId: 'cash_closings',
          action: AppAction.close,
        ),
        isTrue,
      );
    });

    test('administrador conserva acceso total', () {
      expect(
        service.can(
          role: 'administrador',
          moduleId: 'settings',
          action: AppAction.configure,
        ),
        isTrue,
      );
    });
  });
}
