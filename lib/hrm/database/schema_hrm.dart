import 'package:sqflite/sqflite.dart';

/// Esquema HRM. `empleados` sigue siendo la fuente canonica del empleado
/// comercial; las entidades de ausencias y asistencia viven bajo `hrm_*`.
class SchemaHrm {
  const SchemaHrm._();

  static const leaveTypes = <Map<String, Object?>>[
    {'code': 'vacaciones', 'name': 'Vacaciones'},
    {'code': 'incapacidad_eps', 'name': 'Incapacidad EPS'},
    {'code': 'incapacidad_arl', 'name': 'Incapacidad ARL'},
    {'code': 'licencia_maternidad', 'name': 'Licencia de maternidad'},
    {'code': 'licencia_paternidad', 'name': 'Licencia de paternidad'},
    {'code': 'luto', 'name': 'Licencia por luto'},
    {'code': 'permiso_remunerado', 'name': 'Permiso remunerado'},
    {
      'code': 'permiso_no_remunerado',
      'name': 'Permiso no remunerado',
      'requires_entitlement': 0,
    },
  ];

  static Future<void> crearTablas(DatabaseExecutor db) async {
    await _addColumn(db, 'empleados', 'employee_code', 'TEXT');
    await _addColumn(db, 'empleados', 'job_title_id', 'INTEGER');
    await _addColumn(db, 'empleados', 'fecha_nacimiento', 'TEXT');
    await _addColumn(db, 'empleados', 'genero', 'TEXT');
    await _addColumn(db, 'empleados', 'estado_civil', 'TEXT');
    await _addColumn(db, 'empleados', 'salary_grade', 'TEXT');
    await _addColumn(db, 'empleados', 'manager_id', 'INTEGER');
    await _addColumn(db, 'empleados', 'termination_id', 'INTEGER');
    await _addColumn(db, 'empleados', 'email', 'TEXT');
    await _addColumn(db, 'empleados', 'telefono', 'TEXT');
    await _addColumn(db, 'empleados', 'direccion', 'TEXT');
    await _addColumn(
      db,
      'empleados',
      'entity_type',
      "TEXT NOT NULL DEFAULT 'comercial'",
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_job_titles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        contractual_hours_per_day REAL,
        mrp_workstation_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(company_id, title)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_leave_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        requires_entitlement INTEGER NOT NULL DEFAULT 1,
        exclude_in_reports_if_no_entitlement INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, code)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_leave_entitlements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        employee_id INTEGER NOT NULL,
        leave_type_id INTEGER NOT NULL,
        days_total REAL NOT NULL,
        days_used REAL NOT NULL DEFAULT 0,
        period_from TEXT NOT NULL,
        period_to TEXT NOT NULL,
        UNIQUE(company_id, employee_id, leave_type_id, period_from, period_to),
        FOREIGN KEY(employee_id) REFERENCES empleados(id),
        FOREIGN KEY(leave_type_id) REFERENCES hrm_leave_types(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_leave_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        employee_id INTEGER NOT NULL,
        leave_type_id INTEGER NOT NULL,
        date_applied TEXT NOT NULL,
        comments TEXT,
        status TEXT NOT NULL DEFAULT 'pendiente',
        FOREIGN KEY(employee_id) REFERENCES empleados(id),
        FOREIGN KEY(leave_type_id) REFERENCES hrm_leave_types(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_leaves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        leave_request_id INTEGER NOT NULL,
        employee_id INTEGER NOT NULL,
        leave_type_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        length_days REAL NOT NULL,
        duration_type TEXT NOT NULL DEFAULT 'dia_completo',
        status TEXT NOT NULL DEFAULT 'pendiente',
        approved_by INTEGER,
        comments TEXT,
        reviewed_by INTEGER,
        reviewed_at TEXT,
        rejection_reason TEXT,
        FOREIGN KEY(leave_request_id) REFERENCES hrm_leave_requests(id),
        FOREIGN KEY(employee_id) REFERENCES empleados(id),
        FOREIGN KEY(leave_type_id) REFERENCES hrm_leave_types(id)
      )
    ''');
    await _addColumn(db, 'hrm_leaves', 'reviewed_by', 'INTEGER');
    await _addColumn(db, 'hrm_leaves', 'reviewed_at', 'TEXT');
    await _addColumn(db, 'hrm_leaves', 'rejection_reason', 'TEXT');
    await _addColumn(
      db,
      'hrm_leave_types',
      'exclude_in_reports_if_no_entitlement',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumn(db, 'hrm_job_titles', 'contractual_hours_per_day', 'REAL');
    await _addColumn(db, 'hrm_job_titles', 'mrp_workstation_id', 'INTEGER');
    // Migración: start_date/end_date para rango de la solicitud.
    // Las filas existentes heredan date_applied como fallback en fromMap().
    await _addColumn(db, 'hrm_leave_requests', 'start_date', 'TEXT');
    await _addColumn(db, 'hrm_leave_requests', 'end_date', 'TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hrm_attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        employee_id INTEGER NOT NULL,
        punch_in TEXT,
        punch_out TEXT,
        state TEXT NOT NULL DEFAULT 'IN_PROGRESS',
        FOREIGN KEY(employee_id) REFERENCES empleados(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hrm_leave_date ON hrm_leaves(company_id, date, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hrm_attendance_employee ON hrm_attendance_records(company_id, employee_id, punch_in)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hrm_job_title_workstation ON hrm_job_titles(company_id, mrp_workstation_id)',
    );
    await _seedLeaveTypes(db);
    await db.update(
      'hrm_leave_types',
      {'requires_entitlement': 0},
      where: 'code = ?',
      whereArgs: ['permiso_no_remunerado'],
    );
  }

  static Future<void> _seedLeaveTypes(DatabaseExecutor db) async {
    for (final type in leaveTypes) {
      await db.insert('hrm_leave_types', {
        'company_id': 1,
        ...type,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
