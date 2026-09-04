import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/regalias/database/schema_regalias.dart';
import 'package:merka_erp/sector_publico/regalias/models/sgp.dart';
import 'package:merka_erp/sector_publico/regalias/services/sgp_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SGPService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE entidades_territoriales (id TEXT PRIMARY KEY)',
    );
    await db.execute('''
      CREATE TABLE auditoria_registros (
        id TEXT PRIMARY KEY, entidad_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
        usuario_nombre TEXT, ip_direccion TEXT, fecha_hora TEXT NOT NULL,
        tipo_evento TEXT NOT NULL, modulo TEXT NOT NULL, accion TEXT NOT NULL,
        valor_anterior TEXT NOT NULL, valor_nuevo TEXT NOT NULL,
        hash_anterior TEXT, hash_actual TEXT NOT NULL, referencia_id TEXT,
        observaciones TEXT, archivado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await SchemaRegalias.migrarDestinacionYOCAD(db);
    await db.insert('entidades_territoriales', {'id': 'ent-1'});
    service = SGPService(db: db, auditoriaService: AuditoriaService(db));
  });

  tearDown(() => db.close());

  test(
    'bloquea ejecucion SGP en rubro no autorizado y acepta su componente autorizado',
    () async {
      final sgp = await service.asignarSGP(
        entidadId: 'ent-1',
        usuarioId: 'usr-1',
        tipoParticipacion: TipoParticipacion.salud,
        programa: 'Salud publica',
        municipio: 'Prueba',
        departamento: 'Prueba',
        valorAsignado: publicMoneyFromMajor('1000'),
        vigencia: DateTime(2026),
      );

      await expectLater(
        service.registrarEjecucion(
          entidadId: 'ent-1',
          usuarioId: 'usr-1',
          sgpId: sgp.id,
          codigoRubro: 'EDU-001',
          montoEjecucion: publicMoneyFromMajor('100'),
        ),
        throwsA(isA<Exception>()),
      );

      await service.configurarDestinacionRubro(
        id: 'destino-1',
        entidadId: 'ent-1',
        sgpId: sgp.id,
        codigoRubro: 'SAL-001',
      );
      final ejecutado = await service.registrarEjecucion(
        entidadId: 'ent-1',
        usuarioId: 'usr-1',
        sgpId: sgp.id,
        codigoRubro: 'SAL-001',
        montoEjecucion: publicMoneyFromMajor('100'),
      );

      expect(ejecutado.valorEjecutado, publicMoneyFromMajor('100'));
      expect(ejecutado.saldoDisponible, publicMoneyFromMajor('900'));
    },
  );
}
