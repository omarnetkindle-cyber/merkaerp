/// Esquema de base de datos para el módulo de Regalías y SGP
/// SGR (Sistema General de Regalías) + SGP + Bienios SGR + OCAD + SPGR + SICODIS
library;

import 'package:sqflite/sqflite.dart';

class SchemaRegalias {
  static Future<void> crearTablas(Database db) async {
    // 1. Tabla de estimaciones de Regalías
    await db.execute('''
      CREATE TABLE IF NOT EXISTS regalias (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_regalia TEXT NOT NULL,
        tipo_regalia TEXT NOT NULL,
        proyecto TEXT NOT NULL,
        municipio TEXT NOT NULL,
        departamento TEXT NOT NULL,
        valor_estimado INTEGER NOT NULL,
        valor_recibido INTEGER NOT NULL DEFAULT 0,
        valor_distribuido INTEGER NOT NULL DEFAULT 0,
        valor_asignado INTEGER NOT NULL DEFAULT 0,
        valor_ejecutado INTEGER NOT NULL DEFAULT 0,
        vigencia TEXT NOT NULL,
        fecha_estimacion TEXT NOT NULL,
        fecha_recepcion TEXT,
        fecha_distribucion TEXT,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // 2. Tabla de asignaciones del SGP (Sistema General de Participaciones)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sgp (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_sgp TEXT NOT NULL,
        tipo_participacion TEXT NOT NULL,
        programa TEXT NOT NULL,
        municipio TEXT NOT NULL,
        departamento TEXT NOT NULL,
        valor_asignado INTEGER NOT NULL,
        valor_transferido INTEGER NOT NULL DEFAULT 0,
        valor_recibido INTEGER NOT NULL DEFAULT 0,
        valor_ejecutado INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        vigencia TEXT NOT NULL,
        fecha_asignacion TEXT NOT NULL,
        fecha_transferencia TEXT,
        fecha_recepcion TEXT,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // 3. Tabla de Bienios Presupuestales SGR (Bienalidades 2 años: ej. 2025-2026)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bienios_sgr (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        codigo_bienio TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        monto_presupuestado_bienio INTEGER NOT NULL,
        monto_ejecutado_bienio INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'vigente',
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // 4. Tabla de Proyectos OCAD
    await db.execute('''
      CREATE TABLE IF NOT EXISTS proyectos_ocad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        proyecto_mga_id TEXT,
        bienio_id TEXT,
        codigo_bpin TEXT NOT NULL,
        nombre_proyecto TEXT NOT NULL,
        bienalidad TEXT NOT NULL,
        tipo_ocad TEXT NOT NULL,
        monto_aprobado INTEGER NOT NULL,
        monto_giro_spgr INTEGER NOT NULL DEFAULT 0,
        estado_ocad TEXT NOT NULL,
        fecha_aprobacion TEXT NOT NULL,
        acta_aprobacion TEXT,
        fuente_financiacion TEXT,
        entidad_ejecutora TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (proyecto_mga_id) REFERENCES proyectos_mga(id),
        FOREIGN KEY (bienio_id) REFERENCES bienios_sgr(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sgp_destinaciones_rubro (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        sgp_id TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        componente TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        UNIQUE(sgp_id, codigo_rubro),
        FOREIGN KEY (sgp_id) REFERENCES sgp(id)
      )
    ''');

    // 5. Tabla de Reportes SPGR
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reportes_spgr (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        bienio_id TEXT,
        bienalidad TEXT NOT NULL,
        fecha_generacion TEXT NOT NULL,
        usuario_genero TEXT NOT NULL,
        datos TEXT NOT NULL,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (bienio_id) REFERENCES bienios_sgr(id)
      )
    ''');

    // 6. Tabla de Certificaciones SICODIS SGP (Sistema de Información para la Captura de Datos de la Inversión Social - DNP)
    // FK: entidad_id -> entidades_territoriales(id)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reportes_sicodis (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        sector_participacion TEXT NOT NULL,
        fecha_generacion TEXT NOT NULL,
        usuario_genero TEXT NOT NULL,
        datos TEXT NOT NULL,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_regalias_entidad ON regalias(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_regalias_estado ON regalias(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_regalias_vigencia ON regalias(vigencia)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sgp_entidad ON sgp(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sgp_estado ON sgp(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sgp_vigencia ON sgp(vigencia)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bienios_entidad ON bienios_sgr(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ocad_entidad ON proyectos_ocad(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ocad_mga ON proyectos_ocad(proyecto_mga_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ocad_bpin ON proyectos_ocad(codigo_bpin)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_spgr_entidad ON reportes_spgr(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sicodis_entidad ON reportes_sicodis(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sgp_destinaciones_sgp ON sgp_destinaciones_rubro(sgp_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_regalias_entidad_numero ON regalias(entidad_id, numero_regalia)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_sgp_entidad_numero ON sgp(entidad_id, numero_sgp)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_bienios_sgr_entidad_codigo ON bienios_sgr(entidad_id, codigo_bienio)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_proyectos_ocad_entidad_bpin ON proyectos_ocad(entidad_id, codigo_bpin)',
    );
  }

  static Future<void> migrarDestinacionYOCAD(Database db) async {
    await crearTablas(db);
    await _agregarColumnaSiNoExiste(
      db,
      'proyectos_ocad',
      'acta_aprobacion',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'proyectos_ocad',
      'fuente_financiacion',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'proyectos_ocad',
      'entidad_ejecutora',
      'TEXT',
    );
  }

  static Future<void> _agregarColumnaSiNoExiste(
    Database db,
    String tabla,
    String columna,
    String definicion,
  ) async {
    final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
    if (!columnas.any((fila) => fila['name'] == columna)) {
      await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $definicion');
    }
  }
}
