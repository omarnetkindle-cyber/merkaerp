import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/activos/database/schema_activos.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/depreciacion_job_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entidadId = 'ENT-DEP-001';
const _usuarioId = 'USR-CONTADOR-DEP';

late Database db;
late DepreciacionJobService service;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaActivos.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await db.insert('entidades_territoriales', {
      'id': _entidadId,
      'nit': '901000003-1',
      'razon_social': 'Entidad depreciacion de prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime(2026, 1, 1).toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await db.insert('configuracion_depreciacion', {
      'id': 'CONF-DEP-001',
      'entidad_id': _entidadId,
      'tipo_activo': 'equipo_computo',
      'vida_util_anios': 5,
      'metodo_depreciacion': 'linea_recta',
      'porcentaje_depreciacion': 20.0,
    });
    await db.insert('activos_estado', {
      'id': 'ACT-DEP-001',
      'entidad_id': _entidadId,
      'numero_inventario': 'INV-DEP-001',
      'nombre_activo': 'Equipo de prueba',
      'tipo_activo': 'equipo_computo',
      'marca': 'Merka',
      'modelo': 'T1',
      'serie': 'SER-001',
      'valor_adquisicion': 120000,
      'valor_libros': 120000,
      'valor_neto': 120000,
      'fecha_adquisicion': '2026-01-01',
      'fecha_puesta_en_marcha': '2026-01-01',
      'vida_util_anios': 5,
      'valor_residual': 0,
      'depreciacion_acumulada': 0,
      'estado': 'activo',
    });
    service = DepreciacionJobService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );
  });

  tearDown(() => db.close());

  test(
    'ejecuta el job mensual, actualiza activo y genera asiento NICSP 17',
    () async {
      final resultado = await service.ejecutarDepreciacionMensual(
        entidadId: _entidadId,
        usuarioId: _usuarioId,
        periodo: '2026-07',
      );
      expect(resultado['total_activos'], 1);
      expect(resultado['total_depreciacion'], 2000);
      final activo = (await db.query('activos_estado')).single;
      expect(activo['depreciacion_acumulada'], 2000);
      expect(activo['valor_neto'], 118000);
      final asiento = (await db.query('asientos_contables_sp')).single;
      expect(asiento['total_debito'], 2000);
      expect(asiento['total_credito'], 2000);
      final detalles = await db.query(
        'detalles_asientos',
        where: 'asiento_id = ?',
        whereArgs: [asiento['id']],
      );
      expect(
        detalles.map((d) => d['cuenta_codigo']),
        containsAll(['620101', '160401']),
      );
      expect(
        await service.jobEjecutadoParaPeriodo(
          entidadId: _entidadId,
          periodo: '2026-07',
        ),
        isTrue,
      );
    },
  );
}
