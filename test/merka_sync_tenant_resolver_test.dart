import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/licensing/domain/product_family.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/sync/application/merka_sync_tenant_resolver.dart';

void main() {
  test('tenant remoto usa clientId de la licencia cuando existe', () {
    final license = LicenciaInfo(
      uuid: 'license-1',
      plan: TipoPlan.profesional,
      estado: EstadoLicencia.activa,
      fechaExpiracion: DateTime.utc(2027),
      modulosHabilitados: const ['pos'],
      productFamily: ProductFamily.commercial,
      clientId: 'cliente-123',
    );

    expect(resolveMerkaSyncTenantKind(license), 'commercial');
    expect(resolveMerkaSyncTenantId(license, 1), 'client:cliente-123');
  });

  test('tenant remoto cae a company local si no hay clientId', () {
    expect(resolveMerkaSyncTenantKind(null), 'commercial');
    expect(resolveMerkaSyncTenantId(null, 7), 'company:7');
  });
}
