import 'package:sqflite/sqflite.dart';

class PayrollSchemaMigration {
  const PayrollSchemaMigration._();

  static Future<void> migrateV90(Database db) async {
    if (await _tableExists(db, 'nomina_liquidaciones')) {
      await _addColumnIfMissing(
        db,
        'nomina_liquidaciones',
        'movimiento_caja_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'nomina_liquidaciones',
        'asiento_id',
        'INTEGER',
      );
    }

    if (!await _tableExists(db, 'cuentas_contables')) return;

    final accounts = [
      ('510506', 'Sueldos', 'gasto', 'debito'),
      ('510515', 'Horas extras', 'gasto', 'debito'),
      ('510527', 'Auxilio de transporte', 'gasto', 'debito'),
      ('510548', 'Bonificaciones y variables', 'gasto', 'debito'),
      ('510570', 'Aporte salud empleador', 'gasto', 'debito'),
      ('510571', 'Aporte pension empleador', 'gasto', 'debito'),
      ('510572', 'Aporte ARL empleador', 'gasto', 'debito'),
      ('510573', 'Parafiscales empleador', 'gasto', 'debito'),
      ('510574', 'Provisiones laborales', 'gasto', 'debito'),
      ('237005', 'Salud por pagar', 'pasivo', 'credito'),
      ('237010', 'ARL y parafiscales por pagar', 'pasivo', 'credito'),
      ('237095', 'Otros aportes de nomina por pagar', 'pasivo', 'credito'),
      ('238030', 'Pension por pagar', 'pasivo', 'credito'),
      ('238035', 'Fondo de solidaridad pensional', 'pasivo', 'credito'),
      ('236505', 'Retencion laboral por pagar', 'pasivo', 'credito'),
      ('110505', 'Caja general', 'activo', 'debito'),
      ('111005', 'Bancos nacionales', 'activo', 'debito'),
    ];
    for (final account in accounts) {
      await db.insert('cuentas_contables', {
        'codigo': account.$1,
        'nombre': account.$2,
        'tipo': account.$3,
        'naturaleza': account.$4,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }
}
