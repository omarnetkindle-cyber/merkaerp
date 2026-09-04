import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v97 conserva conversaciones legacy y agrega auditoria segura',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp('copilot_v97_');
      final path = p.join(directory.path, 'legacy.db');
      var db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 96,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE conversaciones_copilot(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              company_id INTEGER,
              usuario TEXT NOT NULL,
              modulo TEXT,
              rol TEXT,
              mensaje_usuario TEXT NOT NULL,
              respuesta TEXT NOT NULL,
              intent TEXT NOT NULL,
              creada_en TEXT NOT NULL
            )
          ''');
            await db.insert('conversaciones_copilot', {
              'company_id': 1,
              'usuario': 'legacy',
              'modulo': 'workspace',
              'rol': 'consulta',
              'mensaje_usuario': 'consulta antigua',
              'respuesta': 'respuesta antigua',
              'intent': 'legacy',
              'creada_en': '2026-08-01T00:00:00',
            });
          },
        ),
      );
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 97,
          onUpgrade: DatabaseHelper.instance.migrarDBForTesting,
        ),
      );
      final columns = await db.rawQuery(
        'PRAGMA table_info(conversaciones_copilot)',
      );
      final names = columns.map((row) => row['name']).toSet();
      expect(
        names,
        containsAll({
          'usuario_id',
          'tool_id',
          'proveedor',
          'resultado',
          'detalle_error',
          'acciones',
        }),
      );
      final rows = await db.query('conversaciones_copilot');
      expect(rows, hasLength(1));
      expect(rows.single['mensaje_usuario'], 'consulta antigua');
      expect(rows.single['proveedor'], 'deterministic');
      expect(rows.single['resultado'], 'exitoso');

      await db.close();
      await directory.delete(recursive: true);
    },
  );
}
