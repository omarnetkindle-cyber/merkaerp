import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v83 agrega capacidad temporal sin alterar filas existentes', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE mrp_workstations (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        hour_rate INTEGER NOT NULL DEFAULT 0,
        production_capacity INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'produccion',
        warehouse_id INTEGER
      )
    ''');
    await db.insert('mrp_workstations', {
      'id': 1,
      'company_id': 4,
      'name': 'Legada',
      'hour_rate': 100,
      'production_capacity': 2,
      'status': 'produccion',
    });

    await DatabaseHelper.instance.migrarDBForTesting(db, 82, 83);

    final columns = await db.rawQuery('PRAGMA table_info(mrp_workstations)');
    expect(
      columns.any((column) => column['name'] == 'available_hours_per_day'),
      isTrue,
    );
    final row = await db.query('mrp_workstations');
    expect(row.single['name'], 'Legada');
    expect(row.single['available_hours_per_day'], isNull);
  });
}
