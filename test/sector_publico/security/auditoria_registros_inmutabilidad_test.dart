import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  Future<void> insertarRegistro({
    required String id,
    required String fechaHora,
  }) {
    return db.insert('auditoria_registros', {
      'id': id,
      'entidad_id': 'ENT-001',
      'usuario_id': 'USR-001',
      'fecha_hora': fechaHora,
      'tipo_evento': 'creacionRegistro',
      'modulo': 'prueba',
      'accion': 'crear',
      'valor_anterior': '{}',
      'valor_nuevo': '{}',
      'hash_actual': 'hash-$id',
    });
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'DELETE directo sobre auditoria_registros es bloqueado por SQLite',
    () async {
      await insertarRegistro(
        id: 'AUD-DELETE',
        fechaHora: '2026-01-01T00:00:00.000',
      );

      await expectLater(
        db.delete(
          'auditoria_registros',
          where: 'id = ?',
          whereArgs: ['AUD-DELETE'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'UPDATE solo de archivado se permite y el archivado del servicio funciona',
    () async {
      await insertarRegistro(
        id: 'AUD-DIRECTO',
        fechaHora: '2026-01-01T00:00:00.000',
      );
      await insertarRegistro(
        id: 'AUD-ANTIGUO',
        fechaHora: '1970-01-01T00:00:00.000',
      );

      await db.update(
        'auditoria_registros',
        {'archivado': 1},
        where: 'id = ?',
        whereArgs: ['AUD-DIRECTO'],
      );
      await AuditoriaService(db).archivarRegistrosAntiguos(
        'ENT-001',
        retentionYearsOverride: 50,
      );

      final rows = await db.query(
        'auditoria_registros',
        columns: ['id', 'archivado'],
        orderBy: 'id',
      );
      expect(rows, [
        {'id': 'AUD-ANTIGUO', 'archivado': 1},
        {'id': 'AUD-DIRECTO', 'archivado': 1},
      ]);
    },
  );

  test(
    'UPDATE que altera otro dato, incluso junto con archivado, es bloqueado',
    () async {
      await insertarRegistro(
        id: 'AUD-UPDATE',
        fechaHora: '2026-01-01T00:00:00.000',
      );

      await expectLater(
        db.update(
          'auditoria_registros',
          {'archivado': 1, 'accion': 'alterada'},
          where: 'id = ?',
          whereArgs: ['AUD-UPDATE'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}
