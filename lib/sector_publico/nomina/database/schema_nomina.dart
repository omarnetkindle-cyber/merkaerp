/// Esquema de base de datos para el módulo de Nómina Pública
/// PILA + Retroactivos
library;

import 'package:sqflite/sqflite.dart';

class SchemaNomina {
  static Future<void> crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS empleados_sp (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_identificacion TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        cargo TEXT NOT NULL,
        dependencia TEXT NOT NULL,
        tipo_contrato TEXT NOT NULL,
        tipo_vinculacion TEXT NOT NULL,
        regimen_nomina TEXT NOT NULL DEFAULT 'carreraAdministrativa',
        clase_riesgo_arl INTEGER NOT NULL DEFAULT 1,
        salario_basico INTEGER NOT NULL,
        fecha_ingreso TEXT NOT NULL,
        fecha_retiro TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        cuenta_bancaria TEXT,
        tipo_cuenta TEXT,
        banco TEXT,
        eps TEXT,
        fondo_pension TEXT,
        fondo_cesantias TEXT,
        observaciones TEXT,
        hrm_employee_id INTEGER,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS liquidaciones_nomina (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_liquidacion TEXT NOT NULL,
        periodo TEXT NOT NULL,
        empleado_id TEXT NOT NULL,
        empleado_nombre TEXT NOT NULL,
        empleado_identificacion TEXT NOT NULL,
        dias_trabajados INTEGER NOT NULL,
        salario_basico INTEGER NOT NULL,
        salario_devengado INTEGER NOT NULL,
        auxilio_transporte INTEGER NOT NULL DEFAULT 0,
        auxilio_alimentacion INTEGER NOT NULL DEFAULT 0,
        horas_extra INTEGER NOT NULL DEFAULT 0,
        recargo_nocturno INTEGER NOT NULL DEFAULT 0,
        total_devengado INTEGER NOT NULL,
        salud INTEGER NOT NULL,
        pension INTEGER NOT NULL,
        fondo_solidaridad INTEGER NOT NULL,
        riesgos_laborales INTEGER NOT NULL,
        caja_compensacion INTEGER NOT NULL,
        sena INTEGER NOT NULL,
        icbf INTEGER NOT NULL,
        total_aportes INTEGER NOT NULL,
        neto_pagar INTEGER NOT NULL,
        estado TEXT NOT NULL,
        fecha_liquidacion TEXT NOT NULL,
        fecha_pago TEXT,
        pila_id TEXT,
        observaciones TEXT,
        novedades_hrm TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (empleado_id) REFERENCES empleados_sp(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS retroactivos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_retroactivo TEXT NOT NULL,
        empleado_id TEXT NOT NULL,
        empleado_nombre TEXT NOT NULL,
        empleado_identificacion TEXT NOT NULL,
        tipo_retroactivo TEXT NOT NULL,
        motivo TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        meses INTEGER NOT NULL,
        salario_anterior INTEGER NOT NULL,
        salario_nuevo INTEGER NOT NULL,
        diferencia_mensual INTEGER NOT NULL,
        valor_total INTEGER NOT NULL,
        valor_pagado INTEGER NOT NULL DEFAULT 0,
        saldo_pendiente INTEGER NOT NULL,
        estado TEXT NOT NULL,
        fecha_calculo TEXT NOT NULL,
        fecha_aprobacion TEXT,
        acto_administrativo TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (empleado_id) REFERENCES empleados_sp(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS horas_extra (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        empleado_id TEXT NOT NULL,
        tipo_hora TEXT NOT NULL,
        fecha TEXT NOT NULL,
        cantidad_horas REAL NOT NULL,
        salario_hora INTEGER NOT NULL,
        porcentaje_recargo REAL NOT NULL,
        valor_recargo INTEGER NOT NULL,
        valor_total INTEGER NOT NULL,
        motivo TEXT,
        aprobado_por TEXT,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (empleado_id) REFERENCES empleados_sp(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recargos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        empleado_id TEXT NOT NULL,
        tipo_recargo TEXT NOT NULL,
        fecha TEXT NOT NULL,
        cantidad_horas REAL NOT NULL,
        salario_hora INTEGER NOT NULL,
        porcentaje_recargo REAL NOT NULL,
        valor_recargo INTEGER NOT NULL,
        motivo TEXT,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (empleado_id) REFERENCES empleados_sp(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_empleados_entidad ON empleados_sp(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_empleados_identificacion ON empleados_sp(numero_identificacion)',
    );
    final employeeTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['empleados_sp'],
    );
    if (employeeTables.isNotEmpty) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_empleados_hrm_employee ON empleados_sp(hrm_employee_id)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_liquidaciones_entidad ON liquidaciones_nomina(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_liquidaciones_periodo ON liquidaciones_nomina(periodo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_liquidaciones_empleado ON liquidaciones_nomina(empleado_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_retroactivos_entidad ON retroactivos(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_retroactivos_empleado ON retroactivos(empleado_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_horas_extra_entidad ON horas_extra(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_horas_extra_empleado ON horas_extra(empleado_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recargos_entidad ON recargos(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recargos_empleado ON recargos(empleado_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_empleados_sp_entidad_identificacion ON empleados_sp(entidad_id, numero_identificacion)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_liquidaciones_nomina_entidad_numero ON liquidaciones_nomina(entidad_id, numero_liquidacion)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_retroactivos_entidad_numero ON retroactivos(entidad_id, numero_retroactivo)',
    );
  }

  static Future<void> migrarRegimenesYAportes(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'empleados_sp',
      'regimen_nomina',
      "TEXT NOT NULL DEFAULT 'carreraAdministrativa'",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'empleados_sp',
      'clase_riesgo_arl',
      'INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> migrarHrmEmployeeLink(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'empleados_sp',
      'hrm_employee_id',
      'INTEGER REFERENCES empleados(id)',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'liquidaciones_nomina',
      'novedades_hrm',
      'TEXT',
    );
    final employeeTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['empleados_sp'],
    );
    if (employeeTables.isNotEmpty) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_empleados_hrm_employee ON empleados_sp(hrm_employee_id)',
      );
    }
  }

  /// Migración: tablas para auxilio de alimentación (Gap F3).
  /// Crea `auxilio_alimentacion` y `historico_valor_auxilio` si no existen.
  /// Idempotente — usa IF NOT EXISTS.
  static Future<void> migrarAuxilioAlimentacion(Database db) async {
    // Tabla de pagos de auxilio de alimentación por periodo/empleado.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auxilio_alimentacion (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        empleado_id TEXT NOT NULL,
        periodo TEXT NOT NULL,
        dias_trabajados INTEGER NOT NULL,
        valor_dia INTEGER NOT NULL DEFAULT 0,
        valor_total INTEGER NOT NULL DEFAULT 0,
        observaciones TEXT,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pagado',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (empleado_id) REFERENCES empleados_sp(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_auxalim_entidad_periodo '
      'ON auxilio_alimentacion(entidad_id, periodo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_auxalim_empleado '
      'ON auxilio_alimentacion(empleado_id)',
    );

    // Tabla de histórico de valores del auxilio (cuando cambia por decreto).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS historico_valor_auxilio (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        valor_anterior INTEGER NOT NULL DEFAULT 0,
        valor_nuevo INTEGER NOT NULL,
        decreto_referencia TEXT NOT NULL,
        fecha_vigencia TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        actualizado_por TEXT
      )
    ''');

    // Tabla de configuración del valor vigente del auxilio (por entidad).
    // Permite que cada entidad tenga su propio valor configurable
    // sin depender de una constante en código.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parametros_auxilio_alimentacion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entidad_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        valor_mensual INTEGER NOT NULL,
        decreto_referencia TEXT,
        fecha_vigencia TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(entidad_id, year)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_param_auxalim_entidad '
      'ON parametros_auxilio_alimentacion(entidad_id, year)',
    );
  }

  static Future<void> _agregarColumnaSiNoExiste(
    Database db,
    String tabla,
    String columna,
    String definicion,
  ) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tabla],
    );
    if (tablas.isEmpty) return;
    final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
    if (columnas.any((fila) => fila['name'] == columna)) return;
    await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $definicion');
  }
}
