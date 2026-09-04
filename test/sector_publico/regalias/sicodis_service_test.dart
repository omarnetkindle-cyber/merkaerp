import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/regalias/database/schema_regalias.dart';
import 'package:merka_erp/sector_publico/regalias/services/sicodis_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuditoriaService auditoriaService;
  late SICODISService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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

    await SchemaRegalias.crearTablas(db);

    await db.insert('entidades_territoriales', {
      'id': 'entidad-001',
      'nit': '800123456-1',
      'razon_social': 'Municipio Test',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    await db.insert('sgp', {
      'id': 'sgp-001',
      'entidad_id': 'entidad-001',
      'numero_sgp': 'SGP-2026-EDU-01',
      'tipo_participacion': 'Educación',
      'programa': 'Calidad Educativa',
      'municipio': 'Test',
      'departamento': 'Test',
      'valor_asignado': 100000000000,
      'valor_ejecutado': 95000000000,
      'saldo_disponible': 5000000000,
      'vigencia': '2026',
      'fecha_asignacion': DateTime.now().toIso8601String(),
      'estado': 'asignado',
    });

    auditoriaService = AuditoriaService(db);
    service = SICODISService(db: db, auditoriaService: auditoriaService);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Generación de Certificación SICODIS SGP y Exportación a Plano DNP',
    () async {
      final rep = await service.generarCertificacionSICODIS(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        vigencia: '2026',
        sectorParticipacion: 'Educación',
      );

      expect(rep.sectorParticipacion, equals('Educación'));
      expect(rep.datos['monto_asignado_sgp'], equals(1000000000.0));

      final plano = await service.exportarAPlano(rep.id);
      expect(plano, contains('SICODIS_DNP_HEADER'));
      expect(plano, contains('Educación'));
    },
  );
}
