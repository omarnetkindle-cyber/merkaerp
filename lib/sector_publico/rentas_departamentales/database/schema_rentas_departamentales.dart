import 'package:sqflite/sqflite.dart';

class SchemaRentasDepartamentales {
  const SchemaRentasDepartamentales._();

  static Future<void> crearTablas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contribuyentes_rentas_departamentales(
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        direccion TEXT NOT NULL,
        municipio TEXT NOT NULL,
        tipo_impuesto TEXT NOT NULL,
        email TEXT,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        UNIQUE(entidad_id, nit, tipo_impuesto)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS declaraciones_rentas_departamentales(
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        contribuyente_id TEXT NOT NULL,
        tipo_impuesto TEXT NOT NULL,
        periodo TEXT NOT NULL,
        fecha_declaracion TEXT NOT NULL,
        ingresos_gravables INTEGER NOT NULL DEFAULT 0,
        ingresos_no_gravables INTEGER NOT NULL DEFAULT 0,
        ingresos_exentos INTEGER NOT NULL DEFAULT 0,
        base_gravable INTEGER NOT NULL DEFAULT 0,
        tarifa REAL NOT NULL DEFAULT 0,
        impuesto INTEGER NOT NULL DEFAULT 0,
        saldo_pendiente INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'pendiente_pago',
        FOREIGN KEY(contribuyente_id)
          REFERENCES contribuyentes_rentas_departamentales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pagos_rentas_departamentales(
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        declaracion_id TEXT NOT NULL,
        valor_pagado INTEGER NOT NULL DEFAULT 0,
        fecha_pago TEXT NOT NULL,
        referencia_pago TEXT NOT NULL,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'aplicado',
        FOREIGN KEY(declaracion_id)
          REFERENCES declaraciones_rentas_departamentales(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rentas_deptales_contribuyentes_entidad
      ON contribuyentes_rentas_departamentales(entidad_id, estado)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rentas_deptales_contribuyentes_tipo
      ON contribuyentes_rentas_departamentales(entidad_id, tipo_impuesto)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rentas_deptales_declaraciones_entidad
      ON declaraciones_rentas_departamentales(entidad_id, periodo, estado)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rentas_deptales_pagos_entidad
      ON pagos_rentas_departamentales(entidad_id, fecha_pago)
    ''');
  }
}
