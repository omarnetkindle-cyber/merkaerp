part of '../../db_helper.dart';

extension DatabaseInitializer on DatabaseHelper {
  Future _crearDB(Database db, int version) async {
    // Tabla de productos del inventario
    await db.execute('''
      CREATE TABLE productos(
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id          INTEGER,
        codigo              TEXT    DEFAULT '',
        nombre              TEXT    NOT NULL,
        unidad_base         TEXT    NOT NULL,
        stock               REAL    DEFAULT 0,
        stock_minimo        REAL    DEFAULT 5,
        stock_maximo        REAL    DEFAULT 0,
        lead_time_days      INTEGER DEFAULT 7,
        costo               REAL    DEFAULT 0,
        precio              REAL    DEFAULT 0,
        impuesto_pct        REAL    DEFAULT 0,
        codigo_barras       TEXT    DEFAULT '',
        conversion_nombre   TEXT    DEFAULT '',
        conversion_cantidad REAL    DEFAULT 0,
        tipo_item           TEXT    DEFAULT 'producto',
        precio_incluye_iva  INTEGER DEFAULT 0
      )
    ''');

    // Tabla de ventas realizadas
    await db.execute('''
      CREATE TABLE ventas(
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id      INTEGER,
        producto_id     INTEGER DEFAULT 0,
        producto        TEXT    NOT NULL,
        cantidad        REAL    NOT NULL,
        precio_unitario REAL    DEFAULT 0,
        costo_unitario  REAL    DEFAULT 0,
        subtotal        REAL    DEFAULT 0,
        impuesto_pct    REAL    DEFAULT 0,
        impuesto_total  REAL    DEFAULT 0,
        total           REAL    NOT NULL,
        fecha           TEXT    NOT NULL,
        metodo_pago_id  INTEGER DEFAULT 1,
        estado          TEXT    DEFAULT 'emitida',
        created_by      TEXT
      )
    ''');

    // Tabla de movimientos de caja (ingresos y egresos)
    await db.execute('''
      CREATE TABLE movimientos_caja(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        tipo TEXT NOT NULL,
        concepto TEXT NOT NULL,
        monto REAL NOT NULL,
        fecha TEXT NOT NULL,
        origen TEXT NOT NULL DEFAULT 'caja'
      )
    ''');

    // Tabla detalle de ventas (fase 2.2)
    await db.execute('''
      CREATE TABLE ventas_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        venta_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (venta_id) REFERENCES ventas(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE compras(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,

        proveedor_id INTEGER,
        proveedor TEXT,

        numero_factura TEXT,

        subtotal REAL DEFAULT 0,
        impuesto_pct REAL DEFAULT 0,
        impuesto_total REAL DEFAULT 0,
        total REAL NOT NULL,

        fecha TEXT NOT NULL,
        fecha_factura TEXT,

        metodo_pago_id INTEGER,

        estado TEXT DEFAULT 'pagada',

        efectivo REAL DEFAULT 0,
        transferencia REAL DEFAULT 0,
        credito REAL DEFAULT 0,

        observacion TEXT
      )
      ''');

    await db.execute('''
      CREATE TABLE compras_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        compra_id INTEGER,
        producto_id INTEGER,
        producto TEXT,
        cantidad REAL,
        costo_unitario REAL,
        subtotal REAL
      )
      ''');
    await db.execute('''
        CREATE TABLE movimientos_inventario (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          producto_id INTEGER,
          tipo TEXT,
          cantidad REAL,
          stock_anterior REAL,
          stock_nuevo REAL,
          motivo TEXT,
          fecha TEXT
        )
      ''');

    await db.execute('''
      CREATE TABLE cuentas_por_pagar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        proveedor TEXT,
        proveedor_id INTEGER,
        compra_id INTEGER,
        numero_factura TEXT,
        total REAL NOT NULL,
        saldo REAL NOT NULL,
        estado TEXT NOT NULL, -- pendiente / pagada / parcial
        fecha TEXT NOT NULL,
        descripcion TEXT,
        FOREIGN KEY (proveedor_id) REFERENCES proveedores(id)
      )
      ''');
    // Tabla de métodos de pago
    await db.execute('''
      CREATE TABLE abonos_cxp(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cuenta_id INTEGER NOT NULL,
        monto REAL NOT NULL,
        metodo_pago TEXT,
        observacion TEXT,
        fecha TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE metodos_pago(
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre  TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE proveedores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        nit TEXT,
        telefono TEXT,
        direccion TEXT,
        email TEXT,
        contacto TEXT,
        estado TEXT DEFAULT 'activo',
        fecha TEXT
      )
    ''');

    await _crearTablasContables(db);
    await _crearTablasCartera(db);
    await _crearTablasControl(db);
    await _crearTablasEmpresaYComprobantes(db);
    await _crearTablasPeriodos(db);
    await _crearTablasConciliacion(db);
    await _crearTablasPresupuestos(db);
    await _crearTablasGestionAvanzada(db);
    await _crearTablasConfiguracionEmpresarial(db);
    await _crearTablasCatalogosMaestros(db);
    await _crearTablasComplementosERP(db);
    await _crearTablasPlataformaDistribuida(db);
    await _crearTablasConsolidacionArquitectonica(db);
    await _crearTablasSalesEnterprise(db);
    await _crearTablasPurchasesEnterprise(db);
    await _crearTablasFinalEnterprise(db);
    await _crearTablasInteligenciaOperativa(db);
    await _crearTablasExtensionesEmpresariales(db);
    await SchemaCrm.crearTablas(db);
    await SchemaHrm.crearTablas(db);
    await SchemaMrp.crearTablas(db);
    await SchemaImpact.crearTablas(db);
    await _agregarScopeDistribuidoATablas(db);
    await _sembrarPlanCuentas(db);
    await _sembrarSecuencias(db);

    // Crear tablas de los nuevos servicios implementados
    await CurrencyService.instance.createTables(db);
    await PaymentService.instance.createTables(db);
    await WebhookService.instance.createTables(db);
    await AdvancedInventoryService.instance.createTables(db);
    await PriceHistoryService.instance.createTables(db);
    await CompanyTransferService.instance.createTables(db);
    await CommissionService.instance.createTables(db);
    await OrderService.instance.createTables(db);
    await QuoteService.instance.createTables(db);
    await WarrantyService.instance.createTables(db);
    await TemplateService.instance.createTables(db);
    await GDPRService.instance.createTables(db);
    await SchemaDocumentManagement.createTables(db);
    await IntegrationSettingsService.instance.createTables(db);
    await SchemaDataMigration.createTables(db);

    // Crear tablas de los nuevos servicios del Sector Público
    print('Inicializando tablas del Sector Público para nueva instalación...');
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await SchemaAuditoria.crearTablas(db);
    await SchemaRentas.crearTablas(db);
    await SchemaRentasDepartamentales.crearTablas(db);
    await SchemaContratacion.crearTablas(db);
    await SchemaNomina.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);
    await SchemaActivos.crearTablas(db);
    await SchemaSalud.crearTablas(db);
    await SchemaRegalias.crearTablas(db);
    await SchemaTransparencia.crearTablas(db);
    await SchemaSIIF.crearTablas(db);

    // Métodos iniciales
    await db.insert('metodos_pago', {'nombre': 'EFECTIVO'});
    await db.insert('metodos_pago', {'nombre': 'TRANSFERENCIA'});
    await db.insert('metodos_pago', {'nombre': 'TARJETA'});
    await db.insert('metodos_pago', {'nombre': 'NEQUI'});
    await db.insert('metodos_pago', {'nombre': 'DAVIPLATA'});
    await db.insert('metodos_pago', {'nombre': 'CREDITO'});
    await db.insert('metodos_pago', {'nombre': 'PAGO MIXTO'});
    await _migrarAVersion43(db);
    if (version >= 75) {
      await MoneySchemaMigration.migrateV75(db);
    }
    if (version >= 87) {
      await RetentionSchemaMigration.migrateV87(db);
    }
    if (version >= 88) {
      await TaxReportSchemaMigration.migrateV88(db);
    }
    if (version >= 89) {
      await AccountingPeriodSchemaMigration.migrateV89(db);
    }
    if (version >= 90) {
      await PayrollSchemaMigration.migrateV90(db);
    }
    if (version >= 91) {
      await FinancialFrameworkSchemaMigration.migrateV91(db);
    }
    if (version >= 92) {
      await SchemaMultiTenant.migrarContextoPublicoDesdeCompanySettings(db);
    }
    if (version >= 93) {
      await SchemaMultiTenant.migrarConfiguracionVisibilidad(db);
    }
    if (version >= 94) {
      // Aplica la compatibilidad de v94 tambien a bases nuevas, porque
      // algunas tablas legacy se crean antes que los servicios modernos.
      await _migrarDB(db, 93, version);
    }
    if (version >= 95) {
      await _migrarDB(db, 94, version);
    }
    if (version >= 96) {
      await _migrarDB(db, 95, version);
    }
    if (version >= 111) {
      // La cadena histórica anterior se conserva por compatibilidad, pero las
      // instalaciones nuevas también deben recibir el aislamiento v111.
      await _migrarAislamientoMultiempresaV111(db);
    }
    if (version >= 112) {
      await SchemaNomina.migrarAuxilioAlimentacion(db);
    }
    if (version >= 113) {
      await _crearTablasAgentV113(db);
    }
  }

  /// Migraciones incrementales entre versiones de la base de datos.
  Future _migrarDB(Database db, int oldVersion, int newVersion) async {
    // v1 → v2
    if (oldVersion < 4) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS movimientos_caja(
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo     TEXT    NOT NULL,
        concepto TEXT    NOT NULL,
        monto    REAL    NOT NULL,
        fecha    TEXT    NOT NULL
      )
    ''');
    }

    // v2 → v3
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE ventas ADD COLUMN producto_id INTEGER DEFAULT 0',
      );

      await db.execute(
        'ALTER TABLE ventas ADD COLUMN precio_unitario REAL DEFAULT 0',
      );

      await db.execute(
        'ALTER TABLE ventas ADD COLUMN costo_unitario REAL DEFAULT 0',
      );
    }

    // v3 → v4
    if (oldVersion < 5) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS metodos_pago(
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre  TEXT NOT NULL UNIQUE
      )
    ''');

      await db.insert('metodos_pago', {'nombre': 'EFECTIVO'});
      await db.insert('metodos_pago', {'nombre': 'TRANSFERENCIA'});
      await db.insert('metodos_pago', {'nombre': 'TARJETA'});
      await db.insert('metodos_pago', {'nombre': 'NEQUI'});
      await db.insert('metodos_pago', {'nombre': 'DAVIPLATA'});
      await db.insert('metodos_pago', {'nombre': 'CREDITO'});

      await db.execute(
        'ALTER TABLE ventas ADD COLUMN metodo_pago_id INTEGER DEFAULT 1',
      );
    }

    // v8
    if (oldVersion < 8) {
      await db.execute(
        "ALTER TABLE compras ADD COLUMN estado TEXT DEFAULT 'pagada'",
      );
    }

    // v9
    if (oldVersion < 9) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS movimientos_inventario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        producto_id INTEGER,
        tipo TEXT,
        cantidad REAL,
        stock_anterior REAL,
        stock_nuevo REAL,
        motivo TEXT,
        fecha TEXT
      )
    ''');
    }

    // v10 → proveedores
    if (oldVersion < 12) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS proveedores(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        nit TEXT,
        telefono TEXT,
        direccion TEXT,
        email TEXT,
        contacto TEXT,
        estado TEXT DEFAULT 'activo',
        fecha TEXT
      )
    ''');
    }

    // transferencias
    await db.execute('''
    CREATE TABLE IF NOT EXISTS transferencias(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      origen TEXT NOT NULL,
      destino TEXT NOT NULL,
      monto REAL NOT NULL,
      concepto TEXT,
      fecha TEXT NOT NULL
    )
  ''');
    // v11
    if (oldVersion < 11) {
      await db.execute('ALTER TABLE compras ADD COLUMN proveedor_id INTEGER');

      await db.execute('ALTER TABLE compras ADD COLUMN numero_factura TEXT');

      await db.execute('ALTER TABLE compras ADD COLUMN fecha_factura TEXT');

      await db.execute('ALTER TABLE compras ADD COLUMN observacion TEXT');
    }

    // v12
    if (oldVersion < 14) {
      await db.execute(
        'ALTER TABLE cuentas_por_pagar ADD COLUMN proveedor_id INTEGER',
      );

      await db.execute(
        'ALTER TABLE cuentas_por_pagar ADD COLUMN numero_factura TEXT',
      );

      await db.execute(
        'ALTER TABLE cuentas_por_pagar ADD COLUMN compra_id INTEGER',
      );
    }
    // v15 → abonos cuentas por pagar
    if (oldVersion < 15) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS abonos_cxp(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cuenta_id INTEGER NOT NULL,
        monto REAL NOT NULL,
        metodo_pago TEXT,
        observacion TEXT,
        fecha TEXT NOT NULL
      )
    ''');
    }
    if (oldVersion < 16) {
      await db.execute('''
      ALTER TABLE compras ADD COLUMN efectivo REAL DEFAULT 0
    ''');

      await db.execute('''
      ALTER TABLE compras ADD COLUMN transferencia REAL DEFAULT 0
    ''');

      await db.execute('''
      ALTER TABLE compras ADD COLUMN credito REAL DEFAULT 0
    ''');
    }
    if (oldVersion < 17) {
      await db.insert('metodos_pago', {'nombre': 'PAGO MIXTO'});
    }
    if (oldVersion < 18) {
      await _crearTablasContables(db);
      await _sembrarPlanCuentas(db);
    }
    if (oldVersion < 19) {
      await _crearTablasCartera(db);
    }
    if (oldVersion < 20) {
      await _crearTablasControl(db);
      await _agregarColumnaSiNoExiste(db, 'ventas', 'cliente_id', 'INTEGER');
      await _agregarColumnaSiNoExiste(db, 'ventas', 'cliente', 'TEXT');
    }
    if (oldVersion < 21) {
      await _crearTablasEmpresaYComprobantes(db);
      await _sembrarSecuencias(db);
    }
    if (oldVersion < 22) {
      await _crearTablasPeriodos(db);
    }
    if (oldVersion < 23) {
      await _crearTablasConciliacion(db);
    }
    if (oldVersion < 24) {
      await _agregarColumnasImpuestos(db);
      await _crearTablasPresupuestos(db);
      await _sembrarPlanCuentas(db);
    }
    if (oldVersion < 25) {
      await _crearTablasGestionAvanzada(db);
    }
    if (oldVersion < 26) {
      await _agregarColumnaSiNoExiste(
        db,
        'ventas',
        'estado',
        "TEXT DEFAULT 'emitida'",
      );
    }
    if (oldVersion < 27) {
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'codigo_barras',
        "TEXT DEFAULT ''",
      );
    }
    if (oldVersion < 28) {
      await _agregarColumnaSiNoExiste(
        db,
        'empresa_config',
        'logo_path',
        'TEXT',
      );
      await _crearTablasMultiempresaYConfig(db);
    }
    if (oldVersion < 29) {
      await _crearTablasConfiguracionEmpresarial(db);
      await _sincronizarEmpresaLegacy(db);
    }
    if (oldVersion < 30) {
      await _agregarColumnaSiNoExiste(
        db,
        'compras',
        'efectivo',
        'REAL DEFAULT 0',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'compras',
        'transferencia',
        'REAL DEFAULT 0',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'compras',
        'credito',
        'REAL DEFAULT 0',
      );
    }
    if (oldVersion < 31) {
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'impuesto_pct',
        'REAL DEFAULT 0',
      );
      await _sembrarPlanCuentas(db);
    }
    if (oldVersion < 32) {
      await _agregarCompanyIdATablasOperativas(db);
    }

    if (oldVersion < 33) {
      await _crearTablasCatalogosMaestros(db);
      final companyId = await _sincronizarEmpresaLegacy(db);
      await _sembrarCatalogosMaestrosSiNecesario(db, companyId);
    }
    if (oldVersion < 34) {
      await _crearTablasComplementosERP(db);
      final companyId = await _sincronizarEmpresaLegacy(db);
      await _sembrarComplementosERPSiNecesario(db, companyId);
    }
    if (oldVersion < 35) {
      // Agregar columnas faltantes a cuentas_por_pagar para compras a crédito
      await _agregarColumnaSiNoExiste(
        db,
        'cuentas_por_pagar',
        'proveedor_id',
        'INTEGER',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'cuentas_por_pagar',
        'compra_id',
        'INTEGER',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'cuentas_por_pagar',
        'numero_factura',
        'TEXT',
      );
      // Agregar columnas a ventas para desglose de pagos mixtos
      await _agregarColumnaSiNoExiste(
        db,
        'ventas',
        'efectivo',
        'REAL DEFAULT 0',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'ventas',
        'transferencia',
        'REAL DEFAULT 0',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'ventas',
        'credito',
        'REAL DEFAULT 0',
      );
    }

    if (oldVersion < 36) {
      await _crearTablasPlataformaDistribuida(db);
      await _agregarScopeDistribuidoATablas(db);
      final companyId = await _sincronizarEmpresaLegacy(db);
      await _sembrarPlataformaDistribuidaSiNecesario(db, companyId);
    }
    if (oldVersion < 37) {
      await _crearTablasConsolidacionArquitectonica(db);
    }

    if (oldVersion < 38) {
      await _crearTablasSalesEnterprise(db);
      await _crearTablasPurchasesEnterprise(db);
    }
    if (oldVersion < 39) {
      await _crearTablasFinalEnterprise(db);
    }
    if (oldVersion < 40) {
      await _crearTablasInteligenciaOperativa(db);
    }
    if (oldVersion < 41) {
      await _crearTablasExtensionesEmpresariales(db);
    }
    if (oldVersion < 42) {
      await _crearTablasExtensionesEmpresariales(db);
    }
    if (oldVersion < 43) {
      await _migrarAVersion43(db);
    }
    if (oldVersion < 44) {
      await _migrarAVersion44(db);
    }
    if (oldVersion < 45) {
      await _migrarAVersion45(db);
    }
    if (oldVersion < 46) {
      await _migrarAVersion46(db);
    }
    if (oldVersion < 47) {
      await _migrarAVersion47(db);
    }
    if (oldVersion < 48) {
      await _migrarAVersion48(db);
    }
  }

  Future<void> _migrarAVersion44(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'cierres_caja',
      'base_apertura_siguiente',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'cierres_caja',
      'retiro_banco',
      'REAL DEFAULT 0',
    );
  }

  Future<void> _migrarAVersion45(Database db) async {
    // Migración para Control Center Robusto
    // La información de licencias se almacena en app_config
    // Los comandos remotos se procesan en tiempo real con CCCommandsProcessor

    // Los secretos de Control Center se almacenan en el almacén seguro del
    // sistema operativo. No sembrar secretos (ni placeholders) en SQLite.

    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('instalacion_bloqueada', '0')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('update_canal', 'stable')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('update_ultima_revision', '')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('update_version_ignorada', '')
    ''');

    // Registrar la migración en auditoría
    await registrarEventoAuditoria(
      accion: 'MIGRACION_DB_V45',
      entidad: 'base_datos',
      detalle:
          'Control Center Robusto - Licencias, Actualizaciones, Health Reporter',
    );
  }

  Future<void> _migrarAVersion46(
    Database db, {
    bool registrarAuditoria = true,
  }) async {
    // Migración para API REST Pública y Pasarelas de Pago

    // Tabla para API Keys
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_keys(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        key TEXT NOT NULL UNIQUE,
        permisos TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL,
        ultima_uso TEXT,
        rate_limit INTEGER NOT NULL DEFAULT 100,
        rate_window_minutes INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Tabla para logs de acceso a la API
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_access_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        api_key_id INTEGER NOT NULL,
        endpoint TEXT NOT NULL,
        metodo TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (api_key_id) REFERENCES api_keys(id)
      )
    ''');

    // Tabla para integraciones (WooCommerce, Shopify, PSE, Nequi)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS integraciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        config TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');

    // Tabla para transacciones PSE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pse_transacciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        transaction_id TEXT NOT NULL UNIQUE,
        reference TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        bank_code TEXT,
        bank_name TEXT,
        return_url TEXT,
        processed_at TEXT
      )
    ''');

    // Tabla para transacciones Nequi
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nequi_transacciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        transaction_id TEXT NOT NULL UNIQUE,
        phone_number TEXT NOT NULL,
        amount REAL NOT NULL,
        reference TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expiration_minutes INTEGER NOT NULL DEFAULT 30,
        processed_at TEXT
      )
    ''');

    // Tabla para webhooks recibidos
    await db.execute('''
      CREATE TABLE IF NOT EXISTS webhooks_recibidos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        source TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        signature TEXT,
        status TEXT NOT NULL,
        received_at TEXT NOT NULL,
        processed_at TEXT,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Configuración inicial para API Server
    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('api_server_enabled', '0')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO app_config (clave, valor) 
      VALUES ('api_server_port', '8080')
    ''');

    if (registrarAuditoria) {
      await registrarEventoAuditoria(
        accion: 'MIGRACION_DB_V46',
        entidad: 'base_datos',
        detalle:
            'API REST Pública - API Keys, Integraciones, Pasarelas Pago, Webhooks',
      );
    }
  }

  Future<void> _migrarAVersion47(Database db) async {
    // Migración para CRM Real

    // Tabla para oportunidades de venta
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_oportunidades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cliente_id INTEGER NOT NULL,
        cliente_nombre TEXT NOT NULL,
        titulo TEXT NOT NULL,
        etapa TEXT NOT NULL,
        valor_estimado REAL NOT NULL,
        probabilidad INTEGER NOT NULL DEFAULT 50,
        fecha_cierre_estimada TEXT NOT NULL,
        creado_en TEXT NOT NULL,
        vendedor_id INTEGER,
        vendedor_nombre TEXT,
        descripcion TEXT,
        prioridad TEXT NOT NULL DEFAULT 'media',
        motivo_perdida TEXT,
        ultima_actividad TEXT,
        actualizado_en TEXT
      )
    ''');

    // Tabla para actividades de CRM
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_actividades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        oportunidad_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        fecha TEXT NOT NULL,
        usuario_id INTEGER,
        usuario_nombre TEXT,
        resultado TEXT,
        FOREIGN KEY (oportunidad_id) REFERENCES crm_oportunidades(id)
      )
    ''');

    // Tabla para campañas de cobranza
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cobranza_campanas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        reglas TEXT NOT NULL,
        activa INTEGER NOT NULL DEFAULT 1,
        creada_en TEXT NOT NULL
      )
    ''');

    // Tabla para acciones de cobranza
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cobranza_acciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        campana_id INTEGER,
        cuenta_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        estado TEXT NOT NULL,
        programada_para TEXT,
        ejecutada_en TEXT,
        resultado TEXT,
        FOREIGN KEY (campana_id) REFERENCES cobranza_campanas(id)
      )
    ''');

    // Registrar la migración en auditoría
    await registrarEventoAuditoria(
      accion: 'MIGRACION_DB_V47',
      entidad: 'base_datos',
      detalle: 'CRM Real - Oportunidades, Actividades, Campañas de Cobranza',
    );
  }

  Future<void> _migrarAVersion48(Database db) async {
    // Migración para Operaciones Avanzadas

    // Tabla para recetas/BOM
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recetas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        producto_nombre TEXT NOT NULL,
        nombre TEXT NOT NULL,
        ingredientes TEXT NOT NULL,
        costo_total REAL NOT NULL,
        descripcion TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');

    // Tabla para órdenes de producción
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ordenes_produccion(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        producto_nombre TEXT NOT NULL,
        cantidad REAL NOT NULL,
        estado TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_inicio TEXT,
        fecha_completado TEXT,
        receta_id INTEGER,
        observaciones TEXT,
        asignado_a TEXT
      )
    ''');

    // Tabla para rutas de entrega
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rutas_entrega(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        fecha TEXT NOT NULL,
        conductor TEXT NOT NULL,
        vehiculo TEXT NOT NULL,
        estado TEXT NOT NULL,
        puntos TEXT NOT NULL,
        observaciones TEXT,
        hora_inicio TEXT,
        hora_fin TEXT,
        creado_en TEXT NOT NULL
      )
    ''');

    // Tabla para usuarios del portal
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portal_usuarios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cliente_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        tipo TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL,
        ultimo_acceso TEXT
      )
    ''');

    // Tabla para tokens de acceso al portal
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portal_tokens(
        token TEXT PRIMARY KEY,
        usuario_id INTEGER NOT NULL,
        expira_en TEXT NOT NULL,
        creado_en TEXT NOT NULL,
        FOREIGN KEY (usuario_id) REFERENCES portal_usuarios(id)
      )
    ''');

    // Registrar la migración en auditoría
    await registrarEventoAuditoria(
      accion: 'MIGRACION_DB_V48',
      entidad: 'base_datos',
      detalle:
          'Operaciones Avanzadas - Recetas, Producción, Rutas, Portal Clientes',
    );
  }

  Future<void> _migrarAVersion43(Database db) async {
    // 1. Crear tabla bancos
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bancos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        numero_cuenta TEXT,
        tipo TEXT,
        saldo_inicial REAL NOT NULL DEFAULT 0,
        cuenta_puc TEXT,
        fecha TEXT NOT NULL
      )
    ''');

    // 2. Crear tabla extractos_bancarios
    await db.execute('''
      CREATE TABLE IF NOT EXISTS extractos_bancarios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        banco_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        monto REAL NOT NULL,
        referencia TEXT,
        conciliado INTEGER NOT NULL DEFAULT 0,
        asiento_linea_id INTEGER,
        FOREIGN KEY (banco_id) REFERENCES bancos(id)
      )
    ''');

    // 3. Agregar columnas a empleados
    await _agregarColumnaSiNoExiste(db, 'empleados', 'metodo_pago', 'TEXT');
    await _agregarColumnaSiNoExiste(db, 'empleados', 'banco', 'TEXT');
    await _agregarColumnaSiNoExiste(db, 'empleados', 'numero_cuenta', 'TEXT');

    // 4. Agregar columnas a nomina_liquidaciones
    await _agregarColumnaSiNoExiste(
      db,
      'nomina_liquidaciones',
      'metodo_pago',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'nomina_liquidaciones',
      'banco',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'nomina_liquidaciones',
      'numero_cuenta',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'nomina_liquidaciones',
      'asiento_id',
      'INTEGER',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'nomina_liquidaciones',
      'movimiento_caja_id',
      'INTEGER',
    );

    // 5. Agregar columnas a activos_fijos
    await _agregarColumnaSiNoExiste(
      db,
      'activos_fijos',
      'fecha_depreciacion',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'activos_fijos',
      'tipo_depreciacion',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(db, 'activos_fijos', 'codigo_puc', 'TEXT');
    await _agregarColumnaSiNoExiste(
      db,
      'activos_fijos',
      'codigo_puc_depreciacion',
      'TEXT',
    );

    // 6. Agregar columnas a movimientos_caja
    await _agregarColumnaSiNoExiste(
      db,
      'movimientos_caja',
      'activo',
      'INTEGER DEFAULT 1',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'movimientos_caja',
      'banco_id',
      'INTEGER',
    );

    // 7. Agregar columnas a ventas y compras para mixed payment e impuestos/retenciones
    await _agregarColumnaSiNoExiste(db, 'ventas', 'efectivo', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'transferencia',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(db, 'ventas', 'credito', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'retefuente',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(db, 'ventas', 'reteiva', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(db, 'ventas', 'reteica', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(
      db,
      'ventas_detalle',
      'impuesto_pct',
      'REAL NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'ventas_detalle',
      'impuesto_total',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'retefuente_concepto',
      "TEXT NOT NULL DEFAULT 'otros_ingresos'",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'retefuente_base',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'retefuente_tasa',
      'REAL NOT NULL DEFAULT 0',
    );

    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'retefuente',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(db, 'compras', 'reteiva', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(db, 'compras', 'reteica', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(
      db,
      'compras_detalle',
      'impuesto_pct',
      'REAL NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras_detalle',
      'impuesto_total',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'retefuente_concepto',
      "TEXT NOT NULL DEFAULT 'compras'",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'retefuente_base',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'retefuente_tasa',
      'REAL NOT NULL DEFAULT 0',
    );
  }
}
