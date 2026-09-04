import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/support/support_bundle_service.dart';
import 'package:merka_erp/document_management/application/document_management_service.dart';
import 'package:merka_erp/integrations/application/integration_settings_service.dart';
import 'package:merka_erp/licensing/domain/product_family.dart';
import 'package:merka_erp/sector_publico/planeacion/pages/planeacion_page.dart';
import 'package:merka_erp/sector_publico/security/roles_permisos_service.dart';

void main() {
  test('contratos que bloquearon 1.2.1+5 permanecen compilables', () {
    expect(IntegrationSettingsService.instance, isNotNull);
    expect(SupportBundleService.instance, isNotNull);

    const page = PlaneacionPage(
      entidadId: 'entidad-test',
      usuarioId: 'usuario-test',
    );
    expect(page.entidadId, 'entidad-test');

    final createDocumentType =
        DocumentManagementService.instance.createDocumentType;
    expect(createDocumentType, isNotNull);

    expect(ProductFamily.commercial.storageValue, 'commercial');
    expect(ProductFamily.publicSector.storageValue, 'public');

    for (final permiso in Permiso.values) {
      expect(
        RolesPermisosService.obtenerDescripcionPermiso(permiso).trim(),
        isNotEmpty,
        reason: 'Todo permiso debe tener descripción legible: $permiso',
      );
    }
  });
}
