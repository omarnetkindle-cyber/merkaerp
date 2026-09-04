import 'package:sqflite/sqflite.dart';

/// Esquema de trazabilidad para migraciones desde sistemas legados.
///
/// Nunca se mezcla con la lógica operativa: registra origen, mapeos, filas
/// originales, cambios aplicados y permite revertir únicamente lo que la
/// propia migración creó/modificó.
class SchemaDataMigration {
  static Future<void> createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_migration_jobs(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        public_entity_id TEXT,
        product_family TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_file_name TEXT,
        source_sha256 TEXT,
        status TEXT NOT NULL,
        duplicate_policy TEXT NOT NULL DEFAULT 'skip',
        backup_path TEXT,
        summary_json TEXT NOT NULL DEFAULT '{}',
        started_at TEXT NOT NULL,
        completed_at TEXT,
        rolled_back_at TEXT,
        created_by TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_migration_runs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        target_entity TEXT NOT NULL,
        source_sheet TEXT,
        mapping_json TEXT NOT NULL DEFAULT '{}',
        rows_total INTEGER NOT NULL DEFAULT 0,
        rows_valid INTEGER NOT NULL DEFAULT 0,
        rows_imported INTEGER NOT NULL DEFAULT 0,
        rows_skipped INTEGER NOT NULL DEFAULT 0,
        rows_errors INTEGER NOT NULL DEFAULT 0,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY(job_id) REFERENCES data_migration_jobs(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_migration_legacy_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        run_id INTEGER NOT NULL,
        row_number INTEGER NOT NULL,
        target_entity TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        normalized_json TEXT,
        imported INTEGER NOT NULL DEFAULT 0,
        target_table TEXT,
        target_pk TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(job_id) REFERENCES data_migration_jobs(id),
        FOREIGN KEY(run_id) REFERENCES data_migration_runs(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_migration_issues(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        run_id INTEGER NOT NULL,
        row_number INTEGER,
        severity TEXT NOT NULL,
        field_name TEXT,
        message TEXT NOT NULL,
        raw_value TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(job_id) REFERENCES data_migration_jobs(id),
        FOREIGN KEY(run_id) REFERENCES data_migration_runs(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_migration_changes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        run_id INTEGER NOT NULL,
        sequence_no INTEGER NOT NULL,
        target_entity TEXT NOT NULL,
        table_name TEXT NOT NULL,
        pk_column TEXT NOT NULL,
        pk_value TEXT NOT NULL,
        operation TEXT NOT NULL,
        before_json TEXT,
        after_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(job_id) REFERENCES data_migration_jobs(id),
        FOREIGN KEY(run_id) REFERENCES data_migration_runs(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_data_migration_jobs_company
      ON data_migration_jobs(company_id, started_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_data_migration_runs_job
      ON data_migration_runs(job_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_data_migration_legacy_job
      ON data_migration_legacy_records(job_id, target_entity)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_data_migration_changes_job
      ON data_migration_changes(job_id, sequence_no DESC)
    ''');
  }
}
