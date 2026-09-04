import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_schema_manifest.g.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final databasePath = Platform.environment['MERKA_MONEY_VALIDATION_DB'];
  test(
    'migra copia del respaldo v63 a v75 y compara cada fila',
    () async {
      final path = databasePath!;
      final beforeDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final beforeVersion = await beforeDb.getVersion();
      expect(beforeVersion, 63);
      await _seedValidationRows(beforeDb);
      final before = await _snapshotExistingTables(beforeDb);
      await beforeDb.close();

      final migratedDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 75,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: DatabaseHelper.instance.migrarDBForTesting,
        ),
      );
      try {
        expect(await migratedDb.getVersion(), 75);
        var checkedCells = 0;
        var migratedRows = 0;
        for (final entry in moneySchemaColumns.entries) {
          final oldRows = before[entry.key] ?? const <Map<String, Object?>>[];
          final newRows = await migratedDb.query(entry.key);
          expect(
            newRows.length,
            oldRows.length,
            reason: 'row count ${entry.key}',
          );
          migratedRows += newRows.length;

          final info = await migratedDb.rawQuery(
            'PRAGMA table_info("${entry.key}")',
          );
          final types = <String, String>{
            for (final column in info)
              column['name']! as String: column['type']
                  .toString()
                  .toUpperCase(),
          };
          for (final column in entry.value) {
            expect(types[column], 'INTEGER', reason: '${entry.key}.$column');
          }

          for (var rowIndex = 0; rowIndex < oldRows.length; rowIndex++) {
            final oldRow = oldRows[rowIndex];
            final newRow = newRows[rowIndex];
            for (final oldEntry in oldRow.entries) {
              if (entry.value.contains(oldEntry.key) &&
                  oldEntry.value != null) {
                final original = oldEntry.value! as num;
                final expected = (original * 100).round();
                expect(
                  newRow[oldEntry.key],
                  expected,
                  reason: '${entry.key}[$rowIndex].${oldEntry.key}',
                );
                checkedCells++;
              } else {
                expect(
                  newRow[oldEntry.key],
                  oldEntry.value,
                  reason: '${entry.key}[$rowIndex].${oldEntry.key}',
                );
              }
            }
          }
          stdout.writeln(
            'TABLE ${entry.key} rows_before=${oldRows.length} '
            'rows_after=${newRows.length} money_columns=${entry.value.length} OK',
          );
        }

        final cash = await migratedDb.query(
          'movimientos_caja',
          where: 'concepto = ?',
          whereArgs: ['VALIDACION_V75_99_99'],
        );
        final pac = await migratedDb.query(
          'pac',
          where: 'id = ?',
          whereArgs: ['PAC-VALIDACION-V75'],
        );
        stdout.writeln(
          'SAMPLE movimientos_caja.monto original=99.99 migrated=${cash.single['monto']} expected=9999',
        );
        stdout.writeln(
          'SAMPLE pac.valor_programado original=10000.0 migrated=${pac.single['valor_programado']} expected=1000000',
        );
        stdout.writeln(
          'SAMPLE pac.valor_ejecutado original=99.99 migrated=${pac.single['valor_ejecutado']} expected=9999',
        );
        stdout.writeln(
          'SUMMARY version_before=$beforeVersion version_after=75 '
          'tables=${moneySchemaColumns.length} columns=$moneySchemaColumnCount '
          'rows=$migratedRows checked_money_cells=$checkedCells OK',
        );
      } finally {
        await migratedDb.close();
        await DatabaseHelper.resetForTests();
      }
    },
    skip: databasePath == null
        ? 'Set MERKA_MONEY_VALIDATION_DB to a disposable backup copy'
        : false,
  );
}

Future<void> _seedValidationRows(Database db) async {
  await db.insert('movimientos_caja', {
    'company_id': 1,
    'tipo': 'ingreso',
    'concepto': 'VALIDACION_V75_99_99',
    'monto': 99.99,
    'fecha': '2026-08-02',
    'origen': 'test_migracion',
  });
  await db.insert('entidades_territoriales', {
    'id': 'ENT-VALIDACION-V75',
    'nit': '900000075',
    'razon_social': 'Entidad validacion v75',
    'tipo_entidad': 'municipio',
    'fecha_creacion': '2026-08-02T00:00:00.000',
    'plan_cuentas_cgc': 'CGC',
    'configuracion_normativa': '{}',
  });
  await db.insert('pac', {
    'id': 'PAC-VALIDACION-V75',
    'entidad_id': 'ENT-VALIDACION-V75',
    'vigencia': '2026',
    'mes': 8,
    'codigo_rubro': '2.1.1',
    'valor_programado': 10000.0,
    'valor_ejecutado': 99.99,
    'saldo_disponible': 9900.01,
    'fecha_creacion': '2026-08-02T00:00:00.000',
    'estado': 'activo',
  });
}

Future<Map<String, List<Map<String, Object?>>>> _snapshotExistingTables(
  Database db,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  final existing = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final names = existing.map((row) => row['name']! as String).toSet();
  for (final table in moneySchemaColumns.keys) {
    if (!names.contains(table)) continue;
    result[table] = await db.query(table);
  }
  return result;
}
