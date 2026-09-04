import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/configuracion/services/configuracion_general_service.dart';
import 'package:merka_erp/sector_publico/configuracion/services/matriz_visibilidad_service.dart';
import 'package:merka_erp/sector_publico/configuracion/services/selector_entidad_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'carga configuracion sin excepciones en una entidad sin configurar',
    () async {
      final auditoria = AuditoriaService(db);
      final selector = SelectorEntidadService(
        db: db,
        auditoriaService: auditoria,
      );
      final matriz = MatrizVisibilidadService(
        db: db,
        auditoriaService: auditoria,
      );
      final service = ConfiguracionGeneralService(
        db: db,
        auditoriaService: auditoria,
        selectorEntidadService: selector,
        matrizVisibilidadService: matriz,
      );

      final configuracion = await service.obtenerConfiguracionCompleta(
        entidadId: 'ENT-001',
      );
      final validacion = await service.validarConfiguracion(
        entidadId: 'ENT-001',
      );

      expect(configuracion['configuracion_tipo'], isNull);
      expect(configuracion['configuracion_visibilidad'], isNull);
      expect(configuracion['configuraciones_adicionales'], isEmpty);
      expect(validacion['es_valida'], isFalse);
    },
  );
}
