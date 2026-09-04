/// Esquema de base de datos para el módulo de Presupuesto Público
/// Implementa el flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:sqflite/sqflite.dart';

class SchemaPresupuesto {
  /// Crea todas las tablas necesarias para el módulo de presupuesto
  static Future<void> crearTablas(Database db) async {
    // Tabla de apropiaciones presupuestales
    await db.execute('''
      CREATE TABLE IF NOT EXISTS apropiaciones (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        nombre_rubro TEXT NOT NULL,
        valor_inicial INTEGER NOT NULL,
        valor_apropiado INTEGER NOT NULL,
        valor_cdp INTEGER NOT NULL DEFAULT 0,
        valor_rp INTEGER NOT NULL DEFAULT 0,
        valor_obligado INTEGER NOT NULL DEFAULT 0,
        valor_pagado INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        fuente_financiacion TEXT NOT NULL,
        sector TEXT NOT NULL,
        programa TEXT NOT NULL,
        subprograma TEXT NOT NULL,
        proyecto TEXT NOT NULL,
        actividad TEXT NOT NULL,
        objeto_gasto TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_aprobacion_concejo TEXT NOT NULL,
        acto_administrativo TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, vigencia, codigo_rubro)
      )
    ''');

    // Tabla de CDPs
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_cdp TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        apropiacion_id TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        valor_cdp INTEGER NOT NULL,
        valor_comprometido_rp INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        fecha_expedicion TEXT NOT NULL,
        fecha_vigencia TEXT NOT NULL,
        funcionario_expedidor TEXT NOT NULL,
        funcionario_solicitante TEXT NOT NULL,
        objeto_gasto TEXT NOT NULL,
        contrato_numero TEXT,
        estado TEXT NOT NULL,
        acto_administrativo_modificacion TEXT,
        fecha_modificacion TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (apropiacion_id) REFERENCES apropiaciones(id)
      )
    ''');

    // Tabla de RPs
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_rp TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        cdp_id TEXT NOT NULL,
        numero_cdp TEXT NOT NULL,
        contrato_id TEXT NOT NULL,
        contrato_numero TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        valor_rp INTEGER NOT NULL,
        valor_obligado INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        fecha_expedicion TEXT NOT NULL,
        fecha_vigencia TEXT NOT NULL,
        funcionario_expedidor TEXT NOT NULL,
        funcionario_solicitante TEXT NOT NULL,
        objeto_gasto TEXT NOT NULL,
        estado TEXT NOT NULL,
        acto_administrativo_modificacion TEXT,
        fecha_modificacion TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (cdp_id) REFERENCES cdps(id)
      )
    ''');

    // Tabla de obligaciones
    await db.execute('''
      CREATE TABLE IF NOT EXISTS obligaciones (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_obligacion TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        rp_id TEXT NOT NULL,
        numero_rp TEXT NOT NULL,
        contrato_id TEXT NOT NULL,
        contrato_numero TEXT NOT NULL,
        tercero_id TEXT NOT NULL,
        tercero_nombre TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        valor_obligacion INTEGER NOT NULL,
        valor_pagado INTEGER NOT NULL DEFAULT 0,
        saldo_pendiente INTEGER NOT NULL,
        fecha_reconocimiento TEXT NOT NULL,
        funcionario_reconocio TEXT NOT NULL,
        objeto_gasto TEXT NOT NULL,
        acta_recibo_numero TEXT,
        acta_recibo_fecha TEXT,
        factura_numero TEXT,
        factura_fecha TEXT,
        estado TEXT NOT NULL,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (rp_id) REFERENCES rps(id),
        FOREIGN KEY (tercero_id) REFERENCES terceros_sector_publico(id)
      )
    ''');

    // Tabla de pagos
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pagos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_pago TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        obligacion_id TEXT NOT NULL,
        numero_obligacion TEXT NOT NULL,
        rp_id TEXT NOT NULL,
        numero_rp TEXT NOT NULL,
        tercero_id TEXT NOT NULL,
        tercero_nombre TEXT NOT NULL,
        banco_destino TEXT NOT NULL,
        cuenta_destino TEXT NOT NULL,
        tipo_cuenta TEXT NOT NULL,
        valor_pago INTEGER NOT NULL,
        mes_pac INTEGER NOT NULL DEFAULT 0,
        fecha_programacion TEXT NOT NULL,
        fecha_aprobacion TEXT,
        fecha_ejecucion TEXT,
        funcionario_aprobo TEXT NOT NULL,
        funcionario_programo TEXT NOT NULL,
        tipo_pago TEXT NOT NULL,
        estado TEXT NOT NULL,
        numero_cheque TEXT,
        numero_referencia TEXT,
        observaciones TEXT,
        rechazo_motivo TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (obligacion_id) REFERENCES obligaciones(id),
        FOREIGN KEY (tercero_id) REFERENCES terceros_sector_publico(id)
      )
    ''');

    // Tabla de PAC
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pac (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        mes INTEGER NOT NULL,
        codigo_rubro TEXT NOT NULL,
        valor_programado INTEGER NOT NULL,
        valor_ejecutado INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_aprobacion TEXT,
        funcionario_aprobo TEXT,
        estado TEXT NOT NULL,
        acto_administrativo TEXT,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, vigencia, mes, codigo_rubro)
      )
    ''');

    // Tabla de embargos judiciales (informativo)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS embargos_judiciales (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_proceso TEXT NOT NULL,
        juzgado TEXT NOT NULL,
        tercero_id TEXT,
        tercero_nombre TEXT NOT NULL,
        valor_embargo INTEGER NOT NULL,
        fecha_registro TEXT NOT NULL,
        fecha_levantamiento TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (tercero_id) REFERENCES terceros_sector_publico(id)
      )
    ''');

    // Tabla de estampillas parafiscales
    await db.execute('''
      CREATE TABLE IF NOT EXISTS estampillas_parafiscales (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        nombre_estampilla TEXT NOT NULL,
        tarifa REAL NOT NULL,
        base_legal TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        observaciones TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // Índices para optimización
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_apropiaciones_entidad 
      ON apropiaciones(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_apropiaciones_vigencia 
      ON apropiaciones(vigencia)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cdps_entidad 
      ON cdps(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cdps_apropiacion 
      ON cdps(apropiacion_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rps_entidad 
      ON rps(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rps_cdp 
      ON rps(cdp_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_obligaciones_entidad 
      ON obligaciones(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_obligaciones_rp 
      ON obligaciones(rp_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pagos_entidad 
      ON pagos(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pagos_obligacion 
      ON pagos(obligacion_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pac_entidad 
      ON pac(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pac_vigencia_mes 
      ON pac(vigencia, mes)
    ''');

    await crearTablasVigenciasFuturas(db);
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_cdps_entidad_numero ON cdps(entidad_id, numero_cdp)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_rps_entidad_numero ON rps(entidad_id, numero_rp)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_obligaciones_entidad_numero ON obligaciones(entidad_id, numero_obligacion)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_pagos_entidad_numero ON pagos(entidad_id, numero_pago)',
    );
  }

  static Future<void> crearTablasVigenciasFuturas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS autorizaciones_vigencias_futuras (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        autorizacion_anterior_id TEXT,
        tipo TEXT NOT NULL CHECK (tipo IN ('ordinaria', 'excepcional')),
        regimen_presupuestal TEXT NOT NULL,
        causal_legal TEXT NOT NULL,
        objeto TEXT NOT NULL,
        proyecto_id TEXT,
        codigo_banco_proyectos TEXT,
        plan_desarrollo_referencia TEXT NOT NULL,
        mfmp_referencia TEXT NOT NULL,
        anio_inicio INTEGER NOT NULL,
        anio_fin INTEGER NOT NULL,
        monto_total INTEGER NOT NULL CHECK (monto_total > 0),
        apropiacion_vigencia_actual INTEGER NOT NULL DEFAULT 0,
        porcentaje_respaldo_actual REAL NOT NULL DEFAULT 0,
        confis_autoridad TEXT NOT NULL,
        confis_acto_numero TEXT NOT NULL,
        confis_acto_fecha TEXT NOT NULL,
        confis_soporte TEXT NOT NULL,
        corporacion_tipo TEXT NOT NULL,
        autorizacion_autoridad TEXT NOT NULL,
        autorizacion_acto_numero TEXT NOT NULL,
        autorizacion_acto_fecha TEXT NOT NULL,
        autorizacion_soporte TEXT NOT NULL,
        estatuto_presupuestal_ese TEXT,
        autoridad_competente_ese TEXT,
        acto_delegacion_ese TEXT,
        concepto_dnp TEXT,
        importancia_estrategica_acto TEXT,
        excepcion_ultimo_anio TEXT,
        estado TEXT NOT NULL CHECK (estado IN ('autorizada', 'revocada')),
        registrado_por TEXT NOT NULL,
        fecha_registro TEXT NOT NULL,
        motivo_version TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (autorizacion_anterior_id) REFERENCES autorizaciones_vigencias_futuras(id),
        UNIQUE(entidad_id, autorizacion_acto_numero, version)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vigencias_futuras_distribucion (
        id TEXT PRIMARY KEY,
        autorizacion_id TEXT NOT NULL,
        anio INTEGER NOT NULL,
        monto_autorizado INTEGER NOT NULL CHECK (monto_autorizado > 0),
        monto_comprometido INTEGER NOT NULL DEFAULT 0,
        monto_obligado INTEGER NOT NULL DEFAULT 0,
        monto_pagado INTEGER NOT NULL DEFAULT 0,
        saldo_disponible INTEGER NOT NULL,
        FOREIGN KEY (autorizacion_id) REFERENCES autorizaciones_vigencias_futuras(id),
        UNIQUE(autorizacion_id, anio)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS compromisos_vigencias_futuras (
        id TEXT PRIMARY KEY,
        autorizacion_id TEXT NOT NULL,
        distribucion_id TEXT NOT NULL,
        entidad_id TEXT NOT NULL,
        rp_id TEXT NOT NULL,
        anio INTEGER NOT NULL,
        monto_comprometido INTEGER NOT NULL CHECK (monto_comprometido > 0),
        monto_obligado INTEGER NOT NULL DEFAULT 0,
        monto_pagado INTEGER NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'vigente',
        registrado_por TEXT NOT NULL,
        fecha_registro TEXT NOT NULL,
        FOREIGN KEY (autorizacion_id) REFERENCES autorizaciones_vigencias_futuras(id),
        FOREIGN KEY (distribucion_id) REFERENCES vigencias_futuras_distribucion(id),
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (rp_id) REFERENCES rps(id),
        UNIQUE(rp_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS obligaciones_vigencias_futuras (
        id TEXT PRIMARY KEY,
        compromiso_id TEXT NOT NULL,
        obligacion_id TEXT NOT NULL UNIQUE,
        monto_obligado INTEGER NOT NULL CHECK (monto_obligado > 0),
        monto_pagado INTEGER NOT NULL DEFAULT 0,
        fecha_registro TEXT NOT NULL,
        FOREIGN KEY (compromiso_id) REFERENCES compromisos_vigencias_futuras(id),
        FOREIGN KEY (obligacion_id) REFERENCES obligaciones(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recepciones_satisfaccion (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        tercero_id TEXT NOT NULL,
        tercero_nombre TEXT NOT NULL,
        contrato_id TEXT,
        rp_id TEXT,
        obligacion_id TEXT,
        acta_numero TEXT NOT NULL,
        factura_numero TEXT,
        fecha_recepcion TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        valor_recibido INTEGER NOT NULL CHECK (valor_recibido > 0),
        valor_reconocido INTEGER NOT NULL CHECK (valor_reconocido > 0),
        asiento_contable_id TEXT,
        estado_contable TEXT NOT NULL,
        soporte TEXT NOT NULL,
        bloquea_pago INTEGER NOT NULL DEFAULT 0,
        registrado_por TEXT NOT NULL,
        fecha_registro TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (obligacion_id) REFERENCES obligaciones(id),
        FOREIGN KEY (asiento_contable_id) REFERENCES asientos_contables_sp(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS incidentes_recibido_sin_obligacion (
        id TEXT PRIMARY KEY,
        recepcion_id TEXT NOT NULL UNIQUE,
        entidad_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        reportado_por TEXT NOT NULL,
        fecha_reporte TEXT NOT NULL,
        revisado_por TEXT,
        concepto_juridico TEXT,
        ruta_regularizacion TEXT,
        estado TEXT NOT NULL DEFAULT 'abierto',
        bloquea_pago INTEGER NOT NULL DEFAULT 1 CHECK (bloquea_pago = 1),
        FOREIGN KEY (recepcion_id) REFERENCES recepciones_satisfaccion(id),
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_vigencias_futuras_entidad
      ON autorizaciones_vigencias_futuras(entidad_id, estado)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_compromisos_vigencias_rp
      ON compromisos_vigencias_futuras(rp_id, anio)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recepciones_bloqueo
      ON recepciones_satisfaccion(entidad_id, bloquea_pago)
    ''');
  }

  static Future<void> migrarVigenciasFuturas(Database db) async {
    await crearTablasVigenciasFuturas(db);
  }
}
