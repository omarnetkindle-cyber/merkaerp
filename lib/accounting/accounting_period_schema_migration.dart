import 'package:sqflite/sqflite.dart';

/// Migracion v89: los periodos contables pertenecen a una empresa.
///
/// Las instalaciones anteriores guardaban periodos globales. Al migrarlos,
/// las filas sin empresa se atribuyen a la empresa activa; no se inventan
/// fechas ni estados.
class AccountingPeriodSchemaMigration {
  const AccountingPeriodSchemaMigration._();

  static Future<void> migrateV89(Database db) async {
    final tableInfo = await db.rawQuery(
      'PRAGMA table_info(periodos_contables)',
    );
    if (tableInfo.isEmpty) {
      await _createTable(db, 'periodos_contables');
      await _ensureRetainedEarningsAccounts(db);
      return;
    }

    final columns = tableInfo
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    final tableSql = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'periodos_contables'",
    );
    final sql = tableSql.isEmpty
        ? ''
        : (tableSql.first['sql']?.toString() ?? '');
    final hasCompanyKey = sql.contains('UNIQUE(company_id, anio, mes)');

    if (columns.contains('company_id') && hasCompanyKey) {
      await _ensureRetainedEarningsAccounts(db);
      return;
    }

    final rows = await db.query('periodos_contables');
    final activeCompanyId = await _activeCompanyId(db);
    await _createTable(db, 'periodos_contables_new');

    for (final row in rows) {
      final apertura = row['fecha_apertura'] ?? row['fecha'];
      await db.insert('periodos_contables_new', {
        'id': row['id'],
        'company_id': row['company_id'] ?? activeCompanyId,
        'anio': row['anio'],
        'mes': row['mes'],
        'estado': row['estado'] ?? 'abierto',
        'fecha_apertura': apertura ?? DateTime.now().toIso8601String(),
        'fecha_cierre': row['fecha_cierre'],
        'observacion': row['observacion'],
      });
    }

    await db.execute('DROP TABLE periodos_contables');
    await db.execute(
      'ALTER TABLE periodos_contables_new RENAME TO periodos_contables',
    );
    await _ensureRetainedEarningsAccounts(db);
  }

  static Future<void> _createTable(Database db, String name) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $name(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        anio INTEGER NOT NULL,
        mes INTEGER NOT NULL,
        estado TEXT NOT NULL DEFAULT 'abierto',
        fecha_apertura TEXT NOT NULL,
        fecha_cierre TEXT,
        observacion TEXT,
        UNIQUE(company_id, anio, mes)
      )
    ''');
  }

  static Future<int> _activeCompanyId(Database db) async {
    final configured = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['company_active_id'],
      limit: 1,
    );
    final configuredId = configured.isEmpty
        ? null
        : int.tryParse(configured.first['valor']?.toString() ?? '');
    if (configuredId != null) return configuredId;

    final companies = await db.query('companies', columns: ['id'], limit: 1);
    return companies.isEmpty ? 1 : companies.first['id'] as int;
  }

  static Future<void> _ensureRetainedEarningsAccounts(Database db) async {
    final table = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      ['cuentas_contables'],
    );
    if (table.isEmpty) return;

    final accounts = [
      {
        'codigo': '37',
        'nombre': 'Resultados acumulados',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3705',
        'nombre': 'Utilidades o perdidas acumuladas',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
    ];
    for (final account in accounts) {
      await db.insert(
        'cuentas_contables',
        account,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
