import 'package:sqflite/sqflite.dart';

/// Storage for simulations only. It has no foreign keys that write to
/// operational CRM, MRP, or HRM tables and is never read by those modules.
class SchemaImpact {
  const SchemaImpact._();

  static Future<void> crearTablas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS impact_scenarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        uplift_percent INTEGER NOT NULL,
        input_json TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        formula TEXT NOT NULL,
        integrity_sha256 TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_impact_scenarios_company '
      'ON impact_scenarios(company_id, created_at DESC)',
    );
  }
}
