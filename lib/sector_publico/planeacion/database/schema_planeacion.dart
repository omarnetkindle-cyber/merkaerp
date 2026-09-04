/// Esquema de base de datos para el módulo de Planeación
/// Banco de Proyectos MGA + PDT
library;

import 'package:sqflite/sqflite.dart';

class SchemaPlaneacion {
  static Future<void> crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS proyectos_mga (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        codigo_bpin TEXT NOT NULL,
        nombre_proyecto TEXT NOT NULL,
        tipo_proyecto TEXT NOT NULL,
        sector TEXT NOT NULL,
        programa TEXT NOT NULL,
        subprograma TEXT NOT NULL,
        valor_total INTEGER NOT NULL,
        valor_ejecutado INTEGER NOT NULL DEFAULT 0,
        saldo_por_ejecutar INTEGER NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        responsable TEXT NOT NULL,
        dependencia TEXT NOT NULL,
        estado TEXT NOT NULL,
        codigo_cdp TEXT,
        codigo_rp TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pdt (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        nombre_pdt TEXT NOT NULL,
        vision TEXT NOT NULL,
        mision TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        estado TEXT NOT NULL,
        acto_administrativo TEXT,
        fecha_aprobacion TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS flujos_viabilizacion (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        proyecto_id TEXT NOT NULL,
        etapa TEXT NOT NULL,
        motivo TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        iniciado_por TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        observaciones TEXT,
        fecha_respuesta TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (proyecto_id) REFERENCES proyectos_mga(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS proyecto_rubros_metas (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        proyecto_id TEXT NOT NULL,
        apropiacion_id TEXT NOT NULL,
        meta_codigo TEXT NOT NULL,
        meta_descripcion TEXT NOT NULL,
        avance_fisico_porcentaje REAL NOT NULL DEFAULT 0,
        fecha_reporte TEXT NOT NULL,
        UNIQUE(proyecto_id, apropiacion_id, meta_codigo),
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (proyecto_id) REFERENCES proyectos_mga(id),
        FOREIGN KEY (apropiacion_id) REFERENCES apropiaciones(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdp_meta_trazabilidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        cdp_id TEXT NOT NULL UNIQUE,
        proyecto_id TEXT NOT NULL,
        apropiacion_id TEXT NOT NULL,
        meta_codigo TEXT NOT NULL,
        meta_descripcion TEXT NOT NULL,
        codigo_bpin TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        fecha_vinculacion TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (cdp_id) REFERENCES cdps(id),
        FOREIGN KEY (proyecto_id) REFERENCES proyectos_mga(id),
        FOREIGN KEY (apropiacion_id) REFERENCES apropiaciones(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rp_meta_trazabilidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        rp_id TEXT NOT NULL UNIQUE,
        cdp_id TEXT NOT NULL,
        proyecto_id TEXT NOT NULL,
        meta_codigo TEXT NOT NULL,
        meta_descripcion TEXT NOT NULL,
        codigo_bpin TEXT NOT NULL,
        fecha_vinculacion TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (rp_id) REFERENCES rps(id),
        FOREIGN KEY (cdp_id) REFERENCES cdps(id),
        FOREIGN KEY (proyecto_id) REFERENCES proyectos_mga(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_proyectos_entidad ON proyectos_mga(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_proyectos_estado ON proyectos_mga(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_proyectos_bpin ON proyectos_mga(codigo_bpin)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdt_entidad ON pdt(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdt_vigencia ON pdt(vigencia)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_flujos_viab_proyecto ON flujos_viabilizacion(proyecto_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_proyecto_rubros_meta_proyecto ON proyecto_rubros_metas(proyecto_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_proyecto_rubros_meta_apropiacion ON proyecto_rubros_metas(apropiacion_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cdp_meta_trazabilidad_proyecto ON cdp_meta_trazabilidad(proyecto_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cdp_meta_trazabilidad_apropiacion ON cdp_meta_trazabilidad(apropiacion_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rp_meta_trazabilidad_cdp ON rp_meta_trazabilidad(cdp_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_proyectos_mga_entidad_bpin ON proyectos_mga(entidad_id, codigo_bpin)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_pdt_entidad_vigencia ON pdt(entidad_id, vigencia)',
    );
  }

  static Future<void> migrarTrazabilidadPlanPresupuesto(Database db) =>
      crearTablas(db);
}
