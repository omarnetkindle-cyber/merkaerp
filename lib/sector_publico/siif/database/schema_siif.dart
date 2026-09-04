/// Esquema de base de datos para el módulo de SIIF Nación
/// Tabla de reportes SIIF Nación
library;

import 'package:sqflite/sqflite.dart';

class SchemaSIIF {
  /// Crea las tablas para SIIF Nación
  static Future<void> crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reportes_siif_nacion (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        tipo_reporte TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        mes INTEGER NOT NULL,
        fecha_generacion TEXT NOT NULL,
        usuario_genero TEXT NOT NULL,
        datos TEXT NOT NULL,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reportes_siif_entidad 
      ON reportes_siif_nacion(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reportes_siif_vigencia_mes 
      ON reportes_siif_nacion(vigencia, mes)
    ''');
  }
}
