import 'package:sqflite/sqflite.dart';

/// Migracion v91: registra el marco NIIF declarado por cada empresa.
class FinancialFrameworkSchemaMigration {
  const FinancialFrameworkSchemaMigration._();

  static Future<void> migrateV91(Database db) async {
    final table = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      ['companies'],
    );
    if (table.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info(companies)');
    final exists = columns.any((row) => row['name'] == 'niif_group');
    if (!exists) {
      await db.execute(
        "ALTER TABLE companies ADD COLUMN niif_group TEXT NOT NULL DEFAULT 'grupo_2'",
      );
    }

    // Instalaciones antiguas no tenian este dato. Se conserva el registro y
    // se usa Grupo 2 solo como valor tecnico revisable, nunca como inferencia.
    await db.update(
      'companies',
      {'niif_group': 'grupo_2'},
      where: 'niif_group IS NULL OR TRIM(niif_group) = ?',
      whereArgs: [''],
    );
  }
}
