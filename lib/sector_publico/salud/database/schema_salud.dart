/// Esquema de base de datos para el módulo de Salud Pública
/// RIPS + EPS/ADRES + Facturación + Glosas
library;

import 'package:sqflite/sqflite.dart';

import 'catalogos_salud_seed.dart';

class SchemaSalud {
  static Future<void> crearTablas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rips (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        tipo_rips TEXT NOT NULL,
        codigo_prestador TEXT NOT NULL,
        nombre_prestador TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        fecha_factura TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        codigo_paciente TEXT NOT NULL,
        nombre_paciente TEXT NOT NULL,
        tipo_identificacion TEXT NOT NULL,
        numero_identificacion TEXT NOT NULL,
        codigo_servicio TEXT NOT NULL,
        nombre_servicio TEXT NOT NULL,
        valor_servicio INTEGER NOT NULL,
        valor_copago INTEGER NOT NULL DEFAULT 0,
        valor_modera INTEGER NOT NULL DEFAULT 0,
        valor_neto INTEGER NOT NULL,
        diagnostico_principal TEXT,
        diagnostico_relacionado TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS glosas (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_glosa TEXT NOT NULL,
        tipo_glosa TEXT NOT NULL,
        rips_id TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        eps TEXT NOT NULL,
        motivo TEXT NOT NULL,
        valor_glosado INTEGER NOT NULL,
        valor_aceptado INTEGER NOT NULL,
        valor_rechazado INTEGER NOT NULL,
        fecha_generacion TEXT NOT NULL,
        fecha_envio TEXT NOT NULL,
        fecha_limite_respuesta TEXT,
        fecha_respuesta TEXT,
        estado TEXT NOT NULL,
        justificacion_respuesta TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (rips_id) REFERENCES rips(id)
      )
    ''');

    await _crearEstructuraRipsFev(db);

    // Tabla de Contratos EPS / ADRES
    // FK: entidad_id -> entidades_territoriales(id)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contratos_eps_adres (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_contrato TEXT NOT NULL,
        eps_adres_nombre TEXT NOT NULL,
        eps_adres_nit TEXT NOT NULL,
        regimen TEXT NOT NULL,
        monto_contrato INTEGER NOT NULL,
        monto_facturado INTEGER NOT NULL DEFAULT 0,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // Tabla de Facturas de Prestación de Servicios de Salud
    // FK: entidad_id -> entidades_territoriales(id)
    // FK: contrato_id -> contratos_eps_adres(id)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS facturas_salud (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        contrato_id TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        periodo TEXT NOT NULL,
        monto_total INTEGER NOT NULL,
        monto_glosado INTEGER NOT NULL DEFAULT 0,
        monto_pagado INTEGER NOT NULL DEFAULT 0,
        fecha_emision TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'emitida',
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (contrato_id) REFERENCES contratos_eps_adres(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rips_entidad ON rips(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rips_fecha ON rips(fecha_factura)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rips_paciente ON rips(numero_identificacion)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_glosas_entidad ON glosas(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_glosas_estado ON glosas(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_glosas_rips ON glosas(rips_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_glosas_limite_respuesta ON glosas(fecha_limite_respuesta)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contratos_eps_entidad ON contratos_eps_adres(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_facturas_salud_contrato ON facturas_salud(contrato_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_glosas_entidad_numero ON glosas(entidad_id, numero_glosa)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_contratos_eps_entidad_numero ON contratos_eps_adres(entidad_id, numero_contrato)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_facturas_salud_entidad_numero ON facturas_salud(entidad_id, numero_factura)',
    );
  }

  /// Migracion v69: conserva las filas RIPS legadas y agrega el formato FEV.
  static Future<void> migrarRipsFevYGlosas(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'glosas',
      'fecha_limite_respuesta',
      'TEXT',
    );
    await _crearEstructuraRipsFev(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_glosas_limite_respuesta ON glosas(fecha_limite_respuesta)',
    );
  }

  static Future<void> _crearEstructuraRipsFev(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rips_fev_documentos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        num_documento_id_obligado TEXT NOT NULL,
        cucon TEXT,
        contenido_json TEXT NOT NULL,
        version_tecnica TEXT NOT NULL DEFAULT '003-2026-07-15',
        estado_validacion_local TEXT NOT NULL,
        fecha_generacion TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_cups (
        codigo TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        tipo_servicio TEXT NOT NULL,
        fuente TEXT NOT NULL,
        version_fuente TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_cie10 (
        codigo TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        fuente TEXT NOT NULL,
        version_fuente TEXT NOT NULL
      )
    ''');

    await _sembrarCatalogosNormativos(db);
  }

  static Future<void> _sembrarCatalogosNormativos(Database db) async {
    final batch = db.batch();
    for (final item in catalogoCupsSeedRows()) {
      batch.insert('catalogo_cups', {
        'codigo': item.codigo,
        'nombre': item.nombre,
        'tipo_servicio': item.tipoServicio,
        'fuente': catalogoCupsVersion,
        'version_fuente': catalogoCupsVersion,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final item in catalogoCie10SeedRows()) {
      batch.insert('catalogo_cie10', {
        'codigo': item.codigo,
        'nombre': item.nombre,
        'fuente': 'Codigos MIPRES - Ministerio de Salud y Proteccion Social',
        'version_fuente': catalogoCie10Version,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _agregarColumnaSiNoExiste(
    Database db,
    String tabla,
    String columna,
    String definicion,
  ) async {
    final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
    if (columnas.any((columnaDb) => columnaDb['name'] == columna)) return;
    await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $definicion');
  }
}
