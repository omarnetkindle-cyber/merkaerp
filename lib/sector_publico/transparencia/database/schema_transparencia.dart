/// Esquema de base de datos para el módulo de Transparencia
/// Transparencia + Control Disciplinario + Consolidación NICSP 40
library;

import 'package:sqflite/sqflite.dart';

class SchemaTransparencia {
  static Future<void> crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reportes_transparencia (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_reporte TEXT NOT NULL,
        tipo_reporte TEXT NOT NULL,
        titulo TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        periodo_inicio TEXT NOT NULL,
        periodo_fin TEXT NOT NULL,
        url_publicacion TEXT,
        estado TEXT NOT NULL,
        fecha_publicacion TEXT NOT NULL,
        usuario_publico TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS procesos_disciplinarios (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_proceso TEXT NOT NULL,
        tipo_proceso TEXT NOT NULL,
        servidor_publico TEXT NOT NULL,
        identificacion TEXT NOT NULL,
        cargo TEXT NOT NULL,
        dependencia TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_decision TEXT,
        estado TEXT NOT NULL,
        sancion TEXT,
        monto_sancion INTEGER,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS consolidaciones_nicsp40 (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_consolidacion TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        entidad_origen TEXT NOT NULL,
        entidad_destino TEXT NOT NULL,
        tipo_transferencia TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        valor_transferido INTEGER NOT NULL,
        valor_ejecutado INTEGER NOT NULL DEFAULT 0,
        valor_no_ejecutado INTEGER NOT NULL DEFAULT 0,
        fecha_transferencia TEXT NOT NULL,
        proyecto TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reportes_entidad ON reportes_transparencia(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reportes_estado ON reportes_transparencia(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_procesos_entidad ON procesos_disciplinarios(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_procesos_estado ON procesos_disciplinarios(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_consolidaciones_entidad ON consolidaciones_nicsp40(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_consolidaciones_vigencia ON consolidaciones_nicsp40(vigencia)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_reportes_transparencia_entidad_numero ON reportes_transparencia(entidad_id, numero_reporte)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_procesos_disciplinarios_entidad_numero ON procesos_disciplinarios(entidad_id, numero_proceso)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_consolidaciones_nicsp40_entidad_numero ON consolidaciones_nicsp40(entidad_id, numero_consolidacion)',
    );
  }
}
