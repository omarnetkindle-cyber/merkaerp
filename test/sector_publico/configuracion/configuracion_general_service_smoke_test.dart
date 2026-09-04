import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/configuracion/services/configuracion_general_service.dart';
import 'package:merka_erp/sector_publico/configuracion/services/matriz_visibilidad_service.dart';
import 'package:merka_erp/sector_publico/configuracion/services/selector_entidad_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('la configuración pública tolera valores legacy nulos', () async {
    await DatabaseHelper.resetForTests();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final entidadId = 'ENT-CONFIG-${DateTime.now().microsecondsSinceEpoch}';
    final configId = 'config-${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('entidades_territoriales', {
      'id': entidadId,
      'company_id': companyId,
      'nit': 'CONFIG-$companyId-${DateTime.now().microsecondsSinceEpoch}',
      'razon_social': 'Entidad de configuración',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await db.insert('configuracion_entidad', {
      'id': configId,
      'entidad_id': entidadId,
      'parametro': 'tipo_entidad',
      'valor': 'municipio',
      'fecha_actualizacion': DateTime.now().toIso8601String(),
      'actualizado_por': 'test',
      'tipo': null,
      'subtipo': null,
      'estado': 'activo',
      'vigente': 1,
    });

    final auditoria = AuditoriaService(db);
    final selector = SelectorEntidadService(
      db: db,
      auditoriaService: auditoria,
    );
    final service = ConfiguracionGeneralService(
      db: db,
      auditoriaService: auditoria,
      selectorEntidadService: selector,
      matrizVisibilidadService: MatrizVisibilidadService(
        db: db,
        auditoriaService: auditoria,
      ),
    );

    final config = await service.obtenerConfiguracionCompleta(
      entidadId: entidadId,
    );
    expect(config['entidad_id'], entidadId);
    final validacion = await service.validarConfiguracion(entidadId: entidadId);
    expect(validacion, contains('es_valida'));
    await DatabaseHelper.resetForTests();
  });
}
