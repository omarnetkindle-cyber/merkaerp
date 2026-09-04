/// Esquema de base de datos multi-tenant jerárquico
/// Implementa NICSP 40 para consolidación de estados financieros
library;

import 'package:sqflite/sqflite.dart';
import '../configuracion/services/matriz_visibilidad_service.dart';

class SchemaMultiTenant {
  /// Crea todas las tablas necesarias para el módulo de Sector Público
  static Future<void> crearTablas(Database db) async {
    // Tabla de entidades territoriales (multi-tenant)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS entidades_territoriales (
        id TEXT PRIMARY KEY,
        company_id INTEGER,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        tipo_entidad TEXT NOT NULL,
        departamento TEXT,
        municipio TEXT,
        gobernacion_id TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_inicio_vigencia TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        plan_cuentas_cgc TEXT NOT NULL,
        configuracion_normativa TEXT NOT NULL,
        FOREIGN KEY (gobernacion_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // Tabla de auditoría append-only
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auditoria_registros (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id TEXT NOT NULL,
        usuario_nombre TEXT,
        ip_direccion TEXT,
        fecha_hora TEXT NOT NULL,
        tipo_evento TEXT NOT NULL,
        modulo TEXT NOT NULL,
        accion TEXT NOT NULL,
        valor_anterior TEXT NOT NULL,
        valor_nuevo TEXT NOT NULL,
        hash_anterior TEXT,
        hash_actual TEXT NOT NULL,
        referencia_id TEXT,
        observaciones TEXT,
        archivado INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    // Índices para auditoría
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auditoria_entidad 
      ON auditoria_registros(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auditoria_usuario 
      ON auditoria_registros(usuario_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auditoria_fecha 
      ON auditoria_registros(fecha_hora)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auditoria_tipo_evento 
      ON auditoria_registros(tipo_evento)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auditoria_referencia 
      ON auditoria_registros(referencia_id)
    ''');
    await crearTriggersAuditoriaInmutable(db);

    // Tabla de usuarios del sector público
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios_sector_publico (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id_merka TEXT NOT NULL,
        roles TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        fecha_creacion TEXT NOT NULL,
        fecha_ultima_actualizacion TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    // Tabla de configuración por entidad
    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracion_entidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        parametro TEXT NOT NULL,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        actualizado_por TEXT NOT NULL,
        tipo TEXT,
        subtipo TEXT,
        nombre_entidad TEXT,
        codigo_dane TEXT,
        departamento TEXT,
        municipio TEXT,
        fecha_configuracion TEXT,
        configurado_por TEXT,
        motivo_cambio TEXT,
        estado TEXT NOT NULL DEFAULT 'activo',
        vigente INTEGER NOT NULL DEFAULT 1,
        fecha_fin TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_configuracion_entidad_vigente
      ON configuracion_entidad(entidad_id, parametro)
      WHERE vigente = 1
    ''');

    await crearTablaModulosPorTipoEntidad(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracion_visibilidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        parametro TEXT NOT NULL DEFAULT 'tipo_entidad',
        valor TEXT NOT NULL DEFAULT '',
        tipo TEXT NOT NULL,
        subtipo TEXT,
        modulos_habilitados TEXT NOT NULL,
        motivo TEXT NOT NULL,
        fecha_configuracion TEXT NOT NULL,
        configurado_por TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        vigente INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await migrarConfiguracionVisibilidad(db);

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_configuracion_visibilidad_entidad
      ON configuracion_visibilidad(entidad_id, estado)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuraciones_generales (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        clave TEXT NOT NULL,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        actualizado_por TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_configuraciones_generales_entidad
      ON configuraciones_generales(entidad_id, estado)
    ''');

    // Tabla de plan de cuentas CGC por entidad
    await db.execute('''
      CREATE TABLE IF NOT EXISTS plan_cuentas_cgc (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        codigo_cuenta TEXT NOT NULL,
        nombre_cuenta TEXT NOT NULL,
        clase TEXT NOT NULL,
        grupo TEXT,
        subgrupo TEXT,
        cuenta TEXT,
        subcuenta TEXT,
        auxiliar TEXT,
        naturaleza TEXT NOT NULL,
        activa INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, codigo_cuenta)
      )
    ''');

    // Índice para plan de cuentas
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_plan_cuentas_entidad 
      ON plan_cuentas_cgc(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_plan_cuentas_codigo 
      ON plan_cuentas_cgc(codigo_cuenta)
    ''');

    // Tabla de terceros (proveedores, contratistas, beneficiarios)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS terceros_sector_publico (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        tipo_identificacion TEXT NOT NULL,
        numero_identificacion TEXT NOT NULL,
        digito_verificacion TEXT,
        razon_social TEXT NOT NULL,
        primer_nombre TEXT,
        segundo_nombre TEXT,
        primer_apellido TEXT,
        segundo_apellido TEXT,
        tipo_tercero TEXT NOT NULL,
        direccion TEXT,
        telefono TEXT,
        email TEXT,
        municipio TEXT,
        departamento TEXT,
        regimen_tributario TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        fecha_creacion TEXT NOT NULL,
        fecha_actualizacion TEXT,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, tipo_identificacion, numero_identificacion)
      )
    ''');

    // Índices para terceros
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_terceros_entidad 
      ON terceros_sector_publico(entidad_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_terceros_identificacion 
      ON terceros_sector_publico(numero_identificacion)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_terceros_tipo 
      ON terceros_sector_publico(tipo_tercero)
    ''');

    // Tabla de consolidación (NICSP 40)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS consolidacion_nicsp40 (
        id TEXT PRIMARY KEY,
        gobernacion_id TEXT NOT NULL,
        entidad_consolidada_id TEXT NOT NULL,
        periodo TEXT NOT NULL,
        tipo_consolidacion TEXT NOT NULL,
        datos_consolidacion TEXT NOT NULL,
        fecha_consolidacion TEXT NOT NULL,
        consolidado_por TEXT NOT NULL,
        estado TEXT NOT NULL,
        FOREIGN KEY (gobernacion_id) REFERENCES entidades_territoriales(id),
        FOREIGN KEY (entidad_consolidada_id) REFERENCES entidades_territoriales(id),
        UNIQUE(gobernacion_id, entidad_consolidada_id, periodo, tipo_consolidacion)
      )
    ''');

    // Índices para consolidación
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_consolidacion_gobernacion 
      ON consolidacion_nicsp40(gobernacion_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_consolidacion_periodo 
      ON consolidacion_nicsp40(periodo)
    ''');

    // Tabla de funcionarios responsables de la entidad (representante legal, ordenador del gasto, contador)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS funcionarios_entidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id TEXT,
        cargo_clave TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        identificacion TEXT NOT NULL,
        tarjeta_profesional TEXT,
        telefono TEXT NOT NULL,
        email TEXT NOT NULL,
        direccion TEXT NOT NULL,
        FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id),
        UNIQUE(entidad_id, cargo_clave)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_funcionarios_usuario ON funcionarios_entidad(usuario_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_funcionarios_entidad_usuario ON funcionarios_entidad(entidad_id, usuario_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_entidades_company_nit ON entidades_territoriales(company_id, nit)',
    );
  }

  /// Inserta datos semilla del Catálogo General de Cuentas (CGC)
  static Future<void> crearTriggersAuditoriaInmutable(Database db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_auditoria_registros_no_delete
      BEFORE DELETE ON auditoria_registros
      FOR EACH ROW
      BEGIN
        SELECT RAISE(ABORT, 'Los registros de auditoria no se pueden eliminar');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_auditoria_registros_update_controlado
      BEFORE UPDATE ON auditoria_registros
      FOR EACH ROW
      WHEN NOT (
        OLD.archivado = 0
        AND NEW.archivado = 1
        AND OLD.id IS NEW.id
        AND OLD.entidad_id IS NEW.entidad_id
        AND OLD.usuario_id IS NEW.usuario_id
        AND OLD.usuario_nombre IS NEW.usuario_nombre
        AND OLD.ip_direccion IS NEW.ip_direccion
        AND OLD.fecha_hora IS NEW.fecha_hora
        AND OLD.tipo_evento IS NEW.tipo_evento
        AND OLD.modulo IS NEW.modulo
        AND OLD.accion IS NEW.accion
        AND OLD.valor_anterior IS NEW.valor_anterior
        AND OLD.valor_nuevo IS NEW.valor_nuevo
        AND OLD.hash_anterior IS NEW.hash_anterior
        AND OLD.hash_actual IS NEW.hash_actual
        AND OLD.referencia_id IS NEW.referencia_id
        AND OLD.observaciones IS NEW.observaciones
      )
      BEGIN
        SELECT RAISE(ABORT, 'Los registros de auditoria solo se pueden archivar');
      END
    ''');
  }

  /// Completa columnas introducidas despues de la primera version del
  /// esquema, sin reescribir configuraciones de visibilidad existentes.
  static Future<void> migrarConfiguracionVisibilidad(
    DatabaseExecutor db,
  ) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['configuracion_visibilidad'],
    );
    if (tablas.isEmpty) return;

    final columnas = await db.rawQuery(
      'PRAGMA table_info(configuracion_visibilidad)',
    );
    final existentes = columnas.map((fila) => fila['name'] as String).toSet();
    if (!existentes.contains('parametro')) {
      await db.execute(
        "ALTER TABLE configuracion_visibilidad ADD COLUMN parametro TEXT NOT NULL DEFAULT 'tipo_entidad'",
      );
    }
    if (!existentes.contains('valor')) {
      await db.execute(
        "ALTER TABLE configuracion_visibilidad ADD COLUMN valor TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!existentes.contains('vigente')) {
      await db.execute(
        'ALTER TABLE configuracion_visibilidad ADD COLUMN vigente INTEGER NOT NULL DEFAULT 1',
      );
    }
  }

  /// Vincula el contexto legado de onboarding con el tenant público real.
  ///
  /// Las instalaciones anteriores guardaban `tipo_entidad=publica` en
  /// `company_settings`, pero no creaban una entidad territorial. La
  /// reparación solo actúa cuando ese valor explícito existe y es idempotente;
  /// no inventa entidades para empresas comerciales.
  static Future<void> migrarContextoPublicoDesdeCompanySettings(
    DatabaseExecutor db,
  ) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['entidades_territoriales'],
    );
    if (tablas.isEmpty) return;

    final columnas = await db.rawQuery(
      'PRAGMA table_info(entidades_territoriales)',
    );
    final nombres = columnas.map((fila) => fila['name'] as String).toSet();
    if (!nombres.contains('company_id')) {
      try {
        await db.execute(
          'ALTER TABLE entidades_territoriales ADD COLUMN company_id INTEGER',
        );
      } on DatabaseException catch (error) {
        if (!error.toString().toLowerCase().contains('duplicate column')) {
          rethrow;
        }
      }
    }

    final publicCompanies = await db.rawQuery('''
      SELECT c.id, c.name, c.tax_id, s.setting_value AS subtipo
      FROM companies c
      INNER JOIN company_settings mode
        ON mode.company_id = c.id
       AND mode.setting_key = 'tipo_entidad'
       AND mode.setting_value = 'publica'
      LEFT JOIN company_settings s
        ON s.company_id = c.id
       AND s.setting_key = 'subtipo_entidad_publica'
    ''');

    for (final company in publicCompanies) {
      await crearEntidadPublicaDesdeConfiguracion(
        db,
        companyId: company['id'] as int,
        nombreEmpresa: company['name']?.toString() ?? 'Entidad pública',
        nit: company['tax_id']?.toString(),
        subtipoLegado: company['subtipo']?.toString(),
      );
    }
  }

  /// Crea el tenant público asociado a un onboarding nuevo o legado.
  /// Devuelve el identificador estable que usan los servicios públicos.
  static Future<String> crearEntidadPublicaDesdeConfiguracion(
    DatabaseExecutor db, {
    required int companyId,
    required String nombreEmpresa,
    String? nit,
    String? subtipoLegado,
  }) async {
    final entidadId = 'ENT-${companyId.toString().padLeft(3, '0')}';
    final tipo = switch (subtipoLegado) {
      'municipio' => 'municipio',
      'gobernacion' => 'departamento',
      'hospital' => 'hospitalEse',
      'otro' => 'otroEnte',
      _ => 'otroEnte',
    };
    final subtipo = subtipoLegado == 'municipio' ? 'municipio' : null;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'entidades_territoriales',
      where: 'id = ?',
      whereArgs: [entidadId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('entidades_territoriales', {
        'id': entidadId,
        'company_id': companyId,
        'nit': (nit == null || nit.trim().isEmpty)
            ? 'PENDIENTE-$companyId'
            : nit.trim(),
        'razon_social': nombreEmpresa,
        'tipo_entidad': tipo,
        'fecha_creacion': now,
        'plan_cuentas_cgc': '{}',
        'configuracion_normativa':
            '{"origen":"onboarding","requiere_completar":true}',
      });
    } else if (existing.first['company_id'] == null) {
      await db.update(
        'entidades_territoriales',
        {'company_id': companyId},
        where: 'id = ?',
        whereArgs: [entidadId],
      );
    } else if (existing.first['company_id'] != companyId) {
      throw StateError(
        'La entidad $entidadId ya pertenece a otra empresa; no se puede '
        'reasignar silenciosamente el contexto público.',
      );
    }

    final config = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
      whereArgs: [entidadId, 'tipo_entidad'],
      limit: 1,
    );
    if (config.isEmpty) {
      await db.insert('configuracion_entidad', {
        'id': 'onboarding-$companyId-tipo-entidad',
        'entidad_id': entidadId,
        'parametro': 'tipo_entidad',
        'valor': tipo,
        'fecha_actualizacion': now,
        'actualizado_por': 'onboarding',
        'tipo': tipo,
        'subtipo': subtipo,
        'nombre_entidad': nombreEmpresa,
        'fecha_configuracion': now,
        'configurado_por': 'onboarding',
        'estado': 'activo',
        'vigente': 1,
      });
    }
    return entidadId;
  }

  static Future<void> migrarConfiguracionEntidadParaHistorial(
    Database db,
  ) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_entidad'",
    );
    if (tablas.isEmpty) return;

    final columnas = await db.rawQuery(
      'PRAGMA table_info(configuracion_entidad)',
    );
    final nombres = columnas
        .map((columna) => columna['name'] as String)
        .toSet();
    if (nombres.contains('vigente') && nombres.contains('fecha_fin')) return;

    const columnasPreservadas = [
      'id',
      'entidad_id',
      'parametro',
      'valor',
      'fecha_actualizacion',
      'actualizado_por',
      'tipo',
      'subtipo',
      'nombre_entidad',
      'codigo_dane',
      'departamento',
      'municipio',
      'fecha_configuracion',
      'configurado_por',
      'motivo_cambio',
      'estado',
    ];
    final columnasExistentes = columnasPreservadas
        .where(nombres.contains)
        .toList();
    final listaColumnas = columnasExistentes.join(', ');

    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE configuracion_entidad RENAME TO configuracion_entidad_legacy',
      );
      await txn.execute('''
        CREATE TABLE configuracion_entidad (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          parametro TEXT NOT NULL,
          valor TEXT NOT NULL,
          fecha_actualizacion TEXT NOT NULL,
          actualizado_por TEXT NOT NULL,
          tipo TEXT,
          subtipo TEXT,
          nombre_entidad TEXT,
          codigo_dane TEXT,
          departamento TEXT,
          municipio TEXT,
          fecha_configuracion TEXT,
          configurado_por TEXT,
          motivo_cambio TEXT,
          estado TEXT NOT NULL DEFAULT 'activo',
          vigente INTEGER NOT NULL DEFAULT 1,
          fecha_fin TEXT,
          FOREIGN KEY (entidad_id) REFERENCES entidades_territoriales(id)
        )
      ''');
      await txn.execute('''
        INSERT INTO configuracion_entidad ($listaColumnas, vigente, fecha_fin)
        SELECT $listaColumnas, 1, NULL
        FROM configuracion_entidad_legacy
      ''');
      await txn.execute('DROP TABLE configuracion_entidad_legacy');
      await txn.execute('''
        CREATE UNIQUE INDEX idx_configuracion_entidad_vigente
        ON configuracion_entidad(entidad_id, parametro)
        WHERE vigente = 1
      ''');
    });
  }

  static Future<void> crearTablaModulosPorTipoEntidad(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS modulos_por_tipo_entidad (
        tipo TEXT NOT NULL,
        subtipo TEXT NOT NULL DEFAULT '',
        modulo TEXT NOT NULL,
        PRIMARY KEY (tipo, subtipo, modulo)
      )
    ''');
    await MatrizVisibilidadService.poblarMatrizInicial(db);
  }

  /// Lleva el tipo público del onboarding comercial al esquema sectorial.
  static Future<void> migrarOnboardingLegado(Database db) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'company_settings'",
    );
    if (tablas.isEmpty) return;

    final configuraciones = await db.rawQuery('''
      SELECT tipo.company_id, subtipo.setting_value AS subtipo
      FROM company_settings tipo
      LEFT JOIN company_settings subtipo
        ON subtipo.company_id = tipo.company_id
        AND subtipo.setting_key = 'subtipo_entidad_publica'
      WHERE tipo.setting_key = 'tipo_entidad'
        AND tipo.setting_value = 'publica'
    ''');

    final ahora = DateTime.now().toIso8601String();
    for (final configuracion in configuraciones) {
      final companyId = configuracion['company_id'] as int;
      final tipo = _tipoEntidadDesdeOnboarding(
        configuracion['subtipo'] as String?,
      );
      final entidadId = companyId.toString();
      final entidad = await db.query(
        'entidades_territoriales',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [entidadId],
        limit: 1,
      );
      if (entidad.isEmpty) {
        // company_settings does not prove that a territorial entity with the
        // same identifier exists. Skip instead of fabricating an FK target.
        continue;
      }
      final existente = await db.query(
        'configuracion_entidad',
        where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
        whereArgs: [entidadId, 'tipo_entidad'],
      );
      final valores = {
        'valor': tipo,
        'tipo': tipo,
        'subtipo': null,
        'fecha_actualizacion': ahora,
        'actualizado_por': 'migracion_onboarding_legado',
        'configurado_por': 'migracion_onboarding_legado',
        'estado': 'activo',
        'vigente': 1,
      };

      if (existente.isEmpty) {
        await db.insert('configuracion_entidad', {
          'id': 'legacy-company-$companyId-tipo-entidad',
          'entidad_id': entidadId,
          'parametro': 'tipo_entidad',
          ...valores,
        });
      } else if (existente.single['configurado_por'] ==
          'migracion_onboarding_legado') {
        await db.update(
          'configuracion_entidad',
          valores,
          where: 'id = ?',
          whereArgs: [existente.single['id']],
        );
      }
    }
  }

  static String _tipoEntidadDesdeOnboarding(String? subtipo) {
    switch (subtipo) {
      case 'gobernacion':
        return 'departamento';
      case 'hospital':
        return 'hospitalEse';
      case 'otro':
        return 'otroEnte';
      case 'municipio':
      default:
        return 'municipio';
    }
  }

  static Future<void> insertarDatosSemillaCGC(
    Database db,
    String entidadId,
  ) async {
    // Clase 1 - Activo
    final cuentasClase1 = [
      [
        '1110',
        'Efectivo y equivalentes de efectivo',
        '1',
        '11',
        '110',
        '1110',
        '',
        'Deudora',
      ],
      ['1111', 'Caja General', '1', '11', '110', '1110', '1111', 'Deudora'],
      ['1112', 'Cajas Menores', '1', '11', '110', '1110', '1112', 'Deudora'],
      ['1120', 'Bancos', '1', '11', '110', '1120', '', 'Deudora'],
      [
        '1121',
        'Cuentas Corrientes',
        '1',
        '11',
        '110',
        '1120',
        '1121',
        'Deudora',
      ],
      [
        '1415',
        'Deudores por impuestos',
        '1',
        '14',
        '140',
        '1415',
        '',
        'Deudora',
      ],
      [
        '1640',
        'Propiedades, planta y equipo',
        '1',
        '16',
        '160',
        '1640',
        '',
        'Deudora',
      ],
      ['1920', 'Activos intangibles', '1', '19', '190', '1920', '', 'Deudora'],
    ];

    // Clase 2 - Pasivo
    final cuentasClase2 = [
      [
        '2401',
        'Cuentas por pagar a contratistas',
        '2',
        '24',
        '240',
        '2401',
        '',
        'Acreedora',
      ],
      [
        '2410',
        'Obligaciones fiscales',
        '2',
        '24',
        '240',
        '2410',
        '',
        'Acreedora',
      ],
      [
        '2510',
        'Beneficios a empleados',
        '2',
        '25',
        '250',
        '2510',
        '',
        'Acreedora',
      ],
    ];

    // Clase 3 - Patrimonio
    final cuentasClase3 = [
      ['3105', 'Capital fiscal', '3', '31', '310', '3105', '', 'Acreedora'],
      [
        '3115',
        'Resultado del ejercicio',
        '3',
        '31',
        '310',
        '3115',
        '',
        'Acreedora',
      ],
      [
        '3120',
        'Impacto acumulado de reexpresión',
        '3',
        '31',
        '310',
        '3120',
        '',
        'Acreedora',
      ],
    ];

    // Clase 4 - Ingresos
    final cuentasClase4 = [
      ['4111', 'Impuesto predial', '4', '41', '410', '4111', '', 'Acreedora'],
      [
        '4115',
        'Impuesto de industria y comercio',
        '4',
        '41',
        '410',
        '4115',
        '',
        'Acreedora',
      ],
      ['4401', 'Transferencias SGP', '4', '44', '440', '4401', '', 'Acreedora'],
      ['4802', 'Otros ingresos', '4', '48', '480', '4802', '', 'Acreedora'],
    ];

    // Clase 5 - Gastos
    final cuentasClase5 = [
      ['5101', 'Servicios personales', '5', '51', '510', '5101', '', 'Deudora'],
      ['5111', 'Gastos generales', '5', '51', '510', '5111', '', 'Deudora'],
      [
        '5120',
        'Transferencias pagadas',
        '5',
        '51',
        '510',
        '5120',
        '',
        'Deudora',
      ],
      ['5310', 'Depreciación', '5', '53', '530', '5310', '', 'Deudora'],
    ];

    // Clase 6 - Costo de ventas/servicios
    final cuentasClase6 = [
      [
        '6101',
        'Costo de producción de bienes',
        '6',
        '61',
        '610',
        '6101',
        '',
        'Deudora',
      ],
      [
        '6310',
        'Costo de la transformación',
        '6',
        '63',
        '630',
        '6310',
        '',
        'Deudora',
      ],
    ];

    // Clase 8 - Cuentas de orden deudoras
    final cuentasClase8 = [
      [
        '8110',
        'Derechos contingentes',
        '8',
        '81',
        '810',
        '8110',
        '',
        'Deudora',
      ],
      [
        '8390',
        'Bienes y valores entregados en custodia',
        '8',
        '83',
        '830',
        '8390',
        '',
        'Deudora',
      ],
    ];

    // Clase 9 - Cuentas de orden acreedoras
    final cuentasClase9 = [
      [
        '9110',
        'Responsabilidades contingentes',
        '9',
        '91',
        '910',
        '9110',
        '',
        'Acreedora',
      ],
      [
        '9390',
        'Bienes y valores recibidos en custodia',
        '9',
        '93',
        '930',
        '9390',
        '',
        'Acreedora',
      ],
    ];

    final todasLasCuentas = [
      ...cuentasClase1,
      ...cuentasClase2,
      ...cuentasClase3,
      ...cuentasClase4,
      ...cuentasClase5,
      ...cuentasClase6,
      ...cuentasClase8,
      ...cuentasClase9,
    ];

    final batch = db.batch();
    for (final cuenta in todasLasCuentas) {
      batch.insert('plan_cuentas_cgc', {
        'id': DateTime.now().millisecondsSinceEpoch.toString() + cuenta[0],
        'entidad_id': entidadId,
        'codigo_cuenta': cuenta[0],
        'nombre_cuenta': cuenta[1],
        'clase': cuenta[2],
        'grupo': cuenta[3],
        'subgrupo': cuenta[4],
        'cuenta': cuenta[5],
        'subcuenta': cuenta[6],
        'auxiliar': '',
        'naturaleza': cuenta[7],
        'activa': 1,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Crea una nueva entidad territorial en el sistema
  static Future<void> crearEntidad(
    Database db,
    String id,
    String nit,
    String razonSocial,
    String tipoEntidad,
    String? departamento,
    String? municipio,
    String? gobernacionId,
    String planCuentasCGC,
  ) async {
    await db.insert('entidades_territoriales', {
      'id': id,
      'nit': nit,
      'razon_social': razonSocial,
      'tipo_entidad': tipoEntidad,
      'departamento': departamento,
      'municipio': municipio,
      'gobernacion_id': gobernacionId,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_inicio_vigencia': DateTime.now().toIso8601String(),
      'activo': 1,
      'plan_cuentas_cgc': planCuentasCGC,
      'configuracion_normativa': '{}',
    });

    // Insertar plan de cuentas CGC inicial
    await insertarDatosSemillaCGC(db, id);
  }

  /// Obtiene todas las entidades consolidadas bajo una gobernación
  static Future<List<Map<String, dynamic>>> obtenerEntidadesConsolidadas(
    Database db,
    String gobernacionId,
  ) async {
    final resultados = await db.query(
      'entidades_territoriales',
      where: 'gobernacion_id = ? AND activo = 1',
      whereArgs: [gobernacionId],
    );
    return resultados;
  }

  /// Verifica si una entidad puede consolidar (es gobernación)
  static Future<bool> puedeConsolidar(Database db, String entidadId) async {
    final resultado = await db.query(
      'entidades_territoriales',
      where: 'id = ? AND tipo_entidad = ? AND activo = 1',
      whereArgs: [entidadId, 'gobernacion'],
    );
    return resultado.isNotEmpty;
  }
}
