// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/siif/services/siif_service.dart';
import 'package:merka_erp/sector_publico/siif/database/schema_siif.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  late Database db;
  late SIIFService siifService;
  late AuditoriaService auditoriaService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS entidades_territoriales (
            id TEXT PRIMARY KEY,
            nit TEXT NOT NULL,
            razon_social TEXT NOT NULL,
            tipo_entidad TEXT NOT NULL,
            fecha_creacion TEXT NOT NULL,
            plan_cuentas_cgc TEXT NOT NULL,
            configuracion_normativa TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS registro_auditoria (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            usuario_id TEXT NOT NULL,
            tipo_evento TEXT NOT NULL,
            modulo TEXT NOT NULL,
            accion TEXT NOT NULL,
            fecha_hora TEXT NOT NULL,
            valor_anterior TEXT NOT NULL,
            valor_nuevo TEXT NOT NULL,
            referencia_id TEXT NOT NULL,
            hash_integridad TEXT NOT NULL
          )
        ''');
        await SchemaPresupuesto.crearTablas(db);
        await SchemaSIIF.crearTablas(db);
        await db.execute('''
          CREATE TABLE IF NOT EXISTS auditoria_registros (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            usuario_id TEXT NOT NULL,
            usuario_nombre TEXT,
            ip_direccion TEXT,
            fecha_hora TEXT NOT NULL,
            tipo_evento TEXT NOT NULL,
            modulo TEXT NOT NULL,
            accion TEXT NOT NULL,
            valor_anterior TEXT NOT NULL,
            valor_nuevo TEXT NOT NULL,
            hash_anterior TEXT,
            hash_actual TEXT NOT NULL,
            referencia_id TEXT,
            observaciones TEXT,
            archivado INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS funcionarios_entidad (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            usuario_id TEXT,
            cargo_clave TEXT NOT NULL,
            nombre_completo TEXT NOT NULL,
            identificacion TEXT NOT NULL,
            tarjeta_profesional TEXT,
            telefono TEXT NOT NULL,
            email TEXT NOT NULL,
            direccion TEXT NOT NULL,
            UNIQUE(entidad_id, cargo_clave)
          )
        ''');
        await db.insert('funcionarios_entidad', {
          'id': 'FUNC-SIIF-01',
          'entidad_id': 'ENT-SIIF-TEST',
          'usuario_id': 'USR-SIIF-01',
          'cargo_clave': 'jefeControlInterno',
          'nombre_completo': 'Jefe de Control Interno SIIF',
          'identificacion': '1003',
          'telefono': '',
          'email': '',
          'direccion': '',
        });
      },
    );
    auditoriaService = AuditoriaService(db);
    siifService = SIIFService(db: db, auditoriaService: auditoriaService);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'SIIFService genera reporte presupuestal mensual y exporta a plano',
    () async {
      final rep = await siifService.generarReportePresupuestoMensual(
        entidadId: 'ENT-SIIF-TEST',
        usuarioId: 'USR-SIIF-01',
        vigencia: '2026',
        mes: 1,
      );

      expect(rep.id, isNotEmpty);
      expect(rep.vigencia, equals('2026'));
      expect(rep.mes, equals(1));

      final plano = await siifService.exportarAPlano(rep.id);
      expect(
        plano,
        contains('HDR|SIIF_NACION|ENT-SIIF-TEST|2026|01|presupuestoMensual'),
      );
    },
  );
}
