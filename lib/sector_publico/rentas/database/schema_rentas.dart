/// Esquema de base de datos para el módulo de Rentas
/// Predial, ICA, Intereses Moratorios, Cobro Coactivo
library;

import 'package:sqflite/sqflite.dart';

class SchemaRentas {
  /// Crea todas las tablas necesarias para el módulo de rentas
  static Future<void> crearTablas(Database db) async {
    // Tabla de predios
    await db.execute('''
      CREATE TABLE IF NOT EXISTS predios (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_predial TEXT NOT NULL,
        numero_matricula TEXT,
        direccion TEXT NOT NULL,
        barrio TEXT NOT NULL,
        municipio TEXT NOT NULL,
        departamento TEXT NOT NULL,
        area REAL NOT NULL,
        avaluo_catastral INTEGER NOT NULL,
        avaluo_anterior INTEGER NOT NULL,
        uso_suelo TEXT NOT NULL,
        estrato TEXT NOT NULL,
        zona TEXT NOT NULL,
        propietario_id TEXT NOT NULL,
        propietario_nombre TEXT NOT NULL,
        propietario_identificacion TEXT NOT NULL,
        poseedor_nombre TEXT,
        poseedor_identificacion TEXT,
        fecha_registro TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        exento INTEGER NOT NULL DEFAULT 0,
        motivo_exencion TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // Tabla de liquidaciones prediales
    await db.execute('''
      CREATE TABLE IF NOT EXISTS liquidaciones_prediales (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_liquidacion TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        predio_id TEXT NOT NULL,
        numero_predial TEXT NOT NULL,
        contribuyente_id TEXT NOT NULL,
        contribuyente_nombre TEXT NOT NULL,
        contribuyente_identificacion TEXT NOT NULL,
        avaluo_catastral INTEGER NOT NULL,
        tarifa REAL NOT NULL,
        impuesto_base INTEGER NOT NULL,
        descuento_pronto_pago INTEGER NOT NULL DEFAULT 0,
        intereses_mora INTEGER NOT NULL DEFAULT 0,
        total_pagar INTEGER NOT NULL,
        fecha_liquidacion TEXT NOT NULL,
        fecha_vencimiento TEXT NOT NULL,
        fecha_pago TEXT,
        estado TEXT NOT NULL,
        acuerdo_pago_id TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (predio_id) REFERENCES predios(id)
      )
    ''');

    // Tabla de acuerdos de pago
    await db.execute('''
      CREATE TABLE IF NOT EXISTS acuerdos_pago (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_acuerdo TEXT NOT NULL,
        liquidacion_id TEXT NOT NULL,
        numero_liquidacion TEXT NOT NULL,
        contribuyente_id TEXT NOT NULL,
        contribuyente_nombre TEXT NOT NULL,
        valor_original INTEGER NOT NULL,
        valor_pagado INTEGER NOT NULL DEFAULT 0,
        saldo_pendiente INTEGER NOT NULL,
        numero_cuotas INTEGER NOT NULL,
        valor_cuota INTEGER NOT NULL,
        fecha_firma TEXT NOT NULL,
        fecha_primera_cuota TEXT NOT NULL,
        periodicidad_dias INTEGER NOT NULL,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (liquidacion_id) REFERENCES liquidaciones_prediales(id)
      )
    ''');

    // Tabla de procesos de cobro coactivo
    await db.execute('''
      CREATE TABLE IF NOT EXISTS procesos_cobro_coactivo (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_proceso TEXT NOT NULL,
        liquidacion_id TEXT NOT NULL,
        numero_liquidacion TEXT NOT NULL,
        deudor_id TEXT NOT NULL,
        deudor_nombre TEXT NOT NULL,
        valor_deuda INTEGER NOT NULL,
        valor_recuperado INTEGER NOT NULL DEFAULT 0,
        saldo_pendiente INTEGER NOT NULL,
        etapa_actual TEXT NOT NULL,
        estado TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_mandamiento_pago TEXT,
        fecha_embargo TEXT,
        fecha_remate TEXT,
        fecha_terminacion TEXT,
        numero_resolucion TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (liquidacion_id) REFERENCES liquidaciones_prediales(id)
      )
    ''');

    // Tabla de tarifas prediales por municipio
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tarifas_prediales (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        uso_suelo TEXT NOT NULL,
        estrato TEXT NOT NULL,
        tarifa REAL NOT NULL,
        vigencia TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, uso_suelo, estrato, vigencia)
      )
    ''');

    // Tablas de Impuesto de Industria y Comercio (ICA)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS censo_ica (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        direccion TEXT NOT NULL,
        telefono TEXT NOT NULL,
        tipo_actividad TEXT NOT NULL,
        actividad_economica TEXT NOT NULL,
        ingresos_anuales_estimados INTEGER NOT NULL,
        email TEXT,
        estado TEXT NOT NULL DEFAULT 'activo',
        fecha_registro TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, nit)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS declaraciones_ica (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        contribuyente_id TEXT NOT NULL,
        periodo TEXT NOT NULL,
        periodo_declaracion TEXT NOT NULL,
        fecha_declaracion TEXT NOT NULL,
        ingresos_gravables INTEGER NOT NULL,
        ingresos_no_gravables INTEGER NOT NULL,
        ingresos_exentos INTEGER NOT NULL,
        base_gravable INTEGER NOT NULL,
        tarifa REAL NOT NULL,
        impuesto_ica INTEGER NOT NULL,
        intereses_mora INTEGER NOT NULL DEFAULT 0,
        total_pagar INTEGER NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente_pago',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (contribuyente_id) REFERENCES censo_ica(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reteica (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        nit_retenedor TEXT NOT NULL,
        nit_retenido TEXT NOT NULL,
        periodo TEXT NOT NULL,
        valor_retenido INTEGER NOT NULL,
        numero_factura TEXT NOT NULL,
        fecha_factura TEXT NOT NULL,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente_declaracion',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS avisos_tablero (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        contribuyente_id TEXT NOT NULL,
        periodo TEXT NOT NULL,
        tipo_aviso TEXT NOT NULL,
        valor_aviso INTEGER NOT NULL,
        ubicacion TEXT NOT NULL,
        area_metros REAL NOT NULL,
        tarifa REAL NOT NULL,
        impuesto_aviso INTEGER NOT NULL,
        fecha_registro TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente_pago',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (contribuyente_id) REFERENCES censo_ica(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pagos_ica (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        declaracion_id TEXT NOT NULL,
        periodo TEXT NOT NULL,
        valor_pagado INTEGER NOT NULL,
        fecha_pago TEXT NOT NULL,
        numero_recibo TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'aplicado',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (declaracion_id) REFERENCES declaraciones_ica(id)
      )
    ''');

    // Índices para optimización
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_censo_ica_entidad ON censo_ica(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_censo_ica_nit ON censo_ica(nit)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_declaraciones_ica_entidad ON declaraciones_ica(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_declaraciones_ica_contribuyente ON declaraciones_ica(contribuyente_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_declaraciones_ica_periodo ON declaraciones_ica(periodo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reteica_entidad ON reteica(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reteica_periodo ON reteica(periodo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_avisos_tablero_entidad ON avisos_tablero(entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pagos_ica_entidad ON pagos_ica(entidad_id)',
    );

    // Índices para optimización
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_predios_entidad 
      ON predios(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_predios_propietario 
      ON predios(propietario_identificacion)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_liquidaciones_entidad 
      ON liquidaciones_prediales(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_liquidaciones_vigencia 
      ON liquidaciones_prediales(vigencia)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_liquidaciones_predio 
      ON liquidaciones_prediales(predio_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_liquidaciones_contribuyente 
      ON liquidaciones_prediales(contribuyente_identificacion)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_acuerdos_liquidacion 
      ON acuerdos_pago(liquidacion_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cobro_coactivo_liquidacion 
      ON procesos_cobro_coactivo(liquidacion_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cobro_coactivo_deudor 
      ON procesos_cobro_coactivo(deudor_id)
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_predios_entidad_numero ON predios(entidad_id, numero_predial)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_liquidaciones_prediales_entidad_numero ON liquidaciones_prediales(entidad_id, numero_liquidacion)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_acuerdos_pago_entidad_numero ON acuerdos_pago(entidad_id, numero_acuerdo)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_cobro_coactivo_entidad_numero ON procesos_cobro_coactivo(entidad_id, numero_proceso)',
    );
  }

  /// Inserta tarifas prediales por defecto
  static Future<void> insertarTarifasPrediales(
    Database db,
    String entidadId,
    String vigencia,
  ) async {
    final tarifas = [
      // Residencial
      ['residencial', 'uno', 4.0],
      ['residencial', 'dos', 5.0],
      ['residencial', 'tres', 6.0],
      ['residencial', 'cuatro', 7.0],
      ['residencial', 'cinco', 8.0],
      ['residencial', 'seis', 10.0],
      // Comercial
      ['comercial', 'uno', 8.0],
      ['comercial', 'dos', 9.0],
      ['comercial', 'tres', 10.0],
      ['comercial', 'cuatro', 11.0],
      ['comercial', 'cinco', 12.0],
      ['comercial', 'seis', 14.0],
      // Industrial
      ['industrial', 'uno', 10.0],
      ['industrial', 'dos', 11.0],
      ['industrial', 'tres', 12.0],
      ['industrial', 'cuatro', 13.0],
      ['industrial', 'cinco', 14.0],
      ['industrial', 'seis', 16.0],
    ];

    final batch = db.batch();
    for (final tarifa in tarifas) {
      batch.insert('tarifas_prediales', {
        'id':
            DateTime.now().millisecondsSinceEpoch.toString() +
            (tarifa[0] as String) +
            (tarifa[1] as String),
        'entidad_id': entidadId,
        'uso_suelo': tarifa[0],
        'estrato': tarifa[1],
        'tarifa': tarifa[2],
        'vigencia': vigencia,
        'activo': 1,
      });
    }
    await batch.commit(noResult: true);
  }
}
