import 'package:sqflite/sqflite.dart';

import '../core/currency/currency.dart';
import 'retention_rule_service.dart';
import 'retention_policy.dart';

class RetentionSchemaMigration {
  const RetentionSchemaMigration._();

  static Future<void> migrateV87(DatabaseExecutor db) async {
    if (await _tableExists(db, 'ventas')) {
      await _addColumnIfMissing(
        db,
        'ventas',
        'retefuente_concepto',
        "TEXT NOT NULL DEFAULT 'otros_ingresos'",
      );
      await _addColumnIfMissing(
        db,
        'ventas',
        'retefuente_base',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        'ventas',
        'retefuente_tasa',
        'REAL NOT NULL DEFAULT 0',
      );
    }
    if (await _tableExists(db, 'compras')) {
      await _addColumnIfMissing(
        db,
        'compras',
        'retefuente_concepto',
        "TEXT NOT NULL DEFAULT 'compras'",
      );
      await _addColumnIfMissing(
        db,
        'compras',
        'retefuente_base',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        'compras',
        'retefuente_tasa',
        'REAL NOT NULL DEFAULT 0',
      );
    }

    // Only repair the old seed's zero base. A non-zero company override is
    // preserved because it is a deliberate configuration choice.
    final purchasesBase = RetentionPolicy.currentUvtMajorUnits * 10 * 100;
    if (await _tableExists(db, 'reglas_retenciones_empresa')) {
      await db.rawUpdate(
        'UPDATE reglas_retenciones_empresa '
        'SET base_minima = ? '
        "WHERE codigo = 'RTFTE_COMPRAS_25' "
        'AND (base_minima IS NULL OR base_minima = 0)',
        [purchasesBase],
      );
    }
  }

  static Future<void> migrateV99(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'companies') ||
        !await _tableExists(db, 'reglas_retenciones_empresa')) {
      return;
    }
    final companies = await db.query('companies', columns: ['id']);
    final cop = Currency(
      code: 'COP',
      name: 'Peso colombiano',
      symbol: r'$',
      decimalPlaces: 2,
    );
    const service = RetentionRuleService();
    for (final company in companies) {
      final companyId = (company['id'] as num?)?.toInt();
      if (companyId == null) continue;
      await service.seedDefaults(db: db, companyId: companyId, currency: cop);
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    if (rows.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
