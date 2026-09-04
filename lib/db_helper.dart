// ============================================================
// db_helper.dart
// Capa de acceso a datos (SQLite).
// Maneja todas las operaciones de la base de datos local.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;
import 'package:path_provider/path_provider.dart';

import 'accounting/application/accounting_engine.dart';
import 'accounting/accounting_period_schema_migration.dart';
import 'accounting/financial_framework.dart';
import 'accounting/financial_framework_schema_migration.dart';
import 'catalog/domain/master_catalog.dart';
import 'core/branch/branch_context.dart';
import 'core/audit/audit_identity.dart';
import 'core/currency/currency.dart';
import 'core/currency/currency_service.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_schema_migration.dart';
import 'core/currency/money_value.dart';
import 'core/invoicing/xml/generator.dart';
import 'services/hardware_fingerprint_service.dart';
import 'core/multi_company/transfer_service.dart';
import 'core/payments/payment_service.dart';
import 'core/webhooks/webhook_service.dart';
import 'features/feature_registry.dart';
import 'features/feature_key.dart';
import 'inventory/application/advanced_inventory_service.dart';
import 'inventory/application/inventory_movement_service.dart';
import 'inventory/application/price_history_service.dart';
import 'models/company.dart';
import 'models/company_profile.dart';
import 'sales/application/commission_service.dart';
import 'sales/application/order_service.dart';
import 'sales/application/quote_service.dart';
import 'sales/application/warranty_service.dart';
import 'core/templates/template_service.dart';
import 'core/privacy/gdpr_service.dart';
import 'crm/database/schema_crm.dart';
import 'hrm/database/schema_hrm.dart';
import 'hrm/application/hrm_payroll_absence_service.dart';
import 'mrp/database/schema_mrp.dart';

import 'sector_publico/database/schema_multi_tenant.dart';
import 'sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'sector_publico/auditoria/database/schema_auditoria.dart';
import 'sector_publico/rentas/database/schema_rentas.dart';
import 'sector_publico/rentas_departamentales/database/schema_rentas_departamentales.dart';
import 'sector_publico/contratacion/database/schema_contratacion.dart';
import 'sector_publico/nomina/database/schema_nomina.dart';
import 'sector_publico/planeacion/database/schema_planeacion.dart';
import 'sector_publico/activos/database/schema_activos.dart';
import 'sector_publico/salud/database/schema_salud.dart';
import 'sector_publico/regalias/database/schema_regalias.dart';
import 'sector_publico/transparencia/database/schema_transparencia.dart';
import 'sector_publico/siif/database/schema_siif.dart';
import 'impact/database/schema_impact.dart';
import 'document_management/database/schema_document_management.dart';
import 'data_migration/database/schema_data_migration.dart';
import 'integrations/application/integration_settings_service.dart';
import 'sync/application/merka_sale_sync_outbox.dart';
import 'taxes/retention_schema_migration.dart';
import 'taxes/retention_rule_service.dart';
import 'taxes/tax_report_schema_migration.dart';
import 'taxes/payroll_schema_migration.dart';
import 'taxes/payroll_deduction_service.dart';
import 'taxes/payroll_withholding.dart';

part 'core/database/database_initializer.dart';

class ActiveCompanyConfiguration {
  const ActiveCompanyConfiguration({
    required this.companyId,
    required this.companyName,
    required this.features,
    required this.settings,
    required this.onboardingCompleted,
  });

  final int companyId;
  final String companyName;
  final Map<String, bool> features;
  final Map<String, String> settings;
  final bool onboardingCompleted;
}

/// Singleton que gestiona la base de datos SQLite de la aplicación.
class DatabaseHelper {
  static const int schemaVersion = 113;
  // Conserva el nombre histórico para no desconectar instalaciones existentes.
  // Backups/restores deben usar exactamente el mismo archivo que abre la app.
  static const String _dataProfile = String.fromEnvironment(
    'MERKAERP_DATA_PROFILE',
  );
  static String get _databaseFileName {
    final profile = _dataProfile.trim().toLowerCase();
    if (profile.isEmpty) return 'merka_erp_test_fresco.db';
    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(profile)) {
      throw StateError('MERKAERP_DATA_PROFILE inválido.');
    }
    return 'merka_erp_${profile}_fresco.db';
  }

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;
  static bool disableAutoLoadsForTests = false;

  DatabaseHelper._init();

  static Future<void> resetForTests() async {
    disableAutoLoadsForTests = false;
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    }
  }

  static void setTestDatabase(Database db) {
    _database = db;
  }

  /// Cierra la conexión singleton en pruebas y evita que una suite reutilice
  /// un handle de SQLite perteneciente a otro caso.
  Future<void> closeForTests() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  // ── Inicialización ────────────────────────────────────────

  /// Devuelve la instancia de la base de datos, creándola si no existe.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_databaseFileName);
    await _crearTablasYTriggersDeSincronizacion(_database!);
    return _database!;
  }

  Future<void> _crearTablasYTriggersDeSincronizacion(
    DatabaseExecutor db,
  ) async {
    // 1. Crear tabla local_changes si no existe
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // 2. Crear tabla sync_table_metadata si no existe
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_table_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        last_sync_timestamp TEXT NOT NULL,
        last_sync_record_id INTEGER
      )
    ''');

    // 3. Crear tabla sync_state y su registro de control
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        is_syncing INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      INSERT INTO sync_state (rowid, is_syncing) 
      SELECT 1, 0 WHERE NOT EXISTS (SELECT 1 FROM sync_state WHERE rowid = 1)
    ''');

    // 4. Crear triggers para productos
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_insert_productos AFTER INSERT ON productos
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('productos', NEW.id, 'insert', json_object('id', NEW.id, 'codigo', NEW.codigo, 'nombre', NEW.nombre, 'unidad_base', NEW.unidad_base, 'stock', NEW.stock, 'costo', NEW.costo, 'precio', NEW.precio, 'impuesto_pct', NEW.impuesto_pct, 'codigo_barras', NEW.codigo_barras, 'conversion_nombre', NEW.conversion_nombre, 'conversion_cantidad', NEW.conversion_cantidad), datetime('now'), 0);
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_update_productos AFTER UPDATE ON productos
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('productos', NEW.id, 'update', json_object('id', NEW.id, 'codigo', NEW.codigo, 'nombre', NEW.nombre, 'unidad_base', NEW.unidad_base, 'stock', NEW.stock, 'costo', NEW.costo, 'precio', NEW.precio, 'impuesto_pct', NEW.impuesto_pct, 'codigo_barras', NEW.codigo_barras, 'conversion_nombre', NEW.conversion_nombre, 'conversion_cantidad', NEW.conversion_cantidad), datetime('now'), 0);
      END;
    ''');

    // 5. Crear triggers para clientes
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_insert_clientes');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_insert_clientes AFTER INSERT ON clientes
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('clientes', NEW.id, 'insert', json_object(
          'id', NEW.id,
          'identificacion', NEW.documento,
          'nombre', NEW.nombre,
          'email', NEW.email,
          'telefono', NEW.telefono,
          'direccion', NEW.direccion,
          'ciudad', NULL,
          'tipo_cliente', NULL,
          'limite_credito', NULL,
          'saldo_actual', NULL,
          'activo', CASE WHEN NEW.estado = 'activo' THEN 1 ELSE 0 END,
          'updated_at', NEW.fecha
        ), datetime('now'), 0);
      END;
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_update_clientes');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_update_clientes AFTER UPDATE ON clientes
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('clientes', NEW.id, 'update', json_object(
          'id', NEW.id,
          'identificacion', NEW.documento,
          'nombre', NEW.nombre,
          'email', NEW.email,
          'telefono', NEW.telefono,
          'direccion', NEW.direccion,
          'ciudad', NULL,
          'tipo_cliente', NULL,
          'limite_credito', NULL,
          'saldo_actual', NULL,
          'activo', CASE WHEN NEW.estado = 'activo' THEN 1 ELSE 0 END,
          'updated_at', NEW.fecha
        ), datetime('now'), 0);
      END;
    ''');

    // 6. Crear triggers para ventas
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_insert_ventas');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_insert_ventas AFTER INSERT ON ventas
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('ventas', NEW.id, 'insert', json_object(
          'id', NEW.id,
          'numero_factura', CAST(NEW.id AS TEXT),
          'cliente_id', NULL,
          'fecha', NEW.fecha,
          'subtotal', NEW.subtotal,
          'iva', NEW.impuesto_total,
          'total', NEW.total,
          'metodo_pago', CASE WHEN NEW.metodo_pago_id = 1 THEN 'EFECTIVO' WHEN NEW.metodo_pago_id = 2 THEN 'TARJETA' ELSE 'TRANSFERENCIA' END,
          'estado', NEW.estado,
          'observaciones', NULL,
          'updated_at', NEW.fecha
        ), datetime('now'), 0);
      END;
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_update_ventas');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_update_ventas AFTER UPDATE ON ventas
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('ventas', NEW.id, 'update', json_object(
          'id', NEW.id,
          'numero_factura', CAST(NEW.id AS TEXT),
          'cliente_id', NULL,
          'fecha', NEW.fecha,
          'subtotal', NEW.subtotal,
          'iva', NEW.impuesto_total,
          'total', NEW.total,
          'metodo_pago', CASE WHEN NEW.metodo_pago_id = 1 THEN 'EFECTIVO' WHEN NEW.metodo_pago_id = 2 THEN 'TARJETA' ELSE 'TRANSFERENCIA' END,
          'estado', NEW.estado,
          'observaciones', NULL,
          'updated_at', NEW.fecha
        ), datetime('now'), 0);
      END;
    ''');

    // 7. Crear triggers para venta_items
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_insert_venta_items');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_insert_venta_items AFTER INSERT ON ventas_detalle
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('venta_items', NEW.id, 'insert', json_object('id', NEW.id, 'venta_id', NEW.venta_id, 'producto_id', NEW.producto_id, 'cantidad', NEW.cantidad, 'precio_unitario', NEW.precio_unitario, 'subtotal', NEW.subtotal), datetime('now'), 0);
      END;
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_update_venta_items');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_update_venta_items AFTER UPDATE ON ventas_detalle
      WHEN (SELECT is_syncing FROM sync_state WHERE rowid = 1) = 0
      BEGIN
        INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
        VALUES ('venta_items', NEW.id, 'update', json_object('id', NEW.id, 'venta_id', NEW.venta_id, 'producto_id', NEW.producto_id, 'cantidad', NEW.cantidad, 'precio_unitario', NEW.precio_unitario, 'subtotal', NEW.subtotal), datetime('now'), 0);
      END;
    ''');

    // 8. Carga retroactiva de datos existentes que no están en cola de sincronización
    await db.execute('''
      INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
      SELECT 'productos', CAST(id AS TEXT), 'insert', json_object('id', id, 'codigo', codigo, 'nombre', nombre, 'unidad_base', unidad_base, 'stock', stock, 'costo', costo, 'precio', precio, 'impuesto_pct', impuesto_pct, 'codigo_barras', codigo_barras, 'conversion_nombre', conversion_nombre, 'conversion_cantidad', conversion_cantidad), datetime('now'), 0
      FROM productos
      WHERE CAST(id AS TEXT) NOT IN (SELECT record_id FROM local_changes WHERE table_name = 'productos');
    ''');

    await db.execute('''
      INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
      SELECT 'clientes', CAST(id AS TEXT), 'insert', json_object(
        'id', id,
        'identificacion', documento,
        'nombre', nombre,
        'email', email,
        'telefono', telefono,
        'direccion', direccion,
        'ciudad', NULL,
        'tipo_cliente', NULL,
        'limite_credito', NULL,
        'saldo_actual', NULL,
        'activo', CASE WHEN estado = 'activo' THEN 1 ELSE 0 END,
        'updated_at', fecha
      ), datetime('now'), 0
      FROM clientes
      WHERE CAST(id AS TEXT) NOT IN (SELECT record_id FROM local_changes WHERE table_name = 'clientes');
    ''');

    await db.execute('''
      INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
      SELECT 'ventas', CAST(id AS TEXT), 'insert', json_object(
        'id', id,
        'numero_factura', CAST(id AS TEXT),
        'cliente_id', NULL,
        'fecha', fecha,
        'subtotal', subtotal,
        'iva', impuesto_total,
        'total', total,
        'metodo_pago', CASE WHEN metodo_pago_id = 1 THEN 'EFECTIVO' WHEN metodo_pago_id = 2 THEN 'TARJETA' ELSE 'TRANSFERENCIA' END,
        'estado', estado,
        'observaciones', NULL,
        'updated_at', fecha
      ), datetime('now'), 0
      FROM ventas
      WHERE CAST(id AS TEXT) NOT IN (SELECT record_id FROM local_changes WHERE table_name = 'ventas');
    ''');

    await db.execute('''
      INSERT INTO local_changes (table_name, record_id, operation, data, timestamp, synced)
      SELECT 'venta_items', CAST(id AS TEXT), 'insert', json_object('id', id, 'venta_id', venta_id, 'producto_id', producto_id, 'cantidad', cantidad, 'precio_unitario', precio_unitario, 'subtotal', subtotal), datetime('now'), 0
      FROM ventas_detalle
      WHERE CAST(id AS TEXT) NOT IN (SELECT record_id FROM local_changes WHERE table_name = 'venta_items');
    ''');
  }

  Future<String> _getAppDir() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    } catch (_) {
      // En pruebas FFI, path_provider no tiene canal nativo. Respetar el path
      // configurado en databaseFactory evita que distintas suites compartan
      // accidentalmente una base relativa al repositorio.
      return getDatabasesPath();
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await _getAppDir();
    final path = p.join(dbPath, filePath);

    // Windows/Linux necesitan sqflite_common_ffi.
    // Se inicializa aquí también como protección antes del openDatabase real.
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      debugPrint('Abriendo SQLite con FFI en: $path');
    }

    return await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        // Las migraciones reconstruyen algunas tablas para retirar restricciones
        // globales heredadas. SQLite exige hacerlo con las FK desactivadas antes
        // de iniciar la transacción de onUpgrade; onOpen las habilita siempre
        // antes de entregar la conexión a la aplicación.
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: _crearDB,
      onUpgrade: _migrarDB,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        final violations = await db.rawQuery('PRAGMA foreign_key_check');
        if (violations.isNotEmpty) {
          throw StateError(
            'La base de datos contiene relaciones inválidas después de migrar.',
          );
        }
      },
    );
  }

  @visibleForTesting
  Future<void> crearDBForTesting(Database db, int version) =>
      _crearDB(db, version);

  @visibleForTesting
  Future<void> migrarDBForTesting(
    Database db,
    int oldVersion,
    int newVersion,
  ) => _migrarDB(db, oldVersion, newVersion);

  Future<void> _migrarDB(Database db, int oldVersion, int newVersion) async {
    bool debeMigrar(int targetVersion) =>
        oldVersion < targetVersion && newVersion >= targetVersion;

    if (debeMigrar(77)) {
      await SchemaCrm.crearTablas(db);
    }
    if (debeMigrar(78)) {
      await SchemaHrm.crearTablas(db);
    }
    if (debeMigrar(79)) {
      await SchemaMrp.crearTablas(db);
    }
    if (debeMigrar(80)) {
      await SchemaHrm.crearTablas(db);
    }
    if (debeMigrar(81)) {
      final payrollTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['nomina_liquidaciones'],
      );
      if (payrollTables.isNotEmpty) {
        await _agregarColumnaSiNoExiste(
          db,
          'nomina_liquidaciones',
          'novedades_hrm',
          'TEXT',
        );
      }
      await SchemaNomina.migrarHrmEmployeeLink(db);
    }
    if (debeMigrar(82)) {
      await SchemaImpact.crearTablas(db);
    }
    if (debeMigrar(83)) {
      final mrpTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['mrp_workstations'],
      );
      if (mrpTables.isNotEmpty) {
        await _agregarColumnaSiNoExiste(
          db,
          'mrp_workstations',
          'available_hours_per_day',
          'REAL',
        );
      }
    }
    if (debeMigrar(84)) {
      await SchemaCrm.crearOpportunityItems(db);
    }
    if (debeMigrar(85)) {
      await SchemaHrm.crearTablas(db);
    }
    if (debeMigrar(86)) {
      await SchemaHrm.crearTablas(db);
    }

    if (debeMigrar(49)) {
      // Agregar columnas faltantes en auditoria_eventos
      await _agregarColumnaSiNoExiste(
        db,
        'auditoria_eventos',
        'old_values',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'auditoria_eventos',
        'new_values',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'auditoria_eventos',
        'ip_address',
        'TEXT',
      );

      // Crear tabla control_center_sync_queue
      await db.execute('''
        CREATE TABLE IF NOT EXISTS control_center_sync_queue(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          action TEXT NOT NULL,
          payload TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (debeMigrar(50)) {
      // Configurar endpoint del Control Center por defecto
      await db.insert('app_config', {
        'clave': 'control_center_endpoint',
        'valor': 'http://localhost:3000',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Configurar installation_id por defecto
      await db.insert('app_config', {
        'clave': 'control_center_installation_id',
        'valor': 'MERKA-LOCAL-001',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (debeMigrar(51)) {
      // Crear tabla warranties si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS warranties(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          venta_id INTEGER NOT NULL,
          producto_id INTEGER NOT NULL,
          numero_serie TEXT,
          descripcion_problema TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Recibido',
          fecha_recepcion TEXT NOT NULL,
          fecha_resolucion TEXT,
          resolucion TEXT,
          dias_garantia INTEGER NOT NULL DEFAULT 365,
          end_date TEXT,
          updated_at TEXT,
          product_name TEXT,
          customer_name TEXT
        )
      ''');

      // Crear tabla commissions
      await db.execute('''
        CREATE TABLE IF NOT EXISTS commissions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          venta_id INTEGER NOT NULL,
          vendedor_id INTEGER,
          cliente_id INTEGER,
          monto_venta REAL NOT NULL,
          porcentaje_comision REAL NOT NULL,
          monto_comision REAL NOT NULL,
          commission_amount REAL NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at TEXT NOT NULL,
          paid_at TEXT,
          FOREIGN KEY (venta_id) REFERENCES ventas(id)
        )
      ''');

      // Crear tabla document_templates
      await db.execute('''
        CREATE TABLE IF NOT EXISTS document_templates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          name TEXT NOT NULL,
          description TEXT,
          template_type TEXT NOT NULL,
          content TEXT NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT
        )
      ''');

      // Crear tabla webhooks si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS webhooks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          event TEXT NOT NULL,
          target_url TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      // Crear tabla currencies si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS currencies(
          code TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          symbol TEXT NOT NULL,
          is_base_currency INTEGER NOT NULL DEFAULT 0,
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }

    if (debeMigrar(52)) {
      // Crear tabla warranty_claims
      await db.execute('''
        CREATE TABLE IF NOT EXISTS warranty_claims(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          warranty_id INTEGER NOT NULL,
          claim_date TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          description TEXT,
          resolution TEXT,
          resolved_at TEXT,
          FOREIGN KEY (warranty_id) REFERENCES warranties(id)
        )
      ''');

      // Crear tabla commission_rules
      await db.execute('''
        CREATE TABLE IF NOT EXISTS commission_rules(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER,
          salesperson_id INTEGER,
          commission_percentage REAL NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT
        )
      ''');

      // Agregar columna is_default a currencies si no existe
      await _agregarColumnaSiNoExiste(
        db,
        'currencies',
        'is_default',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (debeMigrar(53)) {
      // Agregar columnas faltantes a warranties
      await _agregarColumnaSiNoExiste(db, 'warranties', 'product_name', 'TEXT');
      await _agregarColumnaSiNoExiste(
        db,
        'warranties',
        'customer_name',
        'TEXT',
      );

      // Agregar columna faltante a commissions
      await _agregarColumnaSiNoExiste(
        db,
        'commissions',
        'commission_amount',
        'REAL NOT NULL DEFAULT 0',
      );
    }

    if (debeMigrar(54)) {
      // Crear tabla tax_parameters
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tax_parameters(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          year INTEGER NOT NULL,
          company_id INTEGER,
          uvt_value REAL NOT NULL,
          retefuente_min_uvt INTEGER NOT NULL,
          retefuente_rate_declarante REAL NOT NULL,
          retefuente_rate_non_declarante REAL NOT NULL,
          reteica_base_rate REAL NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT,
          UNIQUE(year, company_id)
        )
      ''');
    }

    if (debeMigrar(55)) {
      // Agregar columna status a lotes si no existe
      await _agregarColumnaSiNoExiste(
        db,
        'lotes',
        'status',
        'TEXT NOT NULL DEFAULT "active"',
      );
    }

    if (debeMigrar(56)) {
      // Agregar columnas costo_anterior y costo_nuevo a movimientos_inventario
      await _agregarColumnaSiNoExiste(
        db,
        'movimientos_inventario',
        'costo_anterior',
        'REAL',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'movimientos_inventario',
        'costo_nuevo',
        'REAL',
      );
    }

    if (debeMigrar(57)) {
      // Actualizar catálogo de cuentas del PUC con datos completos
      // Incluir la cuenta 135518 y otras cuentas faltantes
      final cuentasPUC = [
        // Cuentas de Impuestos descontables (clase 1 - Activo)
        {
          'codigo': '135518',
          'nombre': 'Impuesto de Industria y comercio y retenido',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135520',
          'nombre': 'Impuesto de Industria y comercio descontable',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135525',
          'nombre': 'Impuesto de Avisos y Tableros retenido',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135530',
          'nombre': 'Impuesto de Avisos y Tableros descontable',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        // Cuentas de Impuestos por pagar (clase 2 - Pasivo)
        {
          'codigo': '240801',
          'nombre': 'IVA generados',
          'tipo': 'pasivo',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '240805',
          'nombre': 'IVA descontable',
          'tipo': 'pasivo',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '2365',
          'nombre': 'Retenciones en la fuente por pagar',
          'tipo': 'pasivo',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '236505',
          'nombre': 'Retención en la fuente por pagar a terceros',
          'tipo': 'pasivo',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '236510',
          'nombre': 'Retención en la fuente a cargo de terceros',
          'tipo': 'pasivo',
          'naturaleza': 'credito',
          'activa': 1,
        },
        // Cuentas de Ingresos (clase 4)
        {
          'codigo': '4135',
          'nombre': 'Comercio al por mayor y al por menor',
          'tipo': 'ingreso',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '413505',
          'nombre': 'Ventas de mercancías',
          'tipo': 'ingreso',
          'naturaleza': 'credito',
          'activa': 1,
        },
        {
          'codigo': '413510',
          'nombre': 'Servicios',
          'tipo': 'ingreso',
          'naturaleza': 'credito',
          'activa': 1,
        },
        // Cuentas de Costos (clase 6)
        {
          'codigo': '6135',
          'nombre': 'Costo de ventas',
          'tipo': 'costo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '613505',
          'nombre': 'Compras',
          'tipo': 'costo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '613510',
          'nombre': 'Devoluciones en ventas',
          'tipo': 'costo',
          'naturaleza': 'debito',
          'activa': 1,
        },
      ];

      for (final cuenta in cuentasPUC) {
        await db.insert(
          'cuentas_contables',
          cuenta,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (debeMigrar(58)) {
      // Importar todas las cuentas del PUC del archivo procesado
      // Leer el archivo de cuentas procesadas
      final pucFile = File(r'C:\Users\PC\Downloads\puc_processed.txt');
      if (await pucFile.exists()) {
        final lines = await pucFile.readAsLines();
        for (final line in lines) {
          final parts = line.split('|');
          if (parts.length == 4) {
            final codigo = parts[0].trim();
            final nombre = parts[1].trim();
            final tipo = parts[2].trim();
            final naturaleza = parts[3].trim();

            await db.insert('cuentas_contables', {
              'codigo': codigo,
              'nombre': nombre,
              'tipo': tipo,
              'naturaleza': naturaleza,
              'activa': 1,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }
    }

    if (debeMigrar(59)) {
      // Actualizar endpoint del Control Center al puerto correcto (3000)
      await db.update(
        'app_config',
        {'valor': 'http://localhost:3000'},
        where: 'clave = ?',
        whereArgs: ['control_center_endpoint'],
      );
    }

    if (debeMigrar(60)) {
      final cuentasNuevas = [
        {
          'codigo': '135515',
          'nombre': 'Retencion en la fuente',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135517',
          'nombre': 'Impuesto a las ventas y retenido',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135518',
          'nombre': 'Impuesto de Industria y comercio y retenido',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135520',
          'nombre': 'Impuesto de Industria y comercio descontable',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135525',
          'nombre': 'Impuesto de Avisos y Tableros retenido',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
        {
          'codigo': '135530',
          'nombre': 'Impuesto de Avisos y Tableros descontable',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'activa': 1,
        },
      ];
      for (final cuenta in cuentasNuevas) {
        await db.insert(
          'cuentas_contables',
          cuenta,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (debeMigrar(61)) {
      print(
        'Ejecutando migración v61: Inicializando tablas del Sector Público...',
      );
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
      print('✓ Tablas del Sector Público migradas correctamente en v61.');
    }

    if (debeMigrar(62)) {
      await SchemaNomina.crearTablas(db);
    }

    if (debeMigrar(63)) {
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'tipo',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'subtipo',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'nombre_entidad',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'codigo_dane',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'departamento',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'municipio',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'fecha_configuracion',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'configurado_por',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'motivo_cambio',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'configuracion_entidad',
        'estado',
        "TEXT NOT NULL DEFAULT 'activo'",
      );
      await SchemaMultiTenant.crearTablas(db);
    }

    if (debeMigrar(64)) {
      await SchemaMultiTenant.crearTriggersAuditoriaInmutable(db);
    }

    if (debeMigrar(65)) {
      await SchemaMultiTenant.migrarConfiguracionEntidadParaHistorial(db);
      await SchemaMultiTenant.crearTablaModulosPorTipoEntidad(db);
    }

    if (debeMigrar(66)) {
      await SchemaMultiTenant.migrarOnboardingLegado(db);
    }

    if (debeMigrar(67)) {
      await _agregarColumnaSiNoExiste(
        db,
        'pagos',
        'mes_pac',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (debeMigrar(68)) {
      await SchemaContratacion.migrarContratosConRPOpcional(db);
    }

    if (debeMigrar(69)) {
      await SchemaSalud.migrarRipsFevYGlosas(db);
    }

    if (debeMigrar(70)) {
      await SchemaNomina.migrarRegimenesYAportes(db);
    }

    if (debeMigrar(71)) {
      await SchemaPlaneacion.migrarTrazabilidadPlanPresupuesto(db);
    }

    if (debeMigrar(72)) {
      await SchemaRegalias.migrarDestinacionYOCAD(db);
    }

    if (debeMigrar(73)) {
      await SchemaContabilidad.migrarConciliacionesReciprocas(db);
    }

    if (debeMigrar(74)) {
      await SchemaPresupuesto.migrarVigenciasFuturas(db);
    }

    if (debeMigrar(75)) {
      await MoneySchemaMigration.migrateV75(db);
    }

    if (debeMigrar(76)) {
      await SchemaContabilidad.crearTriggersPartidaDoble(db);
    }
    if (debeMigrar(87)) {
      await RetentionSchemaMigration.migrateV87(db);
    }
    if (debeMigrar(88)) {
      await TaxReportSchemaMigration.migrateV88(db);
    }
    if (debeMigrar(89)) {
      await AccountingPeriodSchemaMigration.migrateV89(db);
    }
    if (debeMigrar(90)) {
      await PayrollSchemaMigration.migrateV90(db);
    }
    if (debeMigrar(91)) {
      await FinancialFrameworkSchemaMigration.migrateV91(db);
    }
    if (debeMigrar(92)) {
      await SchemaMultiTenant.migrarConfiguracionVisibilidad(db);
      await SchemaMultiTenant.migrarContextoPublicoDesdeCompanySettings(db);
    }
    if (debeMigrar(94)) {
      // Reaplica ambas correcciones de forma idempotente para instalaciones
      // que ya habian abierto la base con v92 antes de completar la migracion.
      await SchemaMultiTenant.migrarConfiguracionVisibilidad(db);
      await SchemaMultiTenant.migrarContextoPublicoDesdeCompanySettings(db);
      // La tabla de garantias nacio con nombres legacy y el servicio moderno
      // la consulta con nombres de dominio. Se agregan aliases nullable sin
      // reescribir datos existentes; los nuevos registros escriben ambos.
      Future<bool> tableExists(String tableName) async {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [tableName],
        );
        return rows.isNotEmpty;
      }

      const warrantyColumns = <String, String>{
        'sale_id': 'INTEGER',
        'sale_number': 'TEXT',
        'product_id': 'INTEGER',
        'product_name': 'TEXT',
        'customer_id': 'INTEGER',
        'customer_name': 'TEXT',
        'start_date': 'TEXT',
        'end_date': 'TEXT',
        'duration_months': 'INTEGER',
        'warranty_type': 'TEXT',
        'notes': 'TEXT',
        'created_at': 'TEXT',
        'updated_at': 'TEXT',
      };
      if (await tableExists('warranties')) {
        for (final entry in warrantyColumns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'warranties',
            entry.key,
            entry.value,
          );
        }
      }
      if (await tableExists('warranty_claims')) {
        await _agregarColumnaSiNoExiste(
          db,
          'warranty_claims',
          'issue_description',
          'TEXT',
        );
        await _agregarColumnaSiNoExiste(
          db,
          'warranty_claims',
          'resolved_date',
          'TEXT',
        );
      }
      // GDPR consulta el autor de la venta. Nullable preserva filas legacy
      // y evita atribuir retrospectivamente un usuario que no fue guardado.
      if (await tableExists('ventas')) {
        await _agregarColumnaSiNoExiste(db, 'ventas', 'created_by', 'TEXT');
      }
      const lotColumns = <String, String>{
        'lot_number': 'TEXT',
        'manufacturing_date': 'TEXT',
        'expiration_date': 'TEXT',
        'initial_quantity': 'REAL',
        'current_quantity': 'REAL',
        'supplier_id': 'TEXT',
        'purchase_document_id': 'TEXT',
        'status': "TEXT DEFAULT 'active'",
        'created_at': 'TEXT',
        'updated_at': 'TEXT',
      };
      if (await tableExists('inventory_lots')) {
        for (final entry in lotColumns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'inventory_lots',
            entry.key,
            entry.value,
          );
        }
      }
      const syncOutboxColumns = <String, String>{
        'event_id': 'TEXT',
        'user_id': 'TEXT',
        'table_name': 'TEXT',
        'operation': 'TEXT',
        'data': 'TEXT',
        'timestamp': 'TEXT',
        'processed': 'INTEGER DEFAULT 0',
        'error': 'TEXT',
      };
      if (await tableExists('sync_outbox')) {
        for (final entry in syncOutboxColumns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'sync_outbox',
            entry.key,
            entry.value,
          );
        }
      }
      const syncInboxColumns = <String, String>{
        'event_id': 'TEXT',
        'user_id': 'TEXT',
        'table_name': 'TEXT',
        'operation': 'TEXT',
        'data': 'TEXT',
        'timestamp': 'TEXT',
        'processed': 'INTEGER DEFAULT 0',
        'error': 'TEXT',
      };
      if (await tableExists('sync_inbox')) {
        for (final entry in syncInboxColumns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'sync_inbox',
            entry.key,
            entry.value,
          );
        }
      }
      const syncConflictColumns = <String, String>{
        'table_name': 'TEXT',
        'record_id': 'TEXT',
        'local_data': 'TEXT',
        'remote_data': 'TEXT',
        'resolved': 'INTEGER DEFAULT 0',
        'resolved_data': 'TEXT',
      };
      if (await tableExists('sync_conflicts')) {
        for (final entry in syncConflictColumns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'sync_conflicts',
            entry.key,
            entry.value,
          );
        }
      }
    }
    if (debeMigrar(95)) {
      // Campo nullable: protege filas legacy sin inventar el creador.
      final ventasExiste = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['ventas'],
      );
      if (ventasExiste.isNotEmpty) {
        await _agregarColumnaSiNoExiste(db, 'ventas', 'created_by', 'TEXT');
      }
    }
    if (debeMigrar(96)) {
      final warrantiesExiste = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['warranties'],
      );
      if (warrantiesExiste.isNotEmpty) {
        await _agregarColumnaSiNoExiste(db, 'warranties', 'updated_at', 'TEXT');
      }
    }
    if (debeMigrar(97)) {
      final copilotTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['conversaciones_copilot'],
      );
      if (copilotTable.isNotEmpty) {
        const columns = <String, String>{
          'usuario_id': 'TEXT',
          'tool_id': 'TEXT',
          'proveedor': "TEXT NOT NULL DEFAULT 'deterministic'",
          'resultado': "TEXT NOT NULL DEFAULT 'exitoso'",
          'detalle_error': 'TEXT',
          'acciones': 'TEXT',
        };
        for (final entry in columns.entries) {
          await _agregarColumnaSiNoExiste(
            db,
            'conversaciones_copilot',
            entry.key,
            entry.value,
          );
        }
      }
    }
    if (debeMigrar(98)) {
      await CompanyTransferService.instance.createTables(db);
    }
    if (debeMigrar(99)) {
      await RetentionSchemaMigration.migrateV99(db);
    }
    if (debeMigrar(100)) {
      await SchemaPlaneacion.migrarTrazabilidadPlanPresupuesto(db);
    }
    if (debeMigrar(101)) {
      await SchemaActivos.migrarFirmaActasResponsabilidad(db);
    }
    if (debeMigrar(102)) {
      await SchemaCrm.crearBacklogComercial(db);
    }
    if (debeMigrar(103)) {
      // Fix: cuentas_por_pagar creada antes de v35 no tenía proveedor_id,
      // compra_id ni numero_factura. La migración v35 en database_initializer
      // los agrega para upgrades, pero _crearDB no los incluía en la
      // definición inicial. Esta migración los garantiza en todas las
      // instalaciones existentes de forma idempotente.
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
    }
    if (debeMigrar(104)) {
      await SchemaMrp.migrarBacklogK(db);
    }
    if (debeMigrar(105)) {
      // Columnas agregadas en feat(services) / feat(tax) sin migración numerada.
      // tipo_item permite distinguir 'producto' vs 'servicio' (no descuenta stock).
      // precio_incluye_iva indica que el precio publicado ya contiene el IVA.
      // _agregarColumnaSiNoExiste es idempotente: no falla si ya existen.
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'tipo_item',
        "TEXT DEFAULT 'producto'",
      );
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'precio_incluye_iva',
        'INTEGER DEFAULT 0',
      );
    }
    if (debeMigrar(106)) {
      await SchemaDocumentManagement.createTables(db);
      await IntegrationSettingsService.instance.createTables(db);
    }
    if (debeMigrar(107)) {
      await SchemaDataMigration.createTables(db);
    }
    if (debeMigrar(108)) {
      // Inventario predictivo y reposición necesitan umbrales persistentes.
      // Versiones anteriores contenían consumidores de stock_minimo sin que
      // el esquema garantizara la columna, lo que podía fallar en runtime.
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'stock_minimo',
        'REAL DEFAULT 5',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'stock_maximo',
        'REAL DEFAULT 0',
      );
    }

    if (debeMigrar(109)) {
      // Consolida la supervisión contractual que ya existía en servicios pero
      // no estaba garantizada por el esquema de todas las instalaciones.
      await _agregarColumnaSiNoExiste(
        db,
        'contratos',
        'porcentaje_ejecucion',
        'REAL NOT NULL DEFAULT 0',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'contratos',
        'fecha_cierre_expediente',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(db, 'contratos', 'motivo_cierre', 'TEXT');
      await _agregarColumnaSiNoExiste(
        db,
        'contratos',
        'responsable_cierre',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'contratos',
        'documentos_requeridos',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'contratos',
        'documentos_pendientes',
        'TEXT',
      );
      await _agregarColumnaSiNoExiste(
        db,
        'productos',
        'lead_time_days',
        'INTEGER NOT NULL DEFAULT 7',
      );
      await SchemaContratacion.crearTablas(db);
    }

    if (debeMigrar(110)) {
      // La auditoría comercial identifica el equipo mediante una huella SHA-256
      // para mejorar trazabilidad sin almacenar seriales de hardware en claro.
      await _agregarColumnaSiNoExiste(
        db,
        'auditoria_eventos',
        'device_id',
        'TEXT',
      );
    }

    if (debeMigrar(111)) {
      await _migrarAislamientoMultiempresaV111(db);
    }
    if (debeMigrar(112)) {
      // Tablas faltantes para auxilio de alimentación del sector público
      // (Gap F3: AuxilioAlimentacionService, SchemaNomina).
      await SchemaNomina.migrarAuxilioAlimentacion(db);
    }
    if (debeMigrar(113)) {
      await _crearTablasAgentV113(db);
    }
  }

  Future<void> _crearTablasAgentV113(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS processed_command_ids (
        command_id TEXT PRIMARY KEY,
        nonce TEXT NOT NULL UNIQUE,
        action TEXT NOT NULL,
        installation_id TEXT NOT NULL,
        status TEXT NOT NULL,
        success INTEGER,
        message TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_ack (
        command_id TEXT PRIMARY KEY,
        installation_id TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '{}',
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_errors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload_json TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_jobs (
        id TEXT PRIMARY KEY,
        job_type TEXT NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        checksum_sha256 TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_ack_created ON pending_ack(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_telemetry_created ON pending_telemetry(created_at)',
    );
  }

  Future<void> _migrarAislamientoMultiempresaV111(Database db) async {
    // Algunas instalaciones nuevas anteriores solo creaban estas tablas al
    // recorrer migraciones antiguas. Garantizarlas aquí vuelve homogéneos los
    // esquemas nuevos y actualizados.
    await _migrarAVersion46(db, registrarAuditoria: false);
    final companyId = await _sincronizarEmpresaLegacy(db);

    // Las primeras versiones del Sector Público declaraban números de negocio
    // como UNIQUE global. Eso impedía que dos entidades usaran, por ejemplo,
    // CDP-001. La reconstrucción conserva datos, índices y triggers y cambia la
    // unicidad a índices compuestos por entidad.
    await db.execute('PRAGMA legacy_alter_table = ON');
    try {
      const scopedBusinessKeys = <(String, String)>[
        ('entidades_territoriales', 'nit'),
        ('procesos_contratacion', 'numero_proceso'),
        ('contratos', 'numero_contrato'),
        ('polizas', 'numero_poliza'),
        ('cdps', 'numero_cdp'),
        ('rps', 'numero_rp'),
        ('obligaciones', 'numero_obligacion'),
        ('pagos', 'numero_pago'),
        ('asientos_contables_sp', 'numero_asiento'),
        ('empleados_sp', 'numero_identificacion'),
        ('liquidaciones_nomina', 'numero_liquidacion'),
        ('retroactivos', 'numero_retroactivo'),
        ('predios', 'numero_predial'),
        ('liquidaciones_prediales', 'numero_liquidacion'),
        ('acuerdos_pago', 'numero_acuerdo'),
        ('procesos_cobro_coactivo', 'numero_proceso'),
        ('glosas', 'numero_glosa'),
        ('contratos_eps_adres', 'numero_contrato'),
        ('facturas_salud', 'numero_factura'),
        ('reportes_transparencia', 'numero_reporte'),
        ('procesos_disciplinarios', 'numero_proceso'),
        ('consolidaciones_nicsp40', 'numero_consolidacion'),
        ('regalias', 'numero_regalia'),
        ('sgp', 'numero_sgp'),
        ('bienios_sgr', 'codigo_bienio'),
        ('proyectos_ocad', 'codigo_bpin'),
        ('proyectos_mga', 'codigo_bpin'),
        ('pdt', 'vigencia'),
        ('activos_estado', 'numero_inventario'),
        ('fondo_unidad_tesoreria', 'numero_fut'),
        ('actas_responsabilidad', 'numero_acta'),
      ];
      for (final (table, column) in scopedBusinessKeys) {
        await _retirarUniqueGlobal(db, table: table, column: column);
      }
    } finally {
      await db.execute('PRAGMA legacy_alter_table = OFF');
    }

    // Reinstala índices (incluidos los UNIQUE compuestos) y triggers que hayan
    // sido eliminados junto con las tablas heredadas reconstruidas.
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await SchemaRentas.crearTablas(db);
    await SchemaRentasDepartamentales.crearTablas(db);
    await SchemaContratacion.crearTablas(db);
    await SchemaNomina.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);
    await SchemaActivos.crearTablas(db);
    await SchemaSalud.crearTablas(db);
    await SchemaRegalias.crearTablas(db);
    await SchemaTransparencia.crearTablas(db);

    Future<bool> schemaContains(String table, String fragment) async {
      final rows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      if (rows.isEmpty) return false;
      return (rows.first['sql']?.toString().toLowerCase() ?? '').contains(
        fragment.toLowerCase(),
      );
    }

    if (!await schemaContains(
      'secuencias_documentos',
      'unique(company_id, tipo)',
    )) {
      await db.execute(
        'ALTER TABLE secuencias_documentos RENAME TO secuencias_documentos_v110',
      );
      await db.execute('''
        CREATE TABLE secuencias_documentos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          prefijo TEXT NOT NULL,
          siguiente INTEGER NOT NULL DEFAULT 1,
          UNIQUE(company_id, tipo)
        )
      ''');
      await db.rawInsert(
        '''
        INSERT INTO secuencias_documentos(company_id, tipo, prefijo, siguiente)
        SELECT ?, tipo, prefijo, siguiente FROM secuencias_documentos_v110
      ''',
        [companyId],
      );
      await db.execute('DROP TABLE secuencias_documentos_v110');
    }

    if (!await schemaContains('usuarios', 'unique(company_id, usuario)')) {
      await db.execute('ALTER TABLE usuarios RENAME TO usuarios_v110');
      await db.execute('''
        CREATE TABLE usuarios(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER NOT NULL,
          nombre TEXT NOT NULL,
          usuario TEXT NOT NULL COLLATE NOCASE,
          rol TEXT NOT NULL,
          pin TEXT,
          activo INTEGER NOT NULL DEFAULT 1,
          fecha TEXT NOT NULL,
          UNIQUE(company_id, usuario)
        )
      ''');
      await db.rawInsert(
        '''
        INSERT INTO usuarios(id, company_id, nombre, usuario, rol, pin, activo, fecha)
        SELECT id, COALESCE(company_id, ?), nombre, usuario, rol, pin, activo, fecha
        FROM usuarios_v110
      ''',
        [companyId],
      );
      await db.execute('DROP TABLE usuarios_v110');
    }

    if (!await schemaContains(
      'facturas_electronicas',
      'unique(company_id, consecutivo)',
    )) {
      await db.execute(
        'ALTER TABLE facturas_electronicas RENAME TO facturas_electronicas_v110',
      );
      await db.execute('''
        CREATE TABLE facturas_electronicas(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER NOT NULL,
          venta_id INTEGER,
          prefijo TEXT NOT NULL DEFAULT 'FE',
          numero INTEGER NOT NULL,
          consecutivo TEXT NOT NULL,
          estado TEXT NOT NULL DEFAULT 'borrador',
          cufe TEXT,
          xml TEXT,
          respuesta_dian TEXT,
          fecha TEXT NOT NULL,
          validada TEXT,
          observacion TEXT,
          UNIQUE(company_id, consecutivo)
        )
      ''');
      await db.rawInsert(
        '''
        INSERT INTO facturas_electronicas(
          id, company_id, venta_id, prefijo, numero, consecutivo, estado,
          cufe, xml, respuesta_dian, fecha, validada, observacion
        )
        SELECT id, COALESCE(company_id, ?), venta_id, prefijo, numero,
          consecutivo, estado, cufe, xml, respuesta_dian, fecha, validada,
          observacion
        FROM facturas_electronicas_v110
      ''',
        [companyId],
      );
      await db.execute('DROP TABLE facturas_electronicas_v110');
    }

    if (!await schemaContains(
      'comprobantes_contables',
      'unique(company_id, consecutivo)',
    )) {
      await db.execute(
        'ALTER TABLE comprobantes_contables RENAME TO comprobantes_contables_v110',
      );
      await db.execute('''
        CREATE TABLE comprobantes_contables(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          prefijo TEXT NOT NULL,
          numero INTEGER NOT NULL,
          consecutivo TEXT NOT NULL,
          asiento_id INTEGER,
          fecha TEXT NOT NULL,
          concepto TEXT NOT NULL,
          tercero TEXT,
          total REAL NOT NULL DEFAULT 0,
          estado TEXT NOT NULL DEFAULT 'emitido',
          UNIQUE(company_id, consecutivo),
          FOREIGN KEY (asiento_id) REFERENCES asientos_contables(id)
        )
      ''');
      await db.rawInsert(
        '''
        INSERT INTO comprobantes_contables(
          id, company_id, tipo, prefijo, numero, consecutivo, asiento_id,
          fecha, concepto, tercero, total, estado
        )
        SELECT id, COALESCE(company_id, ?), tipo, prefijo, numero, consecutivo,
          asiento_id, fecha, concepto, tercero, total, estado
        FROM comprobantes_contables_v110
      ''',
        [companyId],
      );
      await db.execute('DROP TABLE comprobantes_contables_v110');
    }

    await db.update('empleados', {
      'company_id': companyId,
    }, where: 'company_id IS NULL');
    await db.update('api_keys', {
      'company_id': companyId,
    }, where: 'company_id IS NULL');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_empleados_company ON empleados(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_facturas_electronicas_company ON facturas_electronicas(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_api_keys_company ON api_keys(company_id)',
    );
  }

  Future<void> _retirarUniqueGlobal(
    Database db, {
    required String table,
    required String column,
  }) async {
    final schemaRows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (schemaRows.isEmpty) return;
    final originalSql = schemaRows.first['sql']?.toString();
    if (originalSql == null || originalSql.isEmpty) return;

    final globalUnique = RegExp(
      '\\b${RegExp.escape(column)}\\s+TEXT\\s+NOT\\s+NULL\\s+UNIQUE\\b',
      caseSensitive: false,
    );
    if (!globalUnique.hasMatch(originalSql)) return;

    final ancillaryRows = await db.rawQuery(
      '''
      SELECT type, sql FROM sqlite_master
      WHERE tbl_name = ? AND type IN ('index', 'trigger') AND sql IS NOT NULL
      ''',
      [table],
    );
    final columns = await db.rawQuery('PRAGMA table_info("$table")');
    if (columns.isEmpty) return;
    final quotedColumns = columns
        .map((row) => row['name']!.toString().replaceAll('"', '""'))
        .map((name) => '"$name"')
        .join(', ');
    final legacyTable = '${table}_global_unique_v110';
    final migratedSql = originalSql.replaceFirst(
      globalUnique,
      '$column TEXT NOT NULL',
    );

    await db.execute('ALTER TABLE "$table" RENAME TO "$legacyTable"');
    await db.execute(migratedSql);
    await db.execute(
      'INSERT INTO "$table" ($quotedColumns) '
      'SELECT $quotedColumns FROM "$legacyTable"',
    );
    await db.execute('DROP TABLE "$legacyTable"');
    for (final row in ancillaryRows) {
      final sql = row['sql']?.toString();
      if (sql != null && sql.isNotEmpty) await db.execute(sql);
    }
  }

  Future<String> obtenerRutaBaseDatos() async {
    final dbPath = await _getAppDir();
    return p.join(dbPath, _databaseFileName);
  }

  Future<Directory> _directorioRespaldos() async {
    final dbPath = await _getAppDir();
    final dir = Directory(p.join(dbPath, 'respaldos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> crearRespaldo() async {
    final db = await database;
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

    final origen = File(await obtenerRutaBaseDatos());
    final dir = await _directorioRespaldos();
    final ahora = DateTime.now();
    final nombre =
        'merkaerp_backup_${ahora.year}${ahora.month.toString().padLeft(2, '0')}${ahora.day.toString().padLeft(2, '0')}_${ahora.hour.toString().padLeft(2, '0')}${ahora.minute.toString().padLeft(2, '0')}${ahora.second.toString().padLeft(2, '0')}.db';
    final destino = File(p.join(dir.path, nombre));

    await origen.copy(destino.path);
    await registrarEventoAuditoria(
      accion: 'CREAR_RESPALDO',
      entidad: 'base_datos',
      detalle: destino.path,
    );

    return destino;
  }

  Future<List<File>> obtenerRespaldos() async {
    final dir = await _directorioRespaldos();
    final archivos = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.db'))
        .cast<File>()
        .toList();
    archivos.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return archivos;
  }

  Future<Map<String, Object?>> verificarRespaldo(String rutaRespaldo) async {
    final archivo = File(rutaRespaldo);
    if (!await archivo.exists()) {
      return const {'ok': false, 'message': 'El archivo no existe.'};
    }
    Database? verificacion;
    try {
      verificacion = await openDatabase(
        rutaRespaldo,
        readOnly: true,
        singleInstance: false,
      );
      final quick = await verificacion.rawQuery('PRAGMA quick_check');
      final status = quick.isEmpty
          ? 'unknown'
          : quick.first.values.first?.toString() ?? 'unknown';
      final versionRows = await verificacion.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as num?)?.toInt() ?? 0;
      final tables =
          Sqflite.firstIntValue(
            await verificacion.rawQuery(
              "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            ),
          ) ??
          0;
      final ok = status.toLowerCase() == 'ok' && tables > 0;
      return {
        'ok': ok,
        'message': ok
            ? 'Integridad SQLite verificada.'
            : 'SQLite reportó: $status',
        'user_version': version,
        'tables': tables,
        'size_bytes': await archivo.length(),
      };
    } catch (_) {
      return const {
        'ok': false,
        'message': 'El archivo no pudo abrirse como un respaldo SQLite válido.',
      };
    } finally {
      await verificacion?.close();
    }
  }

  Future<int> aplicarRetencionRespaldos({int conservar = 30}) async {
    final keep = conservar < 1 ? 1 : conservar;
    final respaldos = await obtenerRespaldos();
    if (respaldos.length <= keep) return 0;
    var eliminados = 0;
    for (final archivo in respaldos.skip(keep)) {
      try {
        await archivo.delete();
        eliminados++;
      } catch (_) {
        // La retención no debe interrumpir la operación por un archivo bloqueado.
      }
    }
    if (eliminados > 0) {
      await registrarEventoAuditoria(
        accion: 'RETENCION_RESPALDOS_APLICADA',
        entidad: 'base_datos',
        detalle: 'Conservar=$keep; eliminados=$eliminados',
      );
    }
    return eliminados;
  }

  Future<void> restaurarRespaldo(String rutaRespaldo) async {
    final respaldo = File(rutaRespaldo);
    if (!await respaldo.exists()) {
      throw Exception('El respaldo no existe.');
    }

    final verificacion = await verificarRespaldo(rutaRespaldo);
    if (verificacion['ok'] != true) {
      throw Exception(
        verificacion['message'] ??
            'El respaldo no superó la verificación de integridad.',
      );
    }

    // Crea un punto de retorno antes de reemplazar la base actual. Esto se hace
    // con la conexión aún abierta para forzar el checkpoint WAL correctamente.
    final rollback = await crearRespaldo();
    final actual = File(await obtenerRutaBaseDatos());
    final dbActual = _database;
    if (dbActual != null) {
      await dbActual.close();
      _database = null;
    }

    try {
      await respaldo.copy(actual.path);
      _database = await _initDB(_databaseFileName);
      final check = await _database!.rawQuery('PRAGMA quick_check');
      final status = check.isEmpty
          ? 'unknown'
          : check.first.values.first?.toString() ?? 'unknown';
      if (status.toLowerCase() != 'ok') {
        throw StateError('La base restaurada no superó quick_check: $status');
      }
      await registrarEventoAuditoria(
        accion: 'RESTAURAR_RESPALDO',
        entidad: 'base_datos',
        detalle: '$rutaRespaldo; rollback=${rollback.path}',
      );
    } catch (e) {
      // Recuperación automática usando la copia tomada inmediatamente antes.
      final abierta = _database;
      if (abierta != null) {
        await abierta.close();
        _database = null;
      }
      await rollback.copy(actual.path);
      _database = await _initDB(_databaseFileName);
      await registrarEventoAuditoria(
        accion: 'RESTAURAR_RESPALDO_REVERTIDO',
        entidad: 'base_datos',
        detalle: 'Error al restaurar; se recuperó ${rollback.path}',
      );
      rethrow;
    }
  }

  /// Crea todas las tablas en una instalación nueva.
  Future<void> _crearTablasInteligenciaOperativa(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'ubicacion_pasillo',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'ubicacion_estante',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'ubicacion_nivel',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'ubicacion_codigo',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'referencia',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'tipo_item',
      "TEXT DEFAULT 'producto'",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'precio_incluye_iva',
      'INTEGER DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'descripcion',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'has_warranty',
      "INTEGER DEFAULT 0",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'productos',
      'warranty_days',
      "INTEGER DEFAULT 365",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'movimientos_inventario',
      'costo_anterior',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'movimientos_inventario',
      'costo_nuevo',
      'REAL DEFAULT 0',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lotes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        codigo_lote TEXT NOT NULL,
        fecha_vencimiento TEXT,
        cantidad REAL NOT NULL DEFAULT 0,
        costo REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        FOREIGN KEY (producto_id) REFERENCES productos(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS series(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        numero_serie TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'disponible',
        created_at TEXT NOT NULL,
        FOREIGN KEY (producto_id) REFERENCES productos(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notificaciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        tipo TEXT NOT NULL,
        prioridad TEXT NOT NULL,
        titulo TEXT NOT NULL,
        detalle TEXT,
        entidad TEXT,
        entidad_id INTEGER,
        leida INTEGER NOT NULL DEFAULT 0,
        creada_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS preferencias_usuario(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario TEXT NOT NULL,
        clave TEXT NOT NULL,
        valor TEXT,
        actualizado_en TEXT NOT NULL,
        UNIQUE(usuario, clave)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversaciones_copilot(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        usuario TEXT NOT NULL,
        usuario_id TEXT,
        modulo TEXT,
        rol TEXT,
        mensaje_usuario TEXT NOT NULL,
        respuesta TEXT NOT NULL,
        intent TEXT NOT NULL,
        tool_id TEXT,
        proveedor TEXT NOT NULL DEFAULT 'deterministic',
        resultado TEXT NOT NULL DEFAULT 'exitoso',
        detalle_error TEXT,
        acciones TEXT,
        creada_en TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasExtensionesEmpresariales(Database db) async {
    await _agregarColumnaSiNoExiste(
      db,
      'bodegas',
      'direccion',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'bodegas',
      'telefono',
      "TEXT DEFAULT ''",
    );
    await _agregarColumnaSiNoExiste(
      db,
      'bodegas',
      'estado',
      "TEXT DEFAULT 'activa'",
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_bodega(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        bodega_id INTEGER NOT NULL,
        cantidad REAL NOT NULL DEFAULT 0,
        costo REAL NOT NULL DEFAULT 0,
        actualizado_en TEXT NOT NULL,
        UNIQUE(producto_id, bodega_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS traslados_bodega(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        bodega_origen_id INTEGER NOT NULL,
        bodega_destino_id INTEGER NOT NULL,
        cantidad REAL NOT NULL,
        costo_at_movement REAL NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'registrado',
        observacion TEXT,
        usuario TEXT,
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caja_sesiones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        usuario TEXT NOT NULL,
        sucursal_id INTEGER,
        monto_inicial REAL NOT NULL DEFAULT 0,
        total_ventas REAL NOT NULL DEFAULT 0,
        total_ingresos REAL NOT NULL DEFAULT 0,
        total_egresos REAL NOT NULL DEFAULT 0,
        monto_contado REAL,
        diferencia REAL,
        justificacion TEXT,
        estado TEXT NOT NULL DEFAULT 'abierta',
        abierta_en TEXT NOT NULL,
        cerrada_en TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cotizaciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cliente_id INTEGER,
        cliente TEXT,
        estado TEXT NOT NULL DEFAULT 'borrador',
        subtotal REAL NOT NULL DEFAULT 0,
        impuesto REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        fecha TEXT NOT NULL,
        vence_en TEXT,
        observacion TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cotizacion_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cotizacion_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pedidos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cotizacion_id INTEGER,
        cliente_id INTEGER,
        cliente TEXT,
        estado TEXT NOT NULL DEFAULT 'borrador',
        subtotal REAL NOT NULL DEFAULT 0,
        impuesto REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        fecha TEXT NOT NULL,
        entrega_en TEXT,
        observacion TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pedido_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        pedido_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devoluciones_ventas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        venta_id INTEGER NOT NULL,
        nota_credito TEXT,
        total REAL NOT NULL DEFAULT 0,
        motivo TEXT,
        estado TEXT NOT NULL DEFAULT 'emitida',
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devoluciones_ventas_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        devolucion_id INTEGER NOT NULL,
        venta_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devoluciones_compras(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        compra_id INTEGER NOT NULL,
        total REAL NOT NULL DEFAULT 0,
        motivo TEXT,
        estado TEXT NOT NULL DEFAULT 'emitida',
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devoluciones_compras_detalle(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        devolucion_id INTEGER NOT NULL,
        compra_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        costo_unitario REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comisiones_vendedor(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        usuario_id INTEGER,
        producto_id INTEGER,
        porcentaje REAL NOT NULL DEFAULT 0,
        activa INTEGER NOT NULL DEFAULT 1,
        actualizado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comisiones_liquidadas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        venta_id INTEGER NOT NULL,
        usuario_id INTEGER,
        base REAL NOT NULL,
        porcentaje REAL NOT NULL,
        comision REAL NOT NULL,
        periodo TEXT NOT NULL,
        fecha TEXT NOT NULL,
        commission_type TEXT NOT NULL DEFAULT 'Venta',
        status TEXT NOT NULL DEFAULT 'Pendiente'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS warranties(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        venta_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        numero_serie TEXT,
        descripcion_problema TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Recibido',
        fecha_recepcion TEXT NOT NULL,
        fecha_resolucion TEXT,
        resolucion TEXT,
        dias_garantia INTEGER NOT NULL DEFAULT 365
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuesto_lineas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        periodo TEXT NOT NULL,
        cuenta_id INTEGER,
        categoria TEXT,
        monto_presupuestado REAL NOT NULL DEFAULT 0,
        alerta_pct REAL NOT NULL DEFAULT 90,
        creado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS currencies(
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        is_base_currency INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exchange_rates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        currency_code TEXT NOT NULL,
        rate_to_base REAL NOT NULL,
        company_id INTEGER,
        FOREIGN KEY (currency_code) REFERENCES currencies(code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS webhooks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        event TEXT NOT NULL,
        target_url TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        file_url TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_name TEXT,
        file_size INTEGER,
        uploaded_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS onboarding_steps(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        step_name TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        type TEXT NOT NULL,
        html_content TEXT NOT NULL,
        subject TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_tasks_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_name TEXT NOT NULL UNIQUE,
        last_execution_date TEXT,
        last_execution_status TEXT,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS historial_precios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        producto_id INTEGER NOT NULL,
        precio_anterior REAL NOT NULL,
        precio_nuevo REAL NOT NULL,
        usuario TEXT,
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recordatorios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        titulo TEXT NOT NULL,
        detalle TEXT,
        tipo TEXT NOT NULL,
        prioridad TEXT NOT NULL DEFAULT 'info',
        entidad TEXT,
        entidad_id INTEGER,
        fecha_evento TEXT NOT NULL,
        notificar_48h INTEGER NOT NULL DEFAULT 1,
        notificar_24h INTEGER NOT NULL DEFAULT 1,
        completado INTEGER NOT NULL DEFAULT 0,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS plantillas_factura(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL,
        color_primario TEXT NOT NULL DEFAULT '#2563EB',
        mostrar_logo INTEGER NOT NULL DEFAULT 1,
        mostrar_impuestos INTEGER NOT NULL DEFAULT 1,
        campos_json TEXT NOT NULL DEFAULT '{}',
        activa INTEGER NOT NULL DEFAULT 0,
        actualizado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_tokens(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_webhooks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        evento TEXT NOT NULL,
        url TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_eventos_pendientes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        evento TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente',
        intentos INTEGER NOT NULL DEFAULT 0,
        creado_en TEXT NOT NULL,
        enviado_en TEXT
      )
    ''');
  }

  Future<void> _agregarColumnasImpuestos(Database db) async {
    await _agregarColumnaSiNoExiste(db, 'ventas', 'subtotal', 'REAL DEFAULT 0');
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'impuesto_pct',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'ventas',
      'impuesto_total',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'subtotal',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'impuesto_pct',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'compras',
      'impuesto_total',
      'REAL DEFAULT 0',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'auditoria_eventos',
      'old_values',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'auditoria_eventos',
      'new_values',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'auditoria_eventos',
      'ip_address',
      'TEXT',
    );
  }

  Future<void> _agregarColumnaSiNoExiste(
    Database db,
    String tabla,
    String columna,
    String definicion,
  ) async {
    final tablaExiste = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tabla],
    );
    if (tablaExiste.isEmpty) return;
    final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
    final existe = columnas.any((c) => c['name'] == columna);
    if (!existe) {
      await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $definicion');
    }
  }

  Future<void> _agregarCompanyIdATablasOperativas(Database db) async {
    final companyId = await _sincronizarEmpresaLegacy(db);
    const tablas = [
      'productos',
      'ventas',
      'ventas_detalle',
      'compras',
      'compras_detalle',
      'movimientos_caja',
      'movimientos_inventario',
      'proveedores',
      'clientes',
      'cuentas_por_cobrar',
      'cuentas_por_pagar',
      'abonos_cxc',
      'abonos_cxp',
      'cierres_caja',
      'auditoria_eventos',
      'conciliaciones_bancarias',
      'presupuestos',
      'usuarios',
      'facturas_electronicas',
      'empleados',
      'nomina_liquidaciones',
      'activos_fijos',
      'extractos_bancarios',
      'adjuntos_documentos',
      'asientos_contables',
      'asiento_lineas',
      'comprobantes_contables',
    ];

    for (final tabla in tablas) {
      await _agregarColumnaSiNoExiste(db, tabla, 'company_id', 'INTEGER');
      await db.update(tabla, {
        'company_id': companyId,
      }, where: 'company_id IS NULL');
    }
  }

  Future<int> obtenerEmpresaActivaId([DatabaseExecutor? txn]) async {
    final executor = txn ?? await instance.database;
    final activeId = await executor.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['company_active_id'],
      limit: 1,
    );
    if (activeId.isNotEmpty) {
      final id = int.tryParse(activeId.first['valor']?.toString() ?? '');
      if (id != null) {
        return id;
      }
    }
    if (txn != null) {
      try {
        final companies = await txn.query('companies', limit: 1);
        if (companies.isNotEmpty) {
          return companies.first['id'] as int;
        }
      } catch (_) {}
      throw StateError(
        'No se encontró una empresa activa para la transacción contable.',
      );
    }
    final db = await instance.database;
    return await _sincronizarEmpresaLegacy(db);
  }

  String _dianSecretKey(int companyId, String field) =>
      'merka.dian.v1.$companyId.$field';

  String _dianPublicKey(int companyId, String field) =>
      'dian_${field}_$companyId';

  /// Los secretos DIAN se guardan en el almacén seguro del sistema operativo.
  /// La operación falla cerrada: nunca degrada a texto plano en SQLite.
  Future<void> guardarDianConfig({
    String? dianTechKey,
    String? dianPin,
    String? dianResolution,
    String? dianSoftwareId,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    if (dianTechKey != null) {
      final value = dianTechKey.trim();
      if (value.isEmpty) {
        await _secureStorage.delete(key: _dianSecretKey(companyId, 'tech_key'));
      } else {
        await _secureStorage.write(
          key: _dianSecretKey(companyId, 'tech_key'),
          value: value,
        );
      }
    }
    if (dianPin != null) {
      final value = dianPin.trim();
      if (value.isEmpty) {
        await _secureStorage.delete(key: _dianSecretKey(companyId, 'pin'));
      } else {
        await _secureStorage.write(
          key: _dianSecretKey(companyId, 'pin'),
          value: value,
        );
      }
    }
    if (dianResolution != null) {
      await db.insert('app_config', {
        'clave': _dianPublicKey(companyId, 'resolution'),
        'valor': dianResolution.trim(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (dianSoftwareId != null) {
      await db.insert('app_config', {
        'clave': _dianPublicKey(companyId, 'software_id'),
        'valor': dianSoftwareId.trim(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await db.delete(
      'app_config',
      where: 'clave IN (?, ?)',
      whereArgs: ['dian_tech_key', 'dian_pin'],
    );
  }

  Future<String?> _obtenerDianSecret(
    DatabaseExecutor executor,
    int companyId,
    String field,
    String legacyKey,
  ) async {
    final secureKey = _dianSecretKey(companyId, field);
    final stored = await _secureStorage.read(key: secureKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final legacy = await executor.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [legacyKey],
      limit: 1,
    );
    if (legacy.isEmpty) return null;
    final value = legacy.first['valor']?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    // Solo borrar el legado después de una escritura segura exitosa.
    await _secureStorage.write(key: secureKey, value: value);
    await executor.delete(
      'app_config',
      where: 'clave = ?',
      whereArgs: [legacyKey],
    );
    return value;
  }

  Future<String?> obtenerDianPin([DatabaseExecutor? txn]) async {
    final executor = txn ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    return _obtenerDianSecret(executor, companyId, 'pin', 'dian_pin');
  }

  Future<String?> obtenerDianTechKey([DatabaseExecutor? txn]) async {
    final executor = txn ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    return _obtenerDianSecret(executor, companyId, 'tech_key', 'dian_tech_key');
  }

  /// Recupera las claves DIAN (dian_tech_key, dian_pin, dian_resolution, dian_software_id)
  /// como un mapa clave->valor. Si alguna clave no existe, no aparece en el mapa.
  Future<Map<String, String>> obtenerDianConfig([DatabaseExecutor? txn]) async {
    final executor = txn ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    final resolutionKey = _dianPublicKey(companyId, 'resolution');
    final softwareIdKey = _dianPublicKey(companyId, 'software_id');
    final rows = await executor.query(
      'app_config',
      where: 'clave IN (?,?,?,?)',
      whereArgs: [
        resolutionKey,
        softwareIdKey,
        'dian_resolution',
        'dian_software_id',
      ],
    );
    final Map<String, String> result = {};
    for (final r in rows) {
      final k = r['clave']?.toString();
      final v = r['valor']?.toString();
      if (k == null || v == null) continue;
      if (k == resolutionKey || k == 'dian_resolution') {
        result['dian_resolution'] = v;
      } else if (k == softwareIdKey || k == 'dian_software_id') {
        result['dian_software_id'] = v;
      }
    }
    final techKey = await _obtenerDianSecret(
      executor,
      companyId,
      'tech_key',
      'dian_tech_key',
    );
    final pin = await _obtenerDianSecret(
      executor,
      companyId,
      'pin',
      'dian_pin',
    );
    if (techKey != null) result['dian_tech_key'] = techKey;
    if (pin != null) result['dian_pin'] = pin;
    return result;
  }

  Future<Map<String, dynamic>> _conEmpresa(Map<String, dynamic> row) async {
    return {...row, 'company_id': await obtenerEmpresaActivaId()};
  }

  Future<void> _crearTablasCartera(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        documento TEXT,
        telefono TEXT,
        direccion TEXT,
        email TEXT,
        estado TEXT DEFAULT 'activo',
        fecha TEXT,
        -- Banderas fiscales colombianas
        gran_contribuyente INTEGER DEFAULT 0,
        autorretenedor INTEGER DEFAULT 0,
        regimen_tributario TEXT DEFAULT 'ordinario',
        declarante INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cuentas_por_cobrar(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cliente_id INTEGER,
        cliente TEXT,
        venta_id INTEGER,
        total REAL NOT NULL,
        saldo REAL NOT NULL,
        estado TEXT NOT NULL,
        fecha TEXT NOT NULL,
        vencimiento TEXT,
        descripcion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS abonos_cxc(
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

  Future<void> _crearTablasControl(Database db) async {
    await _agregarColumnaSiNoExiste(db, 'ventas', 'cliente_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(db, 'ventas', 'cliente', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cierres_caja(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        saldo_sistema REAL NOT NULL,
        efectivo_contado REAL NOT NULL,
        diferencia REAL NOT NULL,
        observacion TEXT,
        estado TEXT NOT NULL DEFAULT 'cerrado'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auditoria_eventos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        accion TEXT NOT NULL,
        entidad TEXT NOT NULL,
        entidad_id INTEGER,
        detalle TEXT,
        usuario TEXT DEFAULT 'local',
        old_values TEXT,
        new_values TEXT,
        ip_address TEXT,
        device_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenants(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT NOT NULL,
        license_status TEXT NOT NULL DEFAULT 'active',
        subscription_start TEXT,
        subscription_end TEXT,
        payment_method TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasEmpresaYComprobantes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS empresa_config(
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nombre TEXT,
        nit TEXT,
        regimen TEXT,
        direccion TEXT,
        telefono TEXT,
        email TEXT,
        ciudad TEXT,
        logo_path TEXT,
        moneda TEXT DEFAULT 'COP',
        actualizado TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS secuencias_documentos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        prefijo TEXT NOT NULL,
        siguiente INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, tipo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comprobantes_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        prefijo TEXT NOT NULL,
        numero INTEGER NOT NULL,
        consecutivo TEXT NOT NULL,
        asiento_id INTEGER,
        fecha TEXT NOT NULL,
        concepto TEXT NOT NULL,
        tercero TEXT,
        total REAL NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'emitido',
        UNIQUE(company_id, consecutivo),
        FOREIGN KEY (asiento_id) REFERENCES asientos_contables(id)
      )
    ''');

    await db.insert('empresa_config', {
      'id': 1,
      'nombre': 'MerkaERP',
      'moneda': 'COP',
      'actualizado': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _crearTablasPeriodos(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS periodos_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        anio INTEGER NOT NULL,
        mes INTEGER NOT NULL,
        estado TEXT NOT NULL DEFAULT 'abierto',
        fecha_apertura TEXT NOT NULL,
        fecha_cierre TEXT,
        observacion TEXT,
        UNIQUE(company_id, anio, mes)
      )
    ''');
  }

  Future<void> _crearTablasConciliacion(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conciliaciones_bancarias(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        cuenta TEXT NOT NULL,
        saldo_libros REAL NOT NULL,
        saldo_extracto REAL NOT NULL,
        diferencia REAL NOT NULL,
        observacion TEXT,
        estado TEXT NOT NULL DEFAULT 'registrada'
      )
    ''');
  }

  Future<void> _crearTablasPresupuestos(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuestos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        anio INTEGER NOT NULL,
        mes INTEGER NOT NULL,
        categoria TEXT NOT NULL,
        tipo TEXT NOT NULL,
        valor_presupuestado REAL NOT NULL,
        valor_real REAL NOT NULL DEFAULT 0,
        diferencia REAL NOT NULL DEFAULT 0,
        observacion TEXT,
        fecha TEXT NOT NULL,
        UNIQUE(anio, mes, categoria, tipo)
      )
    ''');
  }

  Future<void> _crearTablasGestionAvanzada(Database db) async {
    await _crearTablasMultiempresaYConfig(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        usuario TEXT NOT NULL COLLATE NOCASE,
        rol TEXT NOT NULL,
        pin TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        fecha TEXT NOT NULL,
        UNIQUE(company_id, usuario)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS facturas_electronicas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        venta_id INTEGER,
        prefijo TEXT NOT NULL DEFAULT 'FE',
        numero INTEGER NOT NULL,
        consecutivo TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'borrador',
        cufe TEXT,
        xml TEXT,
        respuesta_dian TEXT,
        fecha TEXT NOT NULL,
        validada TEXT,
        observacion TEXT,
        UNIQUE(company_id, consecutivo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS empleados(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        documento TEXT,
        tipo_documento TEXT DEFAULT 'CC',
        cargo TEXT,
        salario_base REAL NOT NULL DEFAULT 0,
        auxilio_transporte INTEGER NOT NULL DEFAULT 0,
        cuenta_bancaria TEXT,
        codigo_banco TEXT,
        nombre_banco TEXT,
        nivel_arl TEXT NOT NULL DEFAULT 'I',
        fondo_pension TEXT,
        eps TEXT,
        tipo_contrato TEXT NOT NULL DEFAULT 'indefinido',
        frecuencia_pago TEXT NOT NULL DEFAULT 'mensual',
        activo INTEGER NOT NULL DEFAULT 1,
        fecha_contratacion TEXT NOT NULL,
        fecha_terminacion TEXT,
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS nomina_liquidaciones(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        empleado_id INTEGER NOT NULL,
        empleado TEXT NOT NULL,
        periodo TEXT NOT NULL,
        salario_base REAL NOT NULL,
        total_devengado REAL NOT NULL,
        total_deducciones REAL NOT NULL,
        neto_pagar REAL NOT NULL,
        aportes_empleador REAL NOT NULL,
        salud_empleado REAL NOT NULL,
        salud_empleador REAL NOT NULL,
        pension_empleado REAL NOT NULL,
        pension_empleador REAL NOT NULL,
        fsp REAL NOT NULL,
        arl REAL NOT NULL,
        parafiscal_sena REAL NOT NULL,
        parafiscal_icbf REAL NOT NULL,
        parafiscal_caja REAL NOT NULL,
        cesantias REAL NOT NULL,
        prima_servicios REAL NOT NULL,
        intereses_cesantias REAL NOT NULL,
        vacaciones REAL NOT NULL,
        retefuente REAL NOT NULL,
        estado TEXT NOT NULL DEFAULT 'liquidada',
        calculo_json TEXT,
        nomina_electronica_json TEXT,
        novedades_hrm TEXT,
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_parameters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        year INTEGER NOT NULL,
        smmlv REAL NOT NULL,
        uvt REAL NOT NULL,
        transportation_allowance REAL NOT NULL,
        health_employee_rate REAL NOT NULL DEFAULT 0.04,
        health_employer_rate REAL NOT NULL DEFAULT 0.085,
        health_exonerated INTEGER DEFAULT 0,
        pension_employee_rate REAL NOT NULL DEFAULT 0.04,
        pension_employer_rate REAL NOT NULL DEFAULT 0.12,
        fsp_trigger_smmlv REAL NOT NULL DEFAULT 4.0,
        fsp_rate_1 REAL NOT NULL DEFAULT 0.01,
        fsp_rate_2 REAL NOT NULL DEFAULT 0.012,
        fsp_rate_3 REAL NOT NULL DEFAULT 0.014,
        fsp_rate_4 REAL NOT NULL DEFAULT 0.016,
        fsp_rate_5 REAL NOT NULL DEFAULT 0.018,
        fsp_rate_6 REAL NOT NULL DEFAULT 0.02,
        arl_level_1_rate REAL NOT NULL DEFAULT 0.00522,
        arl_level_2_rate REAL NOT NULL DEFAULT 0.01044,
        arl_level_3_rate REAL NOT NULL DEFAULT 0.02436,
        arl_level_4_rate REAL NOT NULL DEFAULT 0.04350,
        arl_level_5_rate REAL NOT NULL DEFAULT 0.06960,
        parafiscal_sena_rate REAL NOT NULL DEFAULT 0.02,
        parafiscal_icbf_rate REAL NOT NULL DEFAULT 0.03,
        parafiscal_caja_rate REAL NOT NULL DEFAULT 0.04,
        severance_rate REAL NOT NULL DEFAULT 0.0833,
        service_bonus_rate REAL NOT NULL DEFAULT 0.0833,
        severance_interest_rate REAL NOT NULL DEFAULT 0.01,
        vacation_rate REAL NOT NULL DEFAULT 0.0417,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(company_id, year)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_novelties(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        empleado_id INTEGER NOT NULL,
        periodo TEXT NOT NULL,
        tipo_novedad TEXT NOT NULL,
        descripcion TEXT,
        valor REAL NOT NULL,
        horas REAL,
        tarifa REAL,
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tax_parameters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        year INTEGER NOT NULL,
        iva_general_rate REAL NOT NULL DEFAULT 0.19,
        iva_reduced_rate REAL NOT NULL DEFAULT 0.05,
        iva_exempt_rate REAL NOT NULL DEFAULT 0.0,
        retefuente_general_uvt REAL NOT NULL DEFAULT 1090,
        retefuente_purchases_declaring REAL NOT NULL DEFAULT 0.025,
        retefuente_purchases_non_declaring REAL NOT NULL DEFAULT 0.035,
        retefuente_services_1 REAL NOT NULL DEFAULT 0.04,
        retefuente_services_2 REAL NOT NULL DEFAULT 0.06,
        retefuente_honoraries_1 REAL NOT NULL DEFAULT 0.10,
        retefuente_honoraries_2 REAL NOT NULL DEFAULT 0.11,
        reteica_base_rate REAL NOT NULL DEFAULT 0.00414,
        inc_restaurant_rate REAL NOT NULL DEFAULT 0.08,
        inc_telecom_rate REAL NOT NULL DEFAULT 0.04,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(company_id, year)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS activos_fijos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        categoria TEXT,
        costo REAL NOT NULL,
        valor_residual REAL NOT NULL DEFAULT 0,
        fecha_compra TEXT NOT NULL,
        vida_util_meses INTEGER NOT NULL,
        depreciacion_acumulada REAL NOT NULL DEFAULT 0,
        valor_libros REAL NOT NULL,
        estado TEXT NOT NULL DEFAULT 'activo',
        observacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS extractos_bancarios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        cuenta TEXT NOT NULL,
        fecha TEXT NOT NULL,
        descripcion TEXT,
        valor REAL NOT NULL,
        tipo TEXT NOT NULL,
        conciliado INTEGER NOT NULL DEFAULT 0,
        referencia TEXT,
        creado TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS adjuntos_documentos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        entidad TEXT NOT NULL,
        entidad_id INTEGER,
        nombre TEXT NOT NULL,
        ruta TEXT NOT NULL,
        notas TEXT,
        fecha TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasMultiempresaYConfig(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config(
        clave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS empresas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        nit TEXT,
        regimen TEXT,
        direccion TEXT,
        telefono TEXT,
        email TEXT,
        ciudad TEXT,
        moneda TEXT DEFAULT 'COP',
        logo_path TEXT,
        activa INTEGER NOT NULL DEFAULT 1,
        fecha TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasConfiguracionEmpresarial(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS companies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        tax_id TEXT,
        country TEXT DEFAULT 'Colombia',
        currency TEXT DEFAULT 'COP',
        timezone TEXT DEFAULT 'America/Bogota',
        niif_group TEXT NOT NULL DEFAULT 'grupo_2',
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL UNIQUE,
        employee_count TEXT,
        branch_count TEXT,
        operation_volume TEXT,
        tax_regime TEXT,
        vat_enabled INTEGER NOT NULL DEFAULT 0,
        withholding_enabled INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (company_id) REFERENCES companies(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_features(
        company_id INTEGER NOT NULL,
        feature_key TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, feature_key),
        FOREIGN KEY (company_id) REFERENCES companies(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_settings(
        company_id INTEGER NOT NULL,
        setting_key TEXT NOT NULL,
        setting_value TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, setting_key),
        FOREIGN KEY (company_id) REFERENCES companies(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_templates(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        features_json TEXT NOT NULL,
        settings_json TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasCatalogosMaestros(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tax_catalog(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL DEFAULT 0,
        code TEXT NOT NULL,
        label TEXT NOT NULL,
        rate REAL NOT NULL DEFAULT 0,
        sales_enabled INTEGER NOT NULL DEFAULT 1,
        purchases_enabled INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_catalog(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL DEFAULT 0,
        code TEXT NOT NULL,
        label TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_rule_settings(
        company_id INTEGER NOT NULL,
        rule_key TEXT NOT NULL,
        account_code TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(company_id, rule_key)
      )
    ''');
  }

  Future<void> _crearTablasComplementosERP(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bodegas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        activa INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, codigo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS centros_costo(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL DEFAULT 'operativo',
        activo INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, codigo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reglas_impuestos_empresa(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        tasa REAL NOT NULL DEFAULT 0,
        cuenta_venta TEXT,
        cuenta_compra TEXT,
        aplica_ventas INTEGER NOT NULL DEFAULT 1,
        aplica_compras INTEGER NOT NULL DEFAULT 1,
        activo INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, codigo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reglas_retenciones_empresa(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        tasa REAL NOT NULL DEFAULT 0,
        base_minima INTEGER NOT NULL DEFAULT 0,
        cuenta_contable TEXT,
        aplica_ventas INTEGER NOT NULL DEFAULT 0,
        aplica_compras INTEGER NOT NULL DEFAULT 1,
        activo INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, codigo)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documentos_compra_flujo(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        etapa TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'borrador',
        proveedor_id INTEGER,
        proveedor TEXT,
        documento_origen_id INTEGER,
        fecha TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0,
        centro_costo_id INTEGER,
        bodega_id INTEGER,
        observacion TEXT,
        created_by TEXT DEFAULT 'local',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documentos_compra_flujo_lineas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        documento_id INTEGER NOT NULL,
        producto_id INTEGER,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL DEFAULT 0,
        costo_unitario REAL NOT NULL DEFAULT 0,
        impuesto_pct REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(documento_id) REFERENCES documentos_compra_flujo(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documentos_venta_flujo(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        etapa TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'borrador',
        cliente_id INTEGER,
        cliente TEXT,
        documento_origen_id INTEGER,
        fecha TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0,
        centro_costo_id INTEGER,
        bodega_id INTEGER,
        observacion TEXT,
        created_by TEXT DEFAULT 'local',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documentos_venta_flujo_lineas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        documento_id INTEGER NOT NULL,
        producto_id INTEGER,
        producto TEXT NOT NULL,
        cantidad REAL NOT NULL DEFAULT 0,
        precio_unitario REAL NOT NULL DEFAULT 0,
        impuesto_pct REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(documento_id) REFERENCES documentos_venta_flujo(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS kardex_inventario(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        bodega_id INTEGER,
        tipo TEXT NOT NULL,
        cantidad REAL NOT NULL,
        costo_unitario REAL NOT NULL DEFAULT 0,
        costo_total REAL NOT NULL DEFAULT 0,
        stock_anterior REAL NOT NULL DEFAULT 0,
        stock_nuevo REAL NOT NULL DEFAULT 0,
        referencia TEXT,
        documento_tipo TEXT,
        documento_id INTEGER,
        fecha TEXT NOT NULL,
        created_by TEXT DEFAULT 'local'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        idempotency_key TEXT,
        vector_clock_json TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        processed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        token_hint TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        scopes TEXT,
        created_at TEXT NOT NULL,
        last_used_at TEXT
      )
    ''');
  }

  Future<void> _crearTablasPlataformaDistribuida(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS branches(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        city TEXT,
        address TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(company_id, code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_inbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        vector_clock_json TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        received_at TEXT NOT NULL,
        applied_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        direction TEXT NOT NULL,
        event_id TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 100,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL,
        last_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS control_center_sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        vector_clock_json TEXT,
        source_node TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        local_payload_json TEXT NOT NULL,
        remote_payload_json TEXT NOT NULL,
        resolution TEXT NOT NULL DEFAULT 'manual',
        status TEXT NOT NULL DEFAULT 'open',
        detected_at TEXT NOT NULL,
        resolved_at TEXT,
        table_name TEXT,
        record_id TEXT,
        local_data TEXT,
        remote_data TEXT,
        resolved INTEGER DEFAULT 0,
        resolved_data TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata(
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        key TEXT NOT NULL,
        value TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(company_id, branch_id, key)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenant_licenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        plan_id TEXT NOT NULL,
        status TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        max_branches INTEGER NOT NULL DEFAULT 1,
        max_devices INTEGER NOT NULL DEFAULT 1,
        modules_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, plan_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_support_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        session_code TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        requested_by TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT,
        closed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS telemetry_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        branch_id INTEGER,
        trace_id TEXT,
        span_id TEXT,
        severity TEXT NOT NULL,
        name TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_definitions(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        module TEXT NOT NULL,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_steps(
        id TEXT PRIMARY KEY,
        workflow_id TEXT NOT NULL,
        step_order INTEGER NOT NULL,
        name TEXT NOT NULL,
        required_role TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_conditions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workflow_id TEXT NOT NULL,
        step_id TEXT NOT NULL,
        field TEXT NOT NULL,
        operator TEXT NOT NULL,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_actions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workflow_id TEXT NOT NULL,
        step_id TEXT NOT NULL,
        action_type TEXT NOT NULL,
        parameters_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rule_definitions(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        module TEXT NOT NULL,
        name TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 100,
        enabled INTEGER NOT NULL DEFAULT 1,
        definition_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduler_jobs(
        id TEXT PRIMARY KEY,
        company_id INTEGER,
        branch_id INTEGER,
        name TEXT NOT NULL,
        job_type TEXT NOT NULL,
        schedule TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        last_run_at TEXT,
        next_run_at TEXT,
        payload_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        branch_id INTEGER,
        channel TEXT NOT NULL,
        recipient TEXT,
        subject TEXT,
        body TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        sent_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_registry(
        id TEXT PRIMARY KEY,
        company_id INTEGER,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        manifest_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _crearTablasConsolidacionArquitectonica(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS event_store(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL,
        metadata_json TEXT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        idempotency_key TEXT NOT NULL UNIQUE,
        correlation_id TEXT,
        causation_id TEXT,
        trace_id TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS event_dispatch_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_sequence INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        available_at TEXT NOT NULL,
        dispatched_at TEXT,
        created_at TEXT NOT NULL,
        last_error TEXT,
        FOREIGN KEY(event_sequence) REFERENCES event_store(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS event_dead_letters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_sequence INTEGER,
        error TEXT NOT NULL,
        payload_json TEXT,
        failed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cqrs_projection_offsets(
        projection_name TEXT NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        last_sequence INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(projection_name, company_id, branch_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS executive_kpi_read_model(
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        metric_key TEXT NOT NULL,
        metric_value REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(company_id, branch_id, metric_key)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_journal_entries(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        consecutive TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        concept TEXT NOT NULL,
        reference TEXT,
        origin TEXT NOT NULL,
        status TEXT NOT NULL,
        reversed_entry_id TEXT,
        correlation_id TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(company_id, consecutive)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_journal_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id TEXT NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER,
        cost_center_id INTEGER,
        account_code TEXT NOT NULL,
        description TEXT,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        local_debit REAL NOT NULL DEFAULT 0,
        local_credit REAL NOT NULL DEFAULT 0,
        third_party TEXT,
        currency TEXT NOT NULL DEFAULT 'COP',
        exchange_rate REAL NOT NULL DEFAULT 1,
        FOREIGN KEY(entry_id) REFERENCES accounting_journal_entries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_lots(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL NOT NULL DEFAULT 0,
        batch_number TEXT,
        serial_number TEXT,
        received_at TEXT NOT NULL,
        expires_at TEXT,
        lot_number TEXT,
        manufacturing_date TEXT,
        expiration_date TEXT,
        initial_quantity REAL,
        current_quantity REAL,
        supplier_id TEXT,
        purchase_document_id TEXT,
        status TEXT DEFAULT 'active',
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_reservations(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        released_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_event_store_scope_sequence '
      'ON event_store(company_id, branch_id, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_event_store_aggregate '
      'ON event_store(aggregate_type, aggregate_id, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_event_dispatch_queue_status '
      'ON event_dispatch_queue(status, available_at, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounting_journal_scope '
      'ON accounting_journal_entries(company_id, branch_id, entry_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounting_journal_lines_account '
      'ON accounting_journal_lines(company_id, branch_id, account_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_lots_product '
      'ON inventory_lots(company_id, branch_id, warehouse_id, product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_reservations_product '
      'ON inventory_reservations(company_id, branch_id, warehouse_id, product_id, status)',
    );
  }

  Future<void> _crearTablasSalesEnterprise(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL,
        state TEXT NOT NULL,
        customer_id INTEGER,
        customer TEXT NOT NULL,
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        credit_days INTEGER NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        discount_total REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        approved_by TEXT,
        posted_at TEXT,
        reversed_document_id INTEGER,
        correlation_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_document_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        product_id INTEGER NOT NULL,
        product TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(document_id) REFERENCES sales_documents(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_document_audit(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        document_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_analytics_read_model(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        document_id TEXT NOT NULL,
        event_name TEXT NOT NULL,
        revenue REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        occurred_at TEXT NOT NULL,
        correlation_id TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_documents_scope '
      'ON sales_documents(company_id, branch_id, warehouse_id, state, issue_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_documents_customer '
      'ON sales_documents(company_id, customer_id, state)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_document_lines_document '
      'ON sales_document_lines(company_id, document_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_audit_document '
      'ON sales_document_audit(company_id, document_id, created_at)',
    );
  }

  Future<void> _crearTablasPurchasesEnterprise(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL,
        state TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier TEXT NOT NULL,
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        country TEXT NOT NULL DEFAULT 'Colombia',
        budget_code TEXT,
        budget_available REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        retention_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        approved_by TEXT,
        posted_at TEXT,
        reversed_document_id INTEGER,
        correlation_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_document_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        product_id INTEGER NOT NULL,
        product TEXT NOT NULL,
        quantity REAL NOT NULL,
        received_quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL,
        tax_code TEXT NOT NULL DEFAULT 'EXEMPT',
        tax_rate REAL NOT NULL DEFAULT 0,
        retention_rate REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        retention_total REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(document_id) REFERENCES purchase_documents(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_approval_steps(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        level INTEGER NOT NULL,
        approver_role TEXT NOT NULL,
        sla_hours INTEGER NOT NULL DEFAULT 24,
        approved_by TEXT,
        approved_at TEXT,
        escalated_to TEXT,
        FOREIGN KEY(document_id) REFERENCES purchase_documents(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_document_audit(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        document_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_balances(
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        supplier_id INTEGER NOT NULL,
        supplier TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(company_id, branch_id, supplier_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_analytics_read_model(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        document_id TEXT NOT NULL,
        event_name TEXT NOT NULL,
        spend REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        retention REAL NOT NULL DEFAULT 0,
        occurred_at TEXT NOT NULL,
        correlation_id TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_documents_scope '
      'ON purchase_documents(company_id, branch_id, warehouse_id, state, issue_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_documents_supplier '
      'ON purchase_documents(company_id, supplier_id, state)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_lines_document '
      'ON purchase_document_lines(company_id, document_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_approval_document '
      'ON purchase_approval_steps(company_id, document_id, level)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_audit_document '
      'ON purchase_document_audit(company_id, document_id, created_at)',
    );
  }

  Future<void> _crearTablasFinalEnterprise(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS enterprise_audit_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id INTEGER,
        user_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_credit_profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        credit_limit REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        risk_score REAL NOT NULL DEFAULT 0,
        blocked INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ar_ledger_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        customer TEXT NOT NULL,
        document_id TEXT NOT NULL,
        document_type TEXT NOT NULL,
        side TEXT NOT NULL,
        amount REAL NOT NULL,
        open_amount REAL NOT NULL DEFAULT 0,
        due_date TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ar_payment_promises(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        customer TEXT NOT NULL,
        amount REAL NOT NULL,
        promise_date TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ap_supplier_ledger(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        supplier_id INTEGER NOT NULL,
        supplier TEXT NOT NULL,
        document_id TEXT NOT NULL,
        document_type TEXT NOT NULL,
        side TEXT NOT NULL,
        amount REAL NOT NULL,
        open_amount REAL NOT NULL DEFAULT 0,
        due_date TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ap_payment_schedules(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        party_id INTEGER NOT NULL,
        party TEXT NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        source_document_id TEXT,
        payload_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS treasury_bank_accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        name TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        account_number TEXT,
        currency TEXT NOT NULL DEFAULT 'COP',
        balance REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS treasury_transfers(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        from_account_id INTEGER NOT NULL,
        to_account_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        requested_by TEXT NOT NULL,
        created_at TEXT NOT NULL,
        approved INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS treasury_bank_movements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        bank_account_id INTEGER NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        reference TEXT NOT NULL,
        movement_date TEXT NOT NULL,
        reconciled INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_statements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        statement_id TEXT NOT NULL,
        bank_account_id INTEGER NOT NULL,
        statement_date TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_statement_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        statement_id TEXT NOT NULL,
        bank_account_id INTEGER NOT NULL,
        reference TEXT,
        description TEXT,
        amount REAL NOT NULL,
        movement_date TEXT NOT NULL,
        matched_movement_id INTEGER,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_reconciliations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        reconciliation_id TEXT NOT NULL,
        statement_id TEXT NOT NULL,
        matched_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS enterprise_tax_rules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        code TEXT NOT NULL,
        country TEXT NOT NULL,
        document_type TEXT NOT NULL,
        rate REAL NOT NULL DEFAULT 0,
        retention_rate REAL NOT NULL DEFAULT 0,
        exempt INTEGER NOT NULL DEFAULT 0,
        group_name TEXT NOT NULL DEFAULT 'default',
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS enterprise_tax_calculations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        taxable_base REAL NOT NULL,
        tax REAL NOT NULL,
        retention REAL NOT NULL,
        total REAL NOT NULL,
        rule_code TEXT NOT NULL,
        correlation_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS enterprise_fixed_assets(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        name TEXT NOT NULL,
        cost REAL NOT NULL,
        useful_life_months INTEGER NOT NULL,
        acquired_at TEXT NOT NULL,
        monthly_depreciation REAL NOT NULL DEFAULT 0,
        accumulated_depreciation REAL NOT NULL DEFAULT 0,
        fiscal_depreciation REAL NOT NULL DEFAULT 0,
        book_value REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS fixed_asset_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        asset_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_opportunities(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        customer TEXT NOT NULL,
        value REAL NOT NULL DEFAULT 0,
        stage TEXT NOT NULL,
        next_follow_up_at TEXT NOT NULL,
        owner TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_timeline(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_notifications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        recipient TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        scheduled_at TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_definitions(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        name TEXT NOT NULL,
        dataset TEXT NOT NULL,
        filters_json TEXT NOT NULL,
        formats_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_runs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        run_id TEXT NOT NULL,
        definition_id TEXT NOT NULL,
        dataset TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        exports_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS materialized_reports(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        report_key TEXT NOT NULL,
        dataset TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS enterprise_event_metrics(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        metric_key TEXT NOT NULL,
        metric_value REAL NOT NULL DEFAULT 0,
        event_name TEXT NOT NULL,
        correlation_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_ar_ledger_scope ON ar_ledger_entries(company_id, branch_id, customer_id, due_date)',
      'CREATE INDEX IF NOT EXISTS idx_ap_ledger_scope ON ap_supplier_ledger(company_id, branch_id, supplier_id, due_date)',
      'CREATE INDEX IF NOT EXISTS idx_treasury_movements ON treasury_bank_movements(company_id, branch_id, bank_account_id, reconciled)',
      'CREATE INDEX IF NOT EXISTS idx_bank_lines_match ON bank_statement_lines(company_id, branch_id, bank_account_id, reference, amount, status)',
      'CREATE INDEX IF NOT EXISTS idx_tax_rules_scope ON enterprise_tax_rules(company_id, branch_id, country, document_type, active)',
      'CREATE INDEX IF NOT EXISTS idx_assets_scope ON enterprise_fixed_assets(company_id, branch_id, status)',
      'CREATE INDEX IF NOT EXISTS idx_crm_pipeline ON crm_opportunities(company_id, branch_id, stage, next_follow_up_at)',
      'CREATE INDEX IF NOT EXISTS idx_reports_scope ON materialized_reports(company_id, branch_id, dataset, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_enterprise_metrics ON enterprise_event_metrics(company_id, branch_id, metric_key, created_at)',
    ];
    for (final index in indexes) {
      await db.execute(index);
    }
  }

  Future<void> _agregarScopeDistribuidoATablas(Database db) async {
    const tablas = [
      'productos',
      'ventas',
      'ventas_detalle',
      'compras',
      'compras_detalle',
      'movimientos_caja',
      'movimientos_inventario',
      'proveedores',
      'clientes',
      'cuentas_por_cobrar',
      'cuentas_por_pagar',
      'abonos_cxc',
      'abonos_cxp',
      'cierres_caja',
      'auditoria_eventos',
      'conciliaciones_bancarias',
      'presupuestos',
      'facturas_electronicas',
      'nomina_liquidaciones',
      'activos_fijos',
      'extractos_bancarios',
      'adjuntos_documentos',
      'asientos_contables',
      'asiento_lineas',
      'comprobantes_contables',
      'documentos_compra_flujo',
      'documentos_compra_flujo_lineas',
      'documentos_venta_flujo',
      'documentos_venta_flujo_lineas',
      'kardex_inventario',
      'sync_outbox',
    ];

    for (final tabla in tablas) {
      await _agregarColumnaSiNoExiste(
        db,
        tabla,
        'branch_id',
        'INTEGER DEFAULT 1',
      );
      await _agregarColumnaSiNoExiste(
        db,
        tabla,
        'warehouse_id',
        'INTEGER DEFAULT 1',
      );
      await _agregarColumnaSiNoExiste(
        db,
        tabla,
        'cost_center_id',
        'INTEGER DEFAULT 1',
      );
      await db.update(tabla, {'branch_id': 1}, where: 'branch_id IS NULL');
      await db.update(tabla, {
        'warehouse_id': 1,
      }, where: 'warehouse_id IS NULL');
      await db.update(tabla, {
        'cost_center_id': 1,
      }, where: 'cost_center_id IS NULL');
    }
    await _agregarColumnaSiNoExiste(
      db,
      'sync_outbox',
      'idempotency_key',
      'TEXT',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'sync_outbox',
      'vector_clock_json',
      'TEXT',
    );

    final syncTablas = ['sync_outbox', 'sync_inbox', 'sync_conflicts'];
    for (final st in syncTablas) {
      await _agregarColumnaSiNoExiste(
        db,
        st,
        'tenant_type',
        "TEXT DEFAULT 'commercial'",
      );
      await _agregarColumnaSiNoExiste(db, st, 'entidad_id', 'TEXT');
      await _agregarColumnaSiNoExiste(db, st, 'user_id', 'TEXT');
    }
  }

  Future<void> _sembrarCatalogosMaestros(
    DatabaseExecutor db,
    int companyId,
  ) async {
    final now = DateTime.now().toIso8601String();

    for (final tax in MasterCatalog.taxes) {
      await db.insert('tax_catalog', {
        'company_id': companyId,
        'code': tax.code,
        'label': tax.label,
        'rate': tax.rate,
        'sales_enabled': tax.sales ? 1 : 0,
        'purchases_enabled': tax.purchases ? 1 : 0,
        'active': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final unit in MasterCatalog.units) {
      await db.insert('unit_catalog', {
        'company_id': companyId,
        'code': unit.code,
        'label': unit.label,
        'active': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    const accountingRules = {
      'cash': '1105',
      'bank': '1110',
      'accounts_receivable': '1305',
      'inventory': '1435',
      'tax_deductible': '1355',
      'accounts_payable': '2205',
      'tax_payable': '2408',
      'sales_revenue': '4135',
      'cost_of_sales': '6135',
    };

    for (final entry in accountingRules.entries) {
      await db.insert('accounting_rule_settings', {
        'company_id': companyId,
        'rule_key': entry.key,
        'account_code': entry.value,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<int> _sincronizarEmpresaLegacy(Database db) async {
    await _crearTablasEmpresaYComprobantes(db);
    await _crearTablasMultiempresaYConfig(db);
    await _crearTablasConfiguracionEmpresarial(db);
    await _crearTablasCatalogosMaestros(db);
    await _crearTablasComplementosERP(db);
    await _crearTablasPlataformaDistribuida(db);

    final activeId = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['company_active_id'],
      limit: 1,
    );
    if (activeId.isNotEmpty) {
      final id = int.tryParse(activeId.first['valor']?.toString() ?? '');
      if (id != null) {
        await _sembrarCatalogosMaestrosSiNecesario(db, id);
        await _sembrarComplementosERPSiNecesario(db, id);
        await _sembrarPlataformaDistribuidaSiNecesario(db, id);
        return id;
      }
    }

    final legacy = await db.query('empresa_config', where: 'id = 1', limit: 1);
    final data = legacy.isEmpty ? <String, dynamic>{} : legacy.first;
    final now = DateTime.now().toIso8601String();
    final companyId = await db.insert('companies', {
      'name': data['nombre']?.toString().isNotEmpty == true
          ? data['nombre']
          : 'MerkaERP',
      'tax_id': data['nit'] ?? '',
      'country': data['pais'] ?? 'Colombia',
      'currency': data['moneda'] ?? 'COP',
      'timezone': data['zona_horaria'] ?? 'America/Bogota',
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('company_profiles', {
      'company_id': companyId,
      'tax_regime': data['regimen'] ?? '',
      'vat_enabled': 0,
      'withholding_enabled': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _guardarCompanyFeaturesEnDB(
      db,
      companyId,
      FeatureRegistry.defaultFeatures(),
    );
    await _guardarCompanySettingsEnDB(db, companyId, {
      'onboarding_completed': '0',
      'country': 'Colombia',
      'currency': data['moneda']?.toString() ?? 'COP',
      'timezone': 'America/Bogota',
    });

    await db.insert('app_config', {
      'clave': 'company_active_id',
      'valor': companyId.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _sembrarCatalogosMaestros(db, companyId);
    await _sembrarComplementosERP(db, companyId);
    await _sembrarPlataformaDistribuida(db, companyId);
    await _marcarSiembraLista(db, companyId, 'catalogos_maestros');
    await _marcarSiembraLista(db, companyId, 'complementos_erp');
    await _marcarSiembraLista(db, companyId, 'plataforma_distribuida');

    return companyId;
  }

  Future<bool> _siembraLista(
    DatabaseExecutor db,
    int companyId,
    String seedKey,
  ) async {
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['seed_${companyId}_$seedKey'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _marcarSiembraLista(
    DatabaseExecutor db,
    int companyId,
    String seedKey,
  ) async {
    await db.insert('app_config', {
      'clave': 'seed_${companyId}_$seedKey',
      'valor': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _sembrarCatalogosMaestrosSiNecesario(
    DatabaseExecutor db,
    int companyId,
  ) async {
    const seedKey = 'catalogos_maestros';
    if (await _siembraLista(db, companyId, seedKey)) return;
    await _sembrarCatalogosMaestros(db, companyId);
    await _marcarSiembraLista(db, companyId, seedKey);
  }

  Future<void> _sembrarComplementosERPSiNecesario(
    DatabaseExecutor db,
    int companyId,
  ) async {
    const seedKey = 'complementos_erp';
    if (await _siembraLista(db, companyId, seedKey)) return;
    await _sembrarComplementosERP(db, companyId);
    await _marcarSiembraLista(db, companyId, seedKey);
  }

  Future<void> _sembrarPlataformaDistribuidaSiNecesario(
    DatabaseExecutor db,
    int companyId,
  ) async {
    const seedKey = 'plataforma_distribuida';
    if (await _siembraLista(db, companyId, seedKey)) return;
    await _sembrarPlataformaDistribuida(db, companyId);
    await _marcarSiembraLista(db, companyId, seedKey);
  }

  Future<BranchScope> obtenerScopeOperativoActivo() async {
    final db = await database;
    final companyId = await obtenerEmpresaActivaId();
    final config = await obtenerConfiguracionActiva();
    await _sembrarPlataformaDistribuidaSiNecesario(db, companyId);

    Future<int> appInt(String key, int fallback) async {
      final rows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return fallback;
      return int.tryParse(rows.first['valor']?.toString() ?? '') ?? fallback;
    }

    final branchId = await appInt('branch_active_id', 1);
    final warehouseId = await appInt('warehouse_active_id', 1);
    final costCenterId = await appInt('cost_center_active_id', 1);
    final branchRows = await db.query(
      'branches',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, branchId],
      limit: 1,
    );

    return BranchScope(
      companyId: companyId,
      companyName: config.companyName,
      branchId: branchId,
      branchName: branchRows.isEmpty
          ? 'Sucursal principal'
          : branchRows.first['name']?.toString() ?? 'Sucursal principal',
      warehouseId: warehouseId,
      costCenterId: costCenterId,
    );
  }

  Future<void> _sembrarPlataformaDistribuida(
    DatabaseExecutor db,
    int companyId,
  ) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('branches', {
      'company_id': companyId,
      'code': 'PRINCIPAL',
      'name': 'Sucursal principal',
      'city': '',
      'address': '',
      'active': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final branchRows = await db.query(
      'branches',
      where: 'company_id = ? AND code = ?',
      whereArgs: [companyId, 'PRINCIPAL'],
      limit: 1,
    );
    final branchId = branchRows.isEmpty
        ? 1
        : (branchRows.first['id'] as num?)?.toInt() ?? 1;

    await db.insert('app_config', {
      'clave': 'branch_active_id',
      'valor': branchId.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('app_config', {
      'clave': 'warehouse_active_id',
      'valor': '1',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('app_config', {
      'clave': 'cost_center_active_id',
      'valor': '1',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('tenant_licenses', {
      'company_id': companyId,
      'plan_id': 'enterprise-local',
      'status': 'trial',
      'expires_at': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'max_branches': 20,
      'max_devices': 50,
      'modules_json':
          '["sales","purchases","inventory","accounting","reports","sync","workflows"]',
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('sync_metadata', {
      'company_id': companyId,
      'branch_id': 1,
      'key': 'node_id',
      'value': 'local-${companyId}_1',
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _sembrarComplementosERP(
    DatabaseExecutor db,
    int companyId,
  ) async {
    final now = DateTime.now().toIso8601String();
    final warehouses = [
      {'codigo': 'PRINCIPAL', 'nombre': 'Bodega principal'},
      {'codigo': 'TRANSITO', 'nombre': 'Inventario en transito'},
    ];
    for (final warehouse in warehouses) {
      await db.insert('bodegas', {
        'company_id': companyId,
        'codigo': warehouse['codigo'],
        'nombre': warehouse['nombre'],
        'activa': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final costCenters = [
      {'codigo': 'ADM', 'nombre': 'Administracion', 'tipo': 'soporte'},
      {'codigo': 'COM', 'nombre': 'Comercial', 'tipo': 'operativo'},
      {'codigo': 'OPS', 'nombre': 'Operaciones', 'tipo': 'operativo'},
    ];
    for (final center in costCenters) {
      await db.insert('centros_costo', {
        'company_id': companyId,
        'codigo': center['codigo'],
        'nombre': center['nombre'],
        'tipo': center['tipo'],
        'activo': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final taxes = [
      {
        'codigo': 'IVA_19',
        'nombre': 'IVA general 19%',
        'tasa': 19.0,
        'cuenta_venta': '2408',
        'cuenta_compra': '1355',
      },
      {
        'codigo': 'IVA_5',
        'nombre': 'IVA reducido 5%',
        'tasa': 5.0,
        'cuenta_venta': '2408',
        'cuenta_compra': '1355',
      },
      {
        'codigo': 'EXENTO',
        'nombre': 'Exento / excluido',
        'tasa': 0.0,
        'cuenta_venta': '2408',
        'cuenta_compra': '1355',
      },
    ];
    for (final tax in taxes) {
      await db.insert('reglas_impuestos_empresa', {
        'company_id': companyId,
        'codigo': tax['codigo'],
        'nombre': tax['nombre'],
        'tasa': tax['tasa'],
        'cuenta_venta': tax['cuenta_venta'],
        'cuenta_compra': tax['cuenta_compra'],
        'aplica_ventas': 1,
        'aplica_compras': 1,
        'activo': 1,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final currency = Currency(
      code: 'COP',
      name: 'Peso colombiano',
      symbol: r'$',
      decimalPlaces: 2,
    );
    for (final retention in RetentionRuleService.defaultRules(
      companyId: companyId,
      currency: currency,
    )) {
      await db.insert(
        'reglas_retenciones_empresa',
        retention.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await db.insert('reglas_retenciones_empresa', {
      'company_id': companyId,
      'codigo': 'RTEICA_COMPRAS',
      'nombre': 'Retencion ICA compras',
      'tasa': 0.966,
      'base_minima': 0,
      'cuenta_contable': '2367',
      'aplica_ventas': 0,
      'aplica_compras': 1,
      'activo': 1,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _sembrarSecuencias(Database db) async {
    final companyId = await _sincronizarEmpresaLegacy(db);
    final secuencias = [
      {'tipo': 'asiento', 'prefijo': 'AC', 'siguiente': 1},
      {'tipo': 'venta', 'prefijo': 'VT', 'siguiente': 1},
      {'tipo': 'ventas', 'prefijo': 'VT', 'siguiente': 1},
      {'tipo': 'compra', 'prefijo': 'CP', 'siguiente': 1},
      {'tipo': 'compras', 'prefijo': 'CP', 'siguiente': 1},
      {'tipo': 'egreso', 'prefijo': 'EG', 'siguiente': 1},
      {'tipo': 'ingreso', 'prefijo': 'IN', 'siguiente': 1},
      {'tipo': 'caja', 'prefijo': 'CJ', 'siguiente': 1},
      {'tipo': 'transferencias', 'prefijo': 'TR', 'siguiente': 1},
      {'tipo': 'cuentas_por_pagar', 'prefijo': 'CXP', 'siguiente': 1},
      {'tipo': 'cuentas_por_cobrar', 'prefijo': 'CXC', 'siguiente': 1},
    ];

    for (final secuencia in secuencias) {
      await db.insert('secuencias_documentos', {
        'company_id': companyId,
        ...secuencia,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _crearTablasContables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cuentas_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL,
        naturaleza TEXT NOT NULL,
        activa INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS asientos_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        concepto TEXT NOT NULL,
        referencia TEXT,
        origen TEXT NOT NULL DEFAULT 'manual',
        estado TEXT NOT NULL DEFAULT 'registrado'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS asiento_lineas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        asiento_id INTEGER NOT NULL,
        cuenta_id INTEGER NOT NULL,
        descripcion TEXT,
        debito REAL NOT NULL DEFAULT 0,
        credito REAL NOT NULL DEFAULT 0,
        tercero TEXT,
        FOREIGN KEY (asiento_id) REFERENCES asientos_contables(id),
        FOREIGN KEY (cuenta_id) REFERENCES cuentas_contables(id)
      )
    ''');
  }

  Future<void> _sembrarPlanCuentas(Database db) async {
    final cuentas = [
      // Clase 1: Activos
      {
        'codigo': '1',
        'nombre': 'Activo',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '11',
        'nombre': 'Disponible',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1105',
        'nombre': 'Caja',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '110505',
        'nombre': 'Caja General',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '110510',
        'nombre': 'Cajas Menores',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1110',
        'nombre': 'Bancos',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '111005',
        'nombre': 'Bancos Nacionales',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1120',
        'nombre': 'Cuentas de Ahorro',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '12',
        'nombre': 'Inversiones',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1205',
        'nombre': 'Inversiones corrientes',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '13',
        'nombre': 'Deudores / Cartera',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1305',
        'nombre': 'Cuentas por cobrar (Clientes)',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '130505',
        'nombre': 'Clientes Nacionales',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1325',
        'nombre': 'Anticipos y avances',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1355',
        'nombre': 'Impuestos descontables (Anticipos)',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135515',
        'nombre': 'Retencion en la fuente',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135517',
        'nombre': 'Impuesto a las ventas y retenido',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135518',
        'nombre': 'Impuesto de Industria y comercio y retenido',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135520',
        'nombre': 'Impuesto de Industria y comercio descontable',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135525',
        'nombre': 'Impuesto de Avisos y Tableros retenido',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '135530',
        'nombre': 'Impuesto de Avisos y Tableros descontable',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1365',
        'nombre': 'Cuentas por cobrar a trabajadores',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '14',
        'nombre': 'Inventarios',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1435',
        'nombre': 'Inventario (Mercancias no fab. por la empresa)',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '15',
        'nombre': 'Propiedades, Planta y Equipo',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1504',
        'nombre': 'Terrenos',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1516',
        'nombre': 'Construcciones y Edificaciones',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1520',
        'nombre': 'Maquinaria y Equipo',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1524',
        'nombre': 'Equipo de Oficina',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1528',
        'nombre': 'Equipo de Computacion y Comunicacion',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1592',
        'nombre': 'Depreciacion Acumulada',
        'tipo': 'activo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '17',
        'nombre': 'Diferidos',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '1705',
        'nombre': 'Gastos Pagados por Anticipado',
        'tipo': 'activo',
        'naturaleza': 'debito',
      },

      // Clase 2: Pasivos
      {
        'codigo': '2',
        'nombre': 'Pasivo',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '21',
        'nombre': 'Obligaciones Financieras',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2105',
        'nombre': 'Obligaciones financieras (Bancos)',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '22',
        'nombre': 'Proveedores',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2205',
        'nombre': 'Proveedores Nacionales',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '23',
        'nombre': 'Cuentas por Pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2335',
        'nombre': 'Costos y gastos por pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2365',
        'nombre': 'Retencion en la fuente por pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2367',
        'nombre': 'Impuesto de industria y comercial retenido (ReteICA)',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2368',
        'nombre': 'Retencion de IVA (ReteIVA) por pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2370',
        'nombre': 'Retenciones y aportes de nomina',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2380',
        'nombre': 'Acreedores varios',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '24',
        'nombre': 'Impuestos, Gravamenes y Tasas',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2408',
        'nombre': 'Impuestos por pagar (IVA)',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '25',
        'nombre': 'Obligaciones Laborales',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2505',
        'nombre': 'Salarios por pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2510',
        'nombre': 'Cesantias consolidadas',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2515',
        'nombre': 'Intereses sobre cesantias',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2520',
        'nombre': 'Prima de servicios por pagar',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },
      {
        'codigo': '2525',
        'nombre': 'Vacaciones consolidadas',
        'tipo': 'pasivo',
        'naturaleza': 'credito',
      },

      // Clase 3: Patrimonio
      {
        'codigo': '3',
        'nombre': 'Patrimonio',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '31',
        'nombre': 'Capital Social',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3105',
        'nombre': 'Capital suscrito y pagado',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3115',
        'nombre': 'Capital Social (Aportes)',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '33',
        'nombre': 'Reservas',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3305',
        'nombre': 'Reservas obligatorias',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '36',
        'nombre': 'Resultados del Ejercicio',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3605',
        'nombre': 'Utilidad del ejercicio',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3610',
        'nombre': 'Perdida del ejercicio',
        'tipo': 'patrimonio',
        'naturaleza': 'debito',
      },
      {
        'codigo': '37',
        'nombre': 'Resultados acumulados',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },
      {
        'codigo': '3705',
        'nombre': 'Utilidades o perdidas acumuladas',
        'tipo': 'patrimonio',
        'naturaleza': 'credito',
      },

      // Clase 4: Ingresos
      {
        'codigo': '4',
        'nombre': 'Ingresos',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },
      {
        'codigo': '41',
        'nombre': 'Ingresos Operacionales',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },
      {
        'codigo': '4135',
        'nombre': 'Ingresos por ventas (Comercio al por mayor/menor)',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },
      {
        'codigo': '4175',
        'nombre': 'Devoluciones en ventas',
        'tipo': 'ingreso',
        'naturaleza': 'debito',
      },
      {
        'codigo': '42',
        'nombre': 'Ingresos No Operacionales',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },
      {
        'codigo': '4210',
        'nombre': 'Ingresos financieros',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },
      {
        'codigo': '4295',
        'nombre': 'Ingresos diversos',
        'tipo': 'ingreso',
        'naturaleza': 'credito',
      },

      // Clase 5: Gastos
      {
        'codigo': '5',
        'nombre': 'Gastos',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '51',
        'nombre': 'Gastos Operacionales de Administracion',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5105',
        'nombre': 'Gastos de personal (Nomina)',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5110',
        'nombre': 'Honorarios',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5115',
        'nombre': 'Impuestos operacionales',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5120',
        'nombre': 'Arrendamientos',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5125',
        'nombre': 'Seguros',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5130',
        'nombre': 'Servicios publicos/comerciales',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5135',
        'nombre': 'Gastos operacionales / Diversos',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5140',
        'nombre': 'Servicios directos',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5160',
        'nombre': 'Depreciaciones',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '52',
        'nombre': 'Gastos Operacionales de Ventas',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5205',
        'nombre': 'Gastos de personal (Ventas)',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5220',
        'nombre': 'Arrendamientos (Ventas)',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5235',
        'nombre': 'Servicios (Ventas)',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '53',
        'nombre': 'Gastos No Operacionales',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },
      {
        'codigo': '5305',
        'nombre': 'Gastos financieros (Comisiones/Intereses)',
        'tipo': 'gasto',
        'naturaleza': 'debito',
      },

      // Clase 6: Costo de Ventas
      {
        'codigo': '6',
        'nombre': 'Costos',
        'tipo': 'costo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '61',
        'nombre': 'Costo de Ventas',
        'tipo': 'costo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '6135',
        'nombre': 'Costo de ventas (Comercio)',
        'tipo': 'costo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '62',
        'nombre': 'Compras',
        'tipo': 'costo',
        'naturaleza': 'debito',
      },
      {
        'codigo': '6205',
        'nombre': 'Compras de mercancias',
        'tipo': 'costo',
        'naturaleza': 'debito',
      },
    ];

    for (final cuenta in cuentas) {
      await db.insert(
        'cuentas_contables',
        cuenta,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ── Productos ────────────────────────────────────────────

  /// Inserta un nuevo producto y devuelve su id generado.
  Future<int> insertarProducto(Map<String, dynamic> row) async {
    await validarFeatureHabilitada(FeatureKey.inventory);
    final db = await instance.database;
    final data = await _conEmpresa(row);
    final id = await db.insert('productos', data);
    await _enqueueProductUpsertIfPossible(db, data['company_id'] as int, id);
    return id;
  }

  /// Devuelve todos los productos ordenados alfabéticamente.
  Future<List<Map<String, dynamic>>> obtenerProductos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'productos',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
  }

  /// Actualiza los datos de un producto existente.
  Future<int> actualizarProducto(int id, Map<String, dynamic> datos) async {
    await validarFeatureHabilitada(FeatureKey.inventory);
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final updated = await db.update(
      'productos',
      datos,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
    if (updated > 0) {
      await _enqueueProductUpsertIfPossible(db, companyId, id);
    }
    return updated;
  }

  /// Elimina un producto por su id.
  Future<int> eliminarProducto(int id) async {
    await validarFeatureHabilitada(FeatureKey.inventory);
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.delete(
      'productos',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  /// Actualiza únicamente el stock de un producto.
  /// Registra un nuevo lote de producto.
  Future<int> registrarLote({
    required int productoId,
    required String codigoLote,
    required String fechaVencimiento,
    required double cantidad,
    required MoneyValue costo,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.insert('lotes', {
      'company_id': companyId,
      'producto_id': productoId,
      'codigo_lote': codigoLote,
      'fecha_vencimiento': fechaVencimiento,
      'cantidad': cantidad,
      'costo': costo.toSql(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Obtiene todos los lotes de un producto.
  Future<List<Map<String, dynamic>>> obtenerLotesPorProducto(
    int productoId,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'lotes',
      where: 'company_id = ? AND producto_id = ?',
      whereArgs: [companyId, productoId],
      orderBy: 'fecha_vencimiento ASC',
    );
  }

  /// Actualiza la cantidad de un lote específico.
  Future<int> actualizarCantidadLote(int loteId, double nuevaCantidad) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.update(
      'lotes',
      {'cantidad': nuevaCantidad},
      where: 'id = ? AND company_id = ?',
      whereArgs: [loteId, companyId],
    );
  }

  Future actualizarStock(int id, double nuevoStock) async {
    if (nuevoStock < 0) {
      throw Exception('El stock no puede quedar negativo.');
    }
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await db.update(
      'productos',
      {'stock': nuevoStock},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  // ── Ventas ───────────────────────────────────────────────

  /// Registra una nueva venta.
  Future<int> insertarVenta(Map<String, dynamic> row) async {
    await validarFeatureHabilitada(FeatureKey.pos);
    final db = await instance.database;

    // Inserta SOLO la cabecera de la venta
    final id = await db.insert('ventas', await _conEmpresa(row));

    return id;
  }

  /// Devuelve todas las ventas, más recientes primero.
  Future<List<Map<String, dynamic>>> obtenerVentas() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'ventas',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleVenta(int ventaId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        vd.*,
        p.unidad_base,
        p.codigo_barras
      FROM ventas_detalle vd
      INNER JOIN ventas v ON v.id = vd.venta_id
      LEFT JOIN productos p ON p.id = vd.producto_id
      WHERE vd.venta_id = ? AND v.company_id = ?
      ORDER BY vd.id ASC
      ''',
      [ventaId, companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleCompra(int compraId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        cd.*,
        p.unidad_base,
        p.codigo_barras
      FROM compras_detalle cd
      INNER JOIN compras c ON c.id = cd.compra_id
      LEFT JOIN productos p ON p.id = cd.producto_id
      WHERE cd.compra_id = ? AND c.company_id = ?
      ORDER BY cd.id ASC
      ''',
      [compraId, companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerVentasActivas() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'ventas',
      where: "company_id = ? AND COALESCE(estado, 'emitida') != 'anulada'",
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  /// Devuelve todas las compras registradas.
  Future<List<Map<String, dynamic>>> obtenerCompras() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    return await db.query(
      'compras',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  /// Compatibilidad con llamadas antiguas: una venta emitida nunca se borra.
  /// Se anula de forma transaccional para conservar inventario, cartera, caja y auditoría.
  Future<int> eliminarVenta(int id) async {
    await anularVenta(id);
    return 1;
  }

  Future<void> anularVenta(int ventaId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    await db.transaction((txn) async {
      final ventas = await txn.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
      );
      if (ventas.isEmpty) {
        throw Exception('La venta no existe.');
      }

      final venta = ventas.first;
      if ((venta['estado']?.toString() ?? 'emitida') == 'anulada') {
        throw Exception('La venta ya fue anulada.');
      }

      final detalles = await txn.query(
        'ventas_detalle',
        where: 'venta_id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
      );

      for (final item in detalles) {
        final productoId = (item['producto_id'] as num?)?.toInt() ?? 0;
        final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;
        if (productoId <= 0 || cantidad <= 0) continue;

        final productos = await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [productoId, companyId],
        );
        if (productos.isEmpty) continue;

        final stockActual = (productos.first['stock'] as num).toDouble();
        final stockNuevo = stockActual + cantidad;
        await txn.update(
          'productos',
          {'stock': stockNuevo},
          where: 'id = ? AND company_id = ?',
          whereArgs: [productoId, companyId],
        );
        final currentCost = MoneyValue.fromSql(
          productos.first['costo'],
          currency: currency,
          nullableAsZero: true,
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productoId,
          type: 'entrada',
          quantity: cantidad,
          stockBefore: stockActual,
          stockAfter: stockNuevo,
          costBeforeMinor: currentCost.toSql(),
          costAfterMinor: currentCost.toSql(),
          costTotalMinor: currentCost
              .multiplyDecimal(cantidad.toString())
              .toSql(),
          reason: 'ANULACION VENTA #$ventaId',
          date: DateTime.now().toIso8601String(),
          documentType: 'anulacion_venta',
          documentId: ventaId,
        );
      }

      final metodo = await txn.query(
        'metodos_pago',
        where: 'id = ?',
        whereArgs: [venta['metodo_pago_id']],
      );
      final nombreMetodo = metodo.isEmpty
          ? ''
          : metodo.first['nombre'].toString().toUpperCase().trim();
      final total = MoneyValue.fromSql(
        venta['total'],
        currency: currency,
        nullableAsZero: true,
      );

      final efectivo = MoneyValue.fromSql(
        venta['efectivo'],
        currency: currency,
        nullableAsZero: true,
      );
      final transferencia = MoneyValue.fromSql(
        venta['transferencia'],
        currency: currency,
        nullableAsZero: true,
      );
      final credito = MoneyValue.fromSql(
        venta['credito'],
        currency: currency,
        nullableAsZero: true,
      );
      final hasSplit = (efectivo + transferencia + credito).minorUnits > 0;
      final now = DateTime.now().toIso8601String();

      Future<void> reverseComponent(
        MoneyValue amount,
        String origin,
        String label,
      ) async {
        if (amount.minorUnits <= 0) return;
        await txn.insert('movimientos_caja', {
          'company_id': companyId,
          'tipo': 'egreso',
          'concepto': 'Anulación venta #$ventaId ($label)',
          'monto': amount.toSql(),
          'fecha': now,
          'origen': origin,
        });
      }

      if (hasSplit) {
        await reverseComponent(efectivo, 'caja', 'Efectivo');
        await reverseComponent(transferencia, 'banco', 'Transferencia');
        await reverseComponent(credito, 'cartera', 'Crédito');
        if (credito.minorUnits > 0) {
          await txn.update(
            'cuentas_por_cobrar',
            {'estado': 'anulada', 'saldo': 0},
            where: 'venta_id = ? AND company_id = ?',
            whereArgs: [ventaId, companyId],
          );
        }
      } else if (nombreMetodo == 'CREDITO') {
        await txn.update(
          'cuentas_por_cobrar',
          {'estado': 'anulada', 'saldo': 0},
          where: 'venta_id = ? AND company_id = ?',
          whereArgs: [ventaId, companyId],
        );
        await reverseComponent(total, 'cartera', 'Crédito');
      } else {
        final origen =
            nombreMetodo == 'TRANSFERENCIA' ||
                nombreMetodo == 'TARJETA' ||
                nombreMetodo == 'NEQUI' ||
                nombreMetodo == 'DAVIPLATA'
            ? 'banco'
            : 'caja';
        await reverseComponent(
          total,
          origen,
          nombreMetodo.isEmpty ? 'Pago' : nombreMetodo,
        );
      }

      await txn.update(
        'ventas',
        {'estado': 'anulada'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
      );
      await txn.insert('auditoria_eventos', {
        'company_id': companyId,
        'fecha': DateTime.now().toIso8601String(),
        'accion': 'ANULAR_VENTA',
        'entidad': 'ventas',
        'entidad_id': ventaId,
        'detalle': 'Venta anulada, stock restaurado y saldos revertidos',
        'usuario': AuditIdentity.current,
      });
    });
  }

  Future<void> eliminarCompra(int compraId) async {
    try {
      final db = await instance.database;
      final companyId = await obtenerEmpresaActivaId();
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );

      await db.transaction((txn) async {
        // 🔥 OBTENER COMPRA
        final compras = await txn.query(
          'compras',
          where: 'id = ? AND company_id = ?',
          whereArgs: [compraId, companyId],
        );

        if (compras.isEmpty) return;

        final compra = compras.first;

        // 🚫 si ya estaba anulada
        if (compra['estado'] == 'anulada') {
          throw Exception('La compra ya fue anulada.');
        }

        final total = MoneyValue.fromSql(compra['total'], currency: currency);
        final efectivo = MoneyValue.fromSql(
          compra['efectivo'],
          currency: currency,
          nullableAsZero: true,
        );
        final transferencia = MoneyValue.fromSql(
          compra['transferencia'],
          currency: currency,
          nullableAsZero: true,
        );
        final credito = MoneyValue.fromSql(
          compra['credito'],
          currency: currency,
          nullableAsZero: true,
        );
        final metodoPagoId = compra['metodo_pago_id'];

        // 🔥 OBTENER MÉTODO DE PAGO
        final metodo = await txn.query(
          'metodos_pago',
          where: 'id = ?',
          whereArgs: [metodoPagoId],
        );

        String nombreMetodo = 'EFECTIVO';

        if (metodo.isNotEmpty && metodo.first['nombre'] != null) {
          nombreMetodo = metodo.first['nombre'].toString();
        }

        // 🔥 OBTENER DETALLE
        final detalles = await txn.query(
          'compras_detalle',
          where: 'compra_id = ? AND company_id = ?',
          whereArgs: [compraId, companyId],
        );

        for (final item in detalles) {
          final productoId = (item['producto_id'] as num?)?.toInt() ?? 0;
          final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;
          if (productoId == 0 || cantidad <= 0) continue;

          final productos = await txn.query(
            'productos',
            where: 'id = ? AND company_id = ?',
            whereArgs: [productoId, companyId],
          );
          if (productos.isEmpty) continue;

          final stockActual =
              (productos.first['stock'] as num?)?.toDouble() ?? 0;
          if (stockActual < cantidad) {
            throw Exception(
              'No se puede anular la compra #$compraId porque ${item['producto']} ya fue vendido o consumido. Stock actual: $stockActual, requerido: $cantidad.',
            );
          }
        }

        // 🔥 DEVOLVER STOCK
        for (final item in detalles) {
          final productoId = (item['producto_id'] as num?)?.toInt() ?? 0;
          final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;

          if (productoId == 0) continue;

          final productos = await txn.query(
            'productos',
            where: 'id = ? AND company_id = ?',
            whereArgs: [productoId, companyId],
          );

          if (productos.isEmpty) continue;

          final producto = productos.first;
          final stockActual = (producto['stock'] as num?)?.toDouble() ?? 0;
          final nuevoStock = stockActual - cantidad;

          await txn.update(
            'productos',
            {'stock': nuevoStock},
            where: 'id = ? AND company_id = ?',
            whereArgs: [productoId, companyId],
          );

          final currentCost = MoneyValue.fromSql(
            producto['costo'],
            currency: currency,
            nullableAsZero: true,
          );
          await InventoryMovementService.record(
            db: txn,
            companyId: companyId,
            productId: productoId,
            type: 'salida',
            quantity: cantidad,
            stockBefore: stockActual,
            stockAfter: nuevoStock,
            costBeforeMinor: currentCost.toSql(),
            costAfterMinor: currentCost.toSql(),
            costTotalMinor: currentCost
                .multiplyDecimal(cantidad.toString())
                .toSql(),
            reason: 'ANULACION COMPRA #$compraId',
            date: DateTime.now().toIso8601String(),
            documentType: 'anulacion_compra',
            documentId: compraId,
          );
        }

        final metodoUpper = nombreMetodo.toString().trim().toUpperCase();

        if (efectivo.minorUnits > 0) {
          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Anulacion compra #$compraId (Caja)',
            'monto': efectivo.toSql(),
            'fecha': DateTime.now().toIso8601String(),
            'origen': 'caja',
          });
        }
        if (transferencia.minorUnits > 0) {
          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Anulacion compra #$compraId (Banco)',
            'monto': transferencia.toSql(),
            'fecha': DateTime.now().toIso8601String(),
            'origen': 'banco',
          });
        }

        if (efectivo.minorUnits == 0 &&
            transferencia.minorUnits == 0 &&
            credito.minorUnits == 0 &&
            (metodoUpper == 'EFECTIVO' ||
                metodoUpper == 'TRANSFERENCIA' ||
                metodoUpper == 'TARJETA' ||
                metodoUpper == 'NEQUI' ||
                metodoUpper == 'DAVIPLATA')) {
          final cuenta =
              (metodoUpper == 'TRANSFERENCIA' ||
                  metodoUpper == 'TARJETA' ||
                  metodoUpper == 'NEQUI' ||
                  metodoUpper == 'DAVIPLATA')
              ? 'banco'
              : 'caja';

          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Anulación compra #$compraId',
            'monto': total.toSql(),
            'fecha': DateTime.now().toIso8601String(),
            'origen': cuenta,
          });
        }

        // 🔥 SI ERA CRÉDITO → CANCELAR DEUDA
        if (metodoUpper == 'CREDITO' || credito.minorUnits > 0) {
          await txn.update(
            'cuentas_por_pagar',
            {'estado': 'anulada', 'saldo': 0},
            where: 'compra_id = ? AND company_id = ?',
            whereArgs: [compraId, companyId],
          );
        }

        await txn.update(
          'compras',
          {'estado': 'anulada'},
          where: 'id = ? AND company_id = ?',
          whereArgs: [compraId, companyId],
        );

        await txn.insert('auditoria_eventos', {
          'company_id': companyId,
          'fecha': DateTime.now().toIso8601String(),
          'accion': 'ANULAR_COMPRA',
          'entidad': 'compras',
          'entidad_id': compraId,
          'detalle': 'Compra anulada y stock revertido',
          'usuario': AuditIdentity.current,
        });
      });
    } catch (e) {
      throw Exception('Error anulando compra: $e');
    }
  }

  // ── Métodos de Pago ───────────────────────────────────

  /// Devuelve todos los métodos de pago registrados.
  Future<List<Map<String, dynamic>>> obtenerMetodosPago() async {
    final db = await instance.database;
    return await db.query('metodos_pago', orderBy: 'nombre ASC');
  }

  // ── Movimientos de Caja ──────────────────────────────────

  /// Registra un movimiento de caja (ingreso o egreso).
  Future<int> insertarMovimiento(Map<String, dynamic> row) async {
    await validarFeatureHabilitada(FeatureKey.cash);
    final tipo = row['tipo']?.toString() ?? '';
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final monto = MoneyValue.fromSql(
      row['monto'],
      currency: currency,
      nullableAsZero: true,
    );
    final origen = row['origen']?.toString() ?? 'caja';
    if ((tipo == 'egreso' || tipo == 'transferencia') && monto.minorUnits > 0) {
      await validarSaldoSuficiente(
        origen: origen,
        monto: monto,
        bancoId: row['banco_id'] as int?,
      );
    }
    return await db.insert('movimientos_caja', await _conEmpresa(row));
  }

  /// Devuelve todos los movimientos activos, más recientes primero.
  Future<List<Map<String, dynamic>>> obtenerMovimientos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'movimientos_caja',
      where: 'company_id = ? AND COALESCE(activo, 1) = 1',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  /// Movimientos de caja en un rango de fechas (solo activos).
  Future<List<Map<String, dynamic>>> obtenerMovimientosPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    String? origen,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final inicio = desde.toIso8601String();
    final fin = hasta.add(const Duration(days: 1)).toIso8601String();
    var where =
        'company_id = ? AND COALESCE(activo, 1) = 1 AND fecha >= ? AND fecha < ?';
    final args = <Object>[companyId, inicio, fin];
    if (origen != null && origen.isNotEmpty && origen != 'todas') {
      where += ' AND origen = ?';
      args.add(origen);
    }
    return await db.query(
      'movimientos_caja',
      where: where,
      whereArgs: args,
      orderBy: 'fecha ASC',
    );
  }

  /// Valida que haya fondos suficientes antes de un egreso.
  Future<void> validarSaldoSuficiente({
    required String origen,
    required MoneyValue monto,
    int? bancoId,
  }) async {
    if (origen == 'cartera') return;
    MoneyValue saldo;
    if (bancoId != null) {
      saldo = await obtenerSaldoBanco(bancoId);
    } else {
      saldo = await obtenerSaldoPorCuenta(origen);
    }
    if (saldo < monto) {
      throw Exception(
        'Fondos insuficientes. Saldo disponible: ${saldo.format()}',
      );
    }
  }

  /// Elimina un movimiento por su id.
  Future<int> eliminarMovimiento(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.delete(
      'movimientos_caja',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<void> transferirEntreCuentas({
    required String origen,
    required String destino,
    required MoneyValue monto,
    required String concepto,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    // 🔴 validar saldo
    final saldoOrigen = await obtenerSaldoPorCuenta(origen);

    if (saldoOrigen < monto) {
      throw Exception('Saldo insuficiente en $origen');
    }

    final now = DateTime.now().toIso8601String();

    // 🔴 salida (egreso del origen)
    await db.insert('movimientos_caja', {
      'company_id': companyId,
      'tipo': 'transferencia',
      'concepto': 'Transferencia: $origen → $destino',
      'monto': monto.toSql(),
      'fecha': now,
      'origen': origen,
    });

    // 🔵 entrada (ingreso al destino)
    await db.insert('movimientos_caja', {
      'company_id': companyId,
      'tipo': 'ingreso',
      'concepto': concepto,
      'monto': monto.toSql(),
      'fecha': now,
      'origen': destino,
    });

    await registrarAsientoTransferencia(
      origen: origen,
      destino: destino,
      monto: monto,
      concepto: concepto,
    );
  }

  Future<MoneyValue> obtenerSaldoPorCuenta(String cuenta) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);

    // 🟢 Caja y Banco funcionan normal
    if (cuenta == 'caja' || cuenta == 'banco') {
      final resIngresos = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total "
        "FROM movimientos_caja "
        "WHERE company_id = ? AND COALESCE(activo, 1) = 1 "
        "AND tipo = 'ingreso' AND origen = ?",
        [companyId, cuenta],
      );

      final resEgresos = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total "
        "FROM movimientos_caja "
        "WHERE company_id = ? AND COALESCE(activo, 1) = 1 "
        "AND tipo IN ('egreso', 'transferencia') AND origen = ?",
        [companyId, cuenta],
      );

      final ingresos = MoneyValue.fromSql(
        resIngresos.first['total'],
        currency: currency,
      );
      final egresos = MoneyValue.fromSql(
        resEgresos.first['total'],
        currency: currency,
      );

      return ingresos - egresos;
    }

    // 🔴 CARTERA = SOLO DEUDA (NO DINERO REAL)
    if (cuenta == 'cartera') {
      final res = await db.rawQuery(
        '''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM movimientos_caja
      WHERE company_id = ? AND origen = 'cartera' AND tipo = 'ingreso'
    ''',
        [companyId],
      );

      return MoneyValue.fromSql(res.first['total'], currency: currency);
    }

    return zero;
  }

  /// Suma el total de todas las ventas registradas.
  Future<MoneyValue> obtenerTotalVentas() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final res = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND COALESCE(estado, 'emitida') != 'anulada'",
      [companyId],
    );
    return MoneyValue.fromSql(res.first['total'], currency: currency);
  }

  Future<MoneyValue> obtenerSaldoPorOrigen(String origen) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    final res = await db.rawQuery(
      '''
    SELECT COALESCE(SUM(monto), 0) AS total
    FROM movimientos_caja
    WHERE company_id = ? AND origen = ?
  ''',
      [companyId, origen],
    );

    return MoneyValue.fromSql(res.first['total'], currency: currency);
  }
  // ── Proveedores ───────────────────────────────────────────

  Future<int> insertarProveedor(Map<String, dynamic> row) async {
    await validarFeatureHabilitada(FeatureKey.purchases);
    final db = await instance.database;

    return await db.insert('proveedores', await _conEmpresa(row));
  }

  Future<List<Map<String, dynamic>>> obtenerProveedores() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    return await db.query(
      'proveedores',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
  }

  Future<int> actualizarProveedor(int id, Map<String, dynamic> datos) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    return await db.update(
      'proveedores',
      datos,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<int> eliminarProveedor(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    return await db.delete(
      'proveedores',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<bool> proveedorTieneCompras(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final res = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM compras WHERE proveedor_id = ? AND company_id = ?',
      [id, companyId],
    );
    return ((res.first['total'] as num?)?.toInt() ?? 0) > 0;
  }

  Future<int> insertarCliente(Map<String, dynamic> row) async {
    await validarFeatureHabilitada(FeatureKey.crm);
    final db = await instance.database;
    final data = await _conEmpresa(row);
    final id = await db.insert('clientes', data);
    await _enqueueCustomerUpsertIfPossible(db, data['company_id'] as int, id);
    return id;
  }

  Future<List<Map<String, dynamic>>> obtenerClientes() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'clientes',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
  }

  Future<int> actualizarCliente(int id, Map<String, dynamic> datos) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final updated = await db.update(
      'clientes',
      datos,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
    if (updated > 0) {
      await _enqueueCustomerUpsertIfPossible(db, companyId, id);
    }
    return updated;
  }

  Future<void> _enqueueProductUpsertIfPossible(
    DatabaseExecutor db,
    int companyId,
    int productId,
  ) async {
    try {
      await const MerkaMasterDataSyncOutboxWriter().enqueueProductUpserted(
        db: db,
        companyId: companyId,
        productId: productId,
      );
    } catch (e) {
      debugPrint('Error en merka_sync_outbox para producto: $e');
    }
  }

  Future<void> _enqueueCustomerUpsertIfPossible(
    DatabaseExecutor db,
    int companyId,
    int customerId,
  ) async {
    try {
      await const MerkaMasterDataSyncOutboxWriter().enqueueCustomerUpserted(
        db: db,
        companyId: companyId,
        customerId: customerId,
      );
    } catch (e) {
      debugPrint('Error en merka_sync_outbox para cliente: $e');
    }
  }

  Future<int> eliminarCliente(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.delete(
      'clientes',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerCuentasPorCobrar() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'cuentas_por_cobrar',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<int> registrarCuentaPorCobrar({
    required int ventaId,
    required MoneyValue total,
    int? clienteId,
    String cliente = 'Cliente general',
    String descripcion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.insert('cuentas_por_cobrar', {
      'company_id': companyId,
      'cliente_id': clienteId,
      'cliente': cliente,
      'venta_id': ventaId,
      'total': total.toSql(),
      'saldo': total.toSql(),
      'estado': 'pendiente',
      'fecha': DateTime.now().toIso8601String(),
      'descripcion': descripcion.isEmpty
          ? 'Venta a crédito #$ventaId'
          : descripcion,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerAbonosCXC(int cuentaId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'abonos_cxc',
      where: 'cuenta_id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<void> registrarAbonoCXC({
    required int cuentaId,
    required MoneyValue monto,
    required String metodoPago,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    final cuentas = await db.query(
      'cuentas_por_cobrar',
      where: 'id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
    );

    if (cuentas.isEmpty) return;

    final cuenta = cuentas.first;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final saldoActual = MoneyValue.fromSql(cuenta['saldo'], currency: currency);
    if (monto.minorUnits <= 0) {
      throw Exception('El abono debe ser mayor que cero.');
    }
    if (monto > saldoActual) {
      throw Exception('El abono no puede superar el saldo pendiente.');
    }
    final nuevoSaldo = saldoActual - monto;
    final nuevoEstado = nuevoSaldo.minorUnits == 0 ? 'pagada' : 'parcial';

    await db.insert('abonos_cxc', {
      'company_id': companyId,
      'cuenta_id': cuentaId,
      'monto': monto.toSql(),
      'metodo_pago': metodoPago,
      'observacion': observacion,
      'fecha': DateTime.now().toIso8601String(),
    });

    await db.update(
      'cuentas_por_cobrar',
      {'saldo': nuevoSaldo.toSql(), 'estado': nuevoEstado},
      where: 'id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
    );

    final origen = metodoPago.toUpperCase() == 'EFECTIVO' ? 'caja' : 'banco';

    await db.insert('movimientos_caja', {
      'company_id': companyId,
      'tipo': 'ingreso',
      'concepto': 'Abono cuenta por cobrar #$cuentaId',
      'monto': monto.toSql(),
      'fecha': DateTime.now().toIso8601String(),
      'origen': origen,
    });

    // Actualizar saldo de cuenta bancaria o caja
    if (origen == 'banco') {
      final cuentasBancarias = await db.query(
        'treasury_bank_accounts',
        where: 'company_id = ?',
        whereArgs: [companyId],
        limit: 1,
      );
      if (cuentasBancarias.isNotEmpty) {
        final saldoActual = MoneyValue.fromSql(
          cuentasBancarias.first['current_balance'],
          currency: currency,
          nullableAsZero: true,
        );
        await db.update(
          'treasury_bank_accounts',
          {'current_balance': (saldoActual + monto).toSql()},
          where: 'id = ?',
          whereArgs: [cuentasBancarias.first['id']],
        );
      }
    }

    await registrarAsientoAbonoCXC(
      cuentaId: cuentaId,
      monto: monto,
      metodoPago: metodoPago,
    );

    // Trigger asíncrono: Actualizar comisiones por recaudo (anti-fraude)
    // No bloquea la operación principal, si falla solo se loguea el error
    final ventaId = cuenta['venta_id'] as int?;
    if (ventaId != null && nuevoEstado == 'pagada') {
      Future.microtask(() async {
        try {
          await actualizarComisionesPorRecaudo(ventaId);
        } catch (e) {
          // Loguear error en auditoría pero no afectar la operación principal
          await registrarEventoAuditoria(
            accion: 'ERROR_COMISIONES_RECAUDO',
            entidad: 'comisiones_liquidadas',
            entidadId: ventaId,
            detalle: 'Error al actualizar comisiones por recaudo: $e',
          );
        }
      });
    }

    // Trigger asíncrono: Encolar sincronización con Control Center
    final abonoId = await db.query(
      'abonos_cxc',
      where: 'cuenta_id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (abonoId.isNotEmpty) {
      final idAbono = abonoId.first['id'] as int;
      Future.microtask(() async {
        try {
          final payload = {
            'payment_id': idAbono,
            'account_id': cuentaId,
            'amount': monto.toWireMap(),
            'payment_method': metodoPago,
            'observation': observacion,
            'date': DateTime.now().toIso8601String(),
            'new_balance': nuevoSaldo.toWireMap(),
            'status': nuevoEstado,
            'sale_id': ventaId,
          };
          await enqueueSync(
            table: 'accounts_receivable',
            recordId: idAbono.toString(),
            action: 'UPDATE',
            payload: jsonEncode(payload),
          );
        } catch (e) {
          // Loguear error pero no afectar la operación principal
          debugPrint('Error en enqueueSync para abono: $e');
        }
      });
    }
  }

  Future<int> registrarCierreCaja({
    required MoneyValue efectivoContado,
    String observacion = '',
    required MoneyValue baseAperturaSiguiente,
    bool arqueoCiego = true,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final saldoSistema = await obtenerSaldoPorCuenta('caja');
    final diferencia = efectivoContado - saldoSistema;
    final excedente = efectivoContado - baseAperturaSiguiente;
    var retiroBanco = MoneyValue(
      minorUnits: 0,
      currency: efectivoContado.currency,
    );

    if (baseAperturaSiguiente.minorUnits > 0 && excedente.minorUnits > 0) {
      retiroBanco = excedente;
      await insertarMovimiento({
        'tipo': 'transferencia',
        'concepto':
            'Retiro cierre caja → Bancos (base ${baseAperturaSiguiente.format()})',
        'monto': retiroBanco.toSql(),
        'fecha': DateTime.now().toIso8601String(),
        'origen': 'caja',
      });
      await insertarMovimiento({
        'tipo': 'ingreso',
        'concepto': 'Depósito desde cierre de caja',
        'monto': retiroBanco.toSql(),
        'fecha': DateTime.now().toIso8601String(),
        'origen': 'banco',
      });
      await registrarAsientoTransferencia(
        origen: 'caja',
        destino: 'banco',
        monto: retiroBanco,
        concepto: 'Cierre caja: traslado excedente a bancos',
      );
    }

    final id = await db.insert('cierres_caja', {
      'company_id': companyId,
      'fecha': DateTime.now().toIso8601String(),
      'saldo_sistema': saldoSistema.toSql(),
      'efectivo_contado': efectivoContado.toSql(),
      'diferencia': diferencia.toSql(),
      'observacion': observacion,
      'estado': 'cerrado',
      'base_apertura_siguiente': baseAperturaSiguiente.toSql(),
      'retiro_banco': retiroBanco.toSql(),
      'arqueo_ciego': arqueoCiego ? 1 : 0,
    });

    await registrarEventoAuditoria(
      accion: 'CIERRE_CAJA',
      entidad: 'cierres_caja',
      entidadId: id,
      detalle:
          'Sistema: $saldoSistema, contado: $efectivoContado, diferencia: $diferencia, base: $baseAperturaSiguiente, retiro banco: $retiroBanco',
    );
    await cambiarBloqueoOperativo(true);

    return id;
  }

  Future<List<Map<String, dynamic>>> obtenerCierresCaja() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'cierres_caja',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<int> registrarConciliacionBancaria({
    required String cuenta,
    required MoneyValue saldoExtracto,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final cuentaNormalizada = cuenta.trim().toLowerCase();
    final saldoLibros = await obtenerSaldoPorCuenta(cuentaNormalizada);
    final diferencia = saldoExtracto - saldoLibros;

    final id = await db.insert('conciliaciones_bancarias', {
      'fecha': DateTime.now().toIso8601String(),
      'cuenta': cuentaNormalizada,
      'saldo_libros': saldoLibros.toSql(),
      'saldo_extracto': saldoExtracto.toSql(),
      'diferencia': diferencia.toSql(),
      'observacion': observacion,
      'estado': 'registrada',
    });

    await registrarEventoAuditoria(
      accion: 'CONCILIACION_BANCARIA',
      entidad: 'conciliaciones_bancarias',
      entidadId: id,
      detalle:
          'Cuenta: $cuentaNormalizada, libros: $saldoLibros, extracto: $saldoExtracto, diferencia: $diferencia',
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> obtenerConciliacionesBancarias() async {
    final db = await instance.database;
    return await db.query('conciliaciones_bancarias', orderBy: 'fecha DESC');
  }

  Future<int> guardarPresupuesto({
    required int anio,
    required int mes,
    required String categoria,
    required String tipo,
    required MoneyValue valorPresupuestado,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final valorReal = await _calcularValorRealPresupuesto(
      anio: anio,
      mes: mes,
      categoria: categoria,
      tipo: tipo,
    );
    final diferencia = tipo == 'ingreso'
        ? valorReal - valorPresupuestado
        : valorPresupuestado - valorReal;

    final datos = {
      'anio': anio,
      'mes': mes,
      'categoria': categoria.trim(),
      'tipo': tipo.trim().toLowerCase(),
      'valor_presupuestado': valorPresupuestado.toSql(),
      'valor_real': valorReal.toSql(),
      'diferencia': diferencia.toSql(),
      'observacion': observacion,
      'fecha': DateTime.now().toIso8601String(),
    };

    final id = await db.insert(
      'presupuestos',
      datos,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await registrarEventoAuditoria(
      accion: 'GUARDAR_PRESUPUESTO',
      entidad: 'presupuestos',
      entidadId: id,
      detalle:
          '$anio-$mes $tipo $categoria presupuesto: $valorPresupuestado real: $valorReal',
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> obtenerPresupuestos() async {
    final db = await instance.database;
    return await db.query(
      'presupuestos',
      orderBy: 'anio DESC, mes DESC, tipo ASC, categoria ASC',
    );
  }

  Future<void> recalcularPresupuestos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final presupuestos = await obtenerPresupuestos();
    for (final p in presupuestos) {
      final valorReal = await _calcularValorRealPresupuesto(
        anio: (p['anio'] as num).toInt(),
        mes: (p['mes'] as num).toInt(),
        categoria: p['categoria'].toString(),
        tipo: p['tipo'].toString(),
      );
      final valorPresupuestado = MoneyValue.fromSql(
        p['valor_presupuestado'],
        currency: currency,
      );
      final tipo = p['tipo'].toString();
      final diferencia = tipo == 'ingreso'
          ? valorReal - valorPresupuestado
          : valorPresupuestado - valorReal;

      await db.update(
        'presupuestos',
        {'valor_real': valorReal.toSql(), 'diferencia': diferencia.toSql()},
        where: 'id = ?',
        whereArgs: [p['id']],
      );
    }
  }

  Future<MoneyValue> _calcularValorRealPresupuesto({
    required int anio,
    required int mes,
    required String categoria,
    required String tipo,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final inicio = DateTime(anio, mes, 1).toIso8601String();
    final fin = DateTime(anio, mes + 1, 1).toIso8601String();
    final categoriaNormalizada = categoria.trim().toLowerCase();

    if (tipo.toLowerCase() == 'ingreso') {
      if (categoriaNormalizada.contains('venta')) {
        final res = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(total), 0) AS total
          FROM ventas
          WHERE company_id = ? AND fecha >= ? AND fecha < ?
          ''',
          [companyId, inicio, fin],
        );
        return MoneyValue.fromSql(res.first['total'], currency: currency);
      }

      final res = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(monto), 0) AS total
        FROM movimientos_caja
        WHERE company_id = ? AND fecha >= ? AND fecha < ? AND tipo = 'ingreso'
        ''',
        [companyId, inicio, fin],
      );
      return MoneyValue.fromSql(res.first['total'], currency: currency);
    }

    if (categoriaNormalizada.contains('compra') ||
        categoriaNormalizada.contains('inventario')) {
      final res = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(total), 0) AS total
        FROM compras
        WHERE company_id = ? AND fecha >= ? AND fecha < ? AND estado != 'anulada'
        ''',
        [companyId, inicio, fin],
      );
      return MoneyValue.fromSql(res.first['total'], currency: currency);
    }

    final res = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM movimientos_caja
      WHERE company_id = ? AND fecha >= ? AND fecha < ? AND tipo = 'egreso'
      ''',
      [companyId, inicio, fin],
    );
    return MoneyValue.fromSql(res.first['total'], currency: currency);
  }

  String _hashPin(String pin) => BCrypt.hashpw(pin, BCrypt.gensalt());

  bool _pinEsHash(String valor) =>
      valor.startsWith(r'$2a$') ||
      valor.startsWith(r'$2b$') ||
      valor.startsWith(r'$2y$');

  void _validarPinNuevo(String pin) {
    if (pin.length < 6) {
      throw ArgumentError('El PIN local debe tener al menos 6 caracteres.');
    }
  }

  Future<List<Map<String, dynamic>>> obtenerUsuarios() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    // Nunca exponer hashes de credenciales a la capa de presentación.
    return await db.query(
      'usuarios',
      columns: [
        'id',
        'company_id',
        'nombre',
        'usuario',
        'rol',
        'activo',
        'fecha',
      ],
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'activo DESC, nombre ASC',
    );
  }

  Future<int> guardarUsuario({
    required String nombre,
    required String usuario,
    required String rol,
    String pin = '',
    bool activo = true,
  }) async {
    if (rol.trim().toLowerCase() == 'sistema') {
      throw ArgumentError(
        'El rol "sistema" es reservado y no puede asignarse a usuarios.',
      );
    }
    _validarPinNuevo(pin);
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final id = await db.insert('usuarios', {
      'company_id': companyId,
      'nombre': nombre,
      'usuario': usuario,
      'rol': rol,
      'pin': _hashPin(pin),
      'activo': activo ? 1 : 0,
      'fecha': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    await registrarEventoAuditoria(
      accion: 'GUARDAR_USUARIO',
      entidad: 'usuarios',
      entidadId: id,
      detalle: '$usuario - $rol',
    );
    return id;
  }

  Future<void> actualizarUsuario({
    required int id,
    required String nombre,
    required String usuario,
    required String rol,
    String pin = '',
    bool activo = true,
  }) async {
    if (rol.trim().toLowerCase() == 'sistema') {
      throw ArgumentError(
        'El rol "sistema" es reservado y no puede asignarse a usuarios.',
      );
    }
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final values = <String, Object?>{
      'nombre': nombre,
      'usuario': usuario,
      'rol': rol,
      'activo': activo ? 1 : 0,
    };
    if (pin.isNotEmpty) {
      _validarPinNuevo(pin);
      values['pin'] = _hashPin(pin);
    }
    await db.update(
      'usuarios',
      values,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await registrarEventoAuditoria(
      accion: 'ACTUALIZAR_USUARIO',
      entidad: 'usuarios',
      entidadId: id,
      detalle: '$usuario - $rol',
    );
  }

  Future<void> eliminarUsuario(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await db.delete(
      'usuarios',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await registrarEventoAuditoria(
      accion: 'ELIMINAR_USUARIO',
      entidad: 'usuarios',
      entidadId: id,
      detalle: 'Usuario eliminado',
    );
  }

  Future<bool> usuarioRequierePinInicial(String usuario) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final res = await db.query(
      'usuarios',
      columns: ['pin'],
      where: 'company_id = ? AND LOWER(usuario) = ? AND activo = 1',
      whereArgs: [companyId, usuario.trim().toLowerCase()],
      limit: 1,
    );
    if (res.isEmpty) return false;
    return (res.first['pin']?.toString() ?? '').isEmpty;
  }

  Future<bool> configurarPinInicial({
    required String usuario,
    required String pin,
  }) async {
    _validarPinNuevo(pin);
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'usuarios',
        columns: ['id', 'pin'],
        where: 'company_id = ? AND LOWER(usuario) = ? AND activo = 1',
        whereArgs: [companyId, usuario.trim().toLowerCase()],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final actual = rows.first['pin']?.toString() ?? '';
      if (actual.isNotEmpty) return false;
      final changed = await txn.update(
        'usuarios',
        {'pin': _hashPin(pin)},
        where: 'id = ? AND company_id = ? AND (pin IS NULL OR pin = ?)',
        whereArgs: [rows.first['id'], companyId, ''],
      );
      return changed == 1;
    });
  }

  Future<Map<String, dynamic>?> validarUsuarioLocal({
    required String usuario,
    required String pin,
  }) async {
    if (pin.isEmpty) return null;
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final normalizedUser = usuario.trim().toLowerCase();
    final res = await db.query(
      'usuarios',
      where: 'company_id = ? AND LOWER(usuario) = ? AND activo = 1',
      whereArgs: [companyId, normalizedUser],
      limit: 1,
    );
    if (res.isEmpty) return null;

    final user = res.first;
    final userId = (user['id'] as num).toInt();
    final throttleKey = 'local_login_throttle_$userId';
    final throttleRows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [throttleKey],
      limit: 1,
    );
    var attempts = 0;
    DateTime? lockedUntil;
    if (throttleRows.isNotEmpty) {
      try {
        final raw = jsonDecode(throttleRows.first['valor']?.toString() ?? '{}');
        if (raw is Map) {
          attempts = (raw['attempts'] as num?)?.toInt() ?? 0;
          lockedUntil = DateTime.tryParse(
            raw['locked_until']?.toString() ?? '',
          );
        }
      } catch (_) {}
    }
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      await registrarEventoAuditoria(
        accion: 'LOGIN_LOCAL_BLOQUEADO',
        entidad: 'usuarios',
        entidadId: userId,
        detalle: 'Intento durante bloqueo temporal',
      );
      return null;
    }

    final pinGuardado = user['pin']?.toString() ?? '';
    if (pinGuardado.isEmpty) return null;

    var valid = false;
    if (_pinEsHash(pinGuardado)) {
      valid = BCrypt.checkpw(pin, pinGuardado);
    } else {
      // Migración transparente de instalaciones antiguas que almacenaban PIN
      // en texto plano. Solo se conserva si la credencial suministrada coincide.
      valid = pinGuardado == pin;
      if (valid) {
        await db.update(
          'usuarios',
          {'pin': _hashPin(pin)},
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
    }

    if (!valid) {
      attempts += 1;
      DateTime? nextLock;
      if (attempts >= 5) {
        // Bloqueo progresivo: 30s, 60s, 120s... hasta 30 minutos.
        var exponent = attempts - 5;
        if (exponent > 6) exponent = 6;
        var seconds = 30 * (1 << exponent);
        if (seconds > 1800) seconds = 1800;
        nextLock = DateTime.now().add(Duration(seconds: seconds));
      }
      await db.insert('app_config', {
        'clave': throttleKey,
        'valor': jsonEncode({
          'attempts': attempts,
          'locked_until': nextLock?.toIso8601String(),
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await registrarEventoAuditoria(
        accion: 'LOGIN_LOCAL_FALLIDO',
        entidad: 'usuarios',
        entidadId: userId,
        detalle: 'Intento fallido #$attempts',
      );
      return null;
    }

    await db.delete('app_config', where: 'clave = ?', whereArgs: [throttleKey]);
    await registrarEventoAuditoria(
      accion: 'LOGIN_LOCAL_EXITOSO',
      entidad: 'usuarios',
      entidadId: userId,
      detalle: normalizedUser,
    );
    return user;
  }

  Future<List<Map<String, dynamic>>> obtenerFacturasElectronicas() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'facturas_electronicas',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<int> crearFacturaElectronicaBorrador({
    required int ventaId,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final result = await db.transaction((txn) async {
      final ventas = await txn.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
        limit: 1,
      );
      if (ventas.isEmpty) {
        throw StateError('La venta no existe en la empresa activa.');
      }
      final secuencia = await txn.query(
        'secuencias_documentos',
        where: 'company_id = ? AND tipo = ?',
        whereArgs: [companyId, 'venta'],
        limit: 1,
      );
      final prefijo = secuencia.isEmpty
          ? 'FE'
          : secuencia.first['prefijo'].toString();
      final siguiente = secuencia.isEmpty
          ? 1
          : (secuencia.first['siguiente'] as num).toInt();
      if (secuencia.isEmpty) {
        await txn.insert('secuencias_documentos', {
          'company_id': companyId,
          'tipo': 'venta',
          'prefijo': prefijo,
          'siguiente': 2,
        });
      } else {
        await txn.update(
          'secuencias_documentos',
          {'siguiente': siguiente + 1},
          where: 'company_id = ? AND tipo = ?',
          whereArgs: [companyId, 'venta'],
        );
      }
      final consecutivo = '$prefijo-${siguiente.toString().padLeft(6, '0')}';
      final xml = _generarXmlFacturaElectronica(
        consecutivo,
        ventas.first,
        currency,
      );
      final id = await txn.insert('facturas_electronicas', {
        'company_id': companyId,
        'venta_id': ventaId,
        'prefijo': prefijo,
        'numero': siguiente,
        'consecutivo': consecutivo,
        'estado': 'borrador',
        'xml': xml,
        'fecha': DateTime.now().toIso8601String(),
        'observacion': observacion,
      });
      return (id: id, consecutivo: consecutivo);
    });

    await registrarEventoAuditoria(
      accion: 'CREAR_FACTURA_ELECTRONICA',
      entidad: 'facturas_electronicas',
      entidadId: result.id,
      detalle: 'Borrador ${result.consecutivo} para venta #$ventaId',
    );
    return result.id;
  }

  String _generarXmlFacturaElectronica(
    String consecutivo,
    Map<String, dynamic> venta,
    Currency currency,
  ) {
    final total = MoneyValue.fromSql(
      venta['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final impuesto = MoneyValue.fromSql(
      venta['impuesto_total'],
      currency: currency,
      nullableAsZero: true,
    );
    final cliente = venta['cliente']?.toString() ?? 'Cliente general';
    final subtotal = total - impuesto;
    return XmlInvoiceGenerator.generateInvoiceXml(
      invoiceData: {
        'invoice_number': consecutivo,
        'issue_date': DateTime.now().toIso8601String(),
        'profile_execution_id': '2',
        'currency': currency.code,
        'supplier': {'nit': '', 'name': 'Empresa local'},
        'customer': {'nit': '', 'name': cliente},
        'subtotal': subtotal.toMajorUnitsString(),
        'tax_exclusive': subtotal.toMajorUnitsString(),
        'total': total.toMajorUnitsString(),
        'tax_totals': [
          {
            'code': '01',
            'name': 'IVA',
            'taxable_amount': subtotal.toMajorUnitsString(),
            'amount': impuesto.toMajorUnitsString(),
            'percent': '0.00',
          },
        ],
        'lines': [
          {
            'id': 1,
            'quantity': venta['cantidad']?.toString() ?? '1',
            'unit_code': 'NIU',
            'unit_price': total.toMajorUnitsString(),
            'total': subtotal.toMajorUnitsString(),
            'description': venta['producto']?.toString() ?? 'Venta POS',
            'taxes': [
              {
                'code': '01',
                'name': 'IVA',
                'taxable_amount': subtotal.toMajorUnitsString(),
                'amount': impuesto.toMajorUnitsString(),
                'percent': venta['impuesto_pct']?.toString() ?? '0.00',
              },
            ],
          },
        ],
      },
    );
  }

  Future<int> actualizarEstadoFacturaElectronica({
    required int id,
    required String estado,
    String cufe = '',
    String respuestaDian = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.update(
      'facturas_electronicas',
      {
        'estado': estado,
        'cufe': cufe,
        'respuesta_dian': respuestaDian,
        'validada': estado == 'validada'
            ? DateTime.now().toIso8601String()
            : null,
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerEmpleados() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'empleados',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'activo DESC, nombre ASC',
    );
  }

  Future<int> guardarEmpleado({
    required String nombre,
    required MoneyValue salarioBase,
    String documento = '',
    String tipoDocumento = 'CC',
    String cargo = '',
    int auxilioTransporte = 0,
    String cuentaBancaria = '',
    String codigoBanco = '',
    String nombreBanco = '',
    String nivelArl = 'I',
    String fondoPension = '',
    String eps = '',
    String tipoContrato = 'indefinido',
    String frecuenciaPago = 'mensual',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.insert('empleados', {
      'company_id': companyId,
      'nombre': nombre,
      'documento': documento,
      'tipo_documento': tipoDocumento,
      'cargo': cargo,
      'salario_base': salarioBase.toSql(),
      'auxilio_transporte': auxilioTransporte,
      'cuenta_bancaria': cuentaBancaria,
      'codigo_banco': codigoBanco,
      'nombre_banco': nombreBanco,
      'nivel_arl': nivelArl,
      'fondo_pension': fondoPension,
      'eps': eps,
      'tipo_contrato': tipoContrato,
      'frecuencia_pago': frecuenciaPago,
      'activo': 1,
      'fecha_contratacion': DateTime.now().toIso8601String(),
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  Future<int> actualizarEmpleado({
    required int id,
    required String nombre,
    required MoneyValue salarioBase,
    required String documento,
    String tipoDocumento = 'CC',
    required String cargo,
    required int auxilioTransporte,
    String cuentaBancaria = '',
    String codigoBanco = '',
    String nombreBanco = '',
    String nivelArl = 'I',
    String fondoPension = '',
    String eps = '',
    String tipoContrato = 'indefinido',
    String frecuenciaPago = 'mensual',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.update(
      'empleados',
      {
        'nombre': nombre,
        'documento': documento,
        'tipo_documento': tipoDocumento,
        'cargo': cargo,
        'salario_base': salarioBase.toSql(),
        'auxilio_transporte': auxilioTransporte,
        'cuenta_bancaria': cuentaBancaria,
        'codigo_banco': codigoBanco,
        'nombre_banco': nombreBanco,
        'nivel_arl': nivelArl,
        'fondo_pension': fondoPension,
        'eps': eps,
        'tipo_contrato': tipoContrato,
        'frecuencia_pago': frecuenciaPago,
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<int> liquidarNomina({
    required int empleadoId,
    required int anio,
    required int mes,
    MoneyValue? horasExtra,
    MoneyValue? bonificaciones,
    MoneyValue? otrasDeducciones,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final otrasDeduccionesValue = otrasDeducciones ?? zero;

    // Obtener parámetros de nómina del año
    final params = await db.query(
      'payroll_parameters',
      where: 'year = ? AND (company_id = ? OR company_id IS NULL)',
      whereArgs: [anio, companyId],
      limit: 1,
    );

    if (params.isEmpty) {
      throw Exception(
        'No hay parámetros de nómina configurados para el año $anio',
      );
    }

    final param = params.first;
    final smmlv = MoneyValue.fromSql(param['smmlv'], currency: currency);
    final healthEmployeeRate = (param['health_employee_rate'] as num)
        .toDouble();
    final healthEmployerRate = (param['health_employer_rate'] as num)
        .toDouble();
    final pensionEmployeeRate = (param['pension_employee_rate'] as num)
        .toDouble();
    final pensionEmployerRate = (param['pension_employer_rate'] as num)
        .toDouble();
    final fspTrigger = (param['fsp_trigger_smmlv'] as num).toDouble();
    final arlLevel1 = (param['arl_level_1_rate'] as num).toDouble();
    final arlLevel2 = (param['arl_level_2_rate'] as num).toDouble();
    final arlLevel3 = (param['arl_level_3_rate'] as num).toDouble();
    final arlLevel4 = (param['arl_level_4_rate'] as num).toDouble();
    final arlLevel5 = (param['arl_level_5_rate'] as num).toDouble();
    final senaRate = (param['parafiscal_sena_rate'] as num).toDouble();
    final icbfRate = (param['parafiscal_icbf_rate'] as num).toDouble();
    final cajaRate = (param['parafiscal_caja_rate'] as num).toDouble();
    final severanceRate = (param['severance_rate'] as num).toDouble();
    final serviceBonusRate = (param['service_bonus_rate'] as num).toDouble();
    final vacationRate = (param['vacation_rate'] as num).toDouble();

    final empleados = await db.query(
      'empleados',
      where: 'id = ? AND company_id = ?',
      whereArgs: [empleadoId, companyId],
    );
    if (empleados.isEmpty) throw Exception('Empleado no encontrado');

    final empleado = empleados.first;
    final salario = MoneyValue.fromSql(
      empleado['salario_base'],
      currency: currency,
    );
    final periodStart = DateTime(anio, mes, 1);
    final periodEnd = DateTime(anio, mes + 1, 1);
    final absenceSummary = await HrmPayrollAbsenceService.forPeriod(
      db: db,
      companyId: companyId,
      from: periodStart,
      to: periodEnd,
      employeeId: empleadoId,
    );
    final absenceImpact = absenceSummary.payrollImpact(
      monthlySalary: salario,
      periodDays: 30,
    );
    final periodo = '$anio-${mes.toString().padLeft(2, '0')}';
    final noveltyRows = await db.query(
      'payroll_novelties',
      where: 'company_id = ? AND empleado_id = ? AND periodo = ?',
      whereArgs: [companyId, empleadoId, periodo],
    );
    MoneyValue sumNovelties(Set<String> types) {
      return noveltyRows
          .where((row) => types.contains(row['tipo_novedad']?.toString()))
          .map(
            (row) => MoneyValue.fromSql(
              row['valor'],
              currency: currency,
              nullableAsZero: true,
            ),
          )
          .fold(zero, (sum, value) => sum + value);
    }

    final noveltyHours = sumNovelties({'horas_extra', 'horas_extra_salarial'});
    final noveltyBonuses = sumNovelties({
      'bonificacion',
      'bonificacion_salarial',
      'comision',
      'comision_salarial',
    });
    final horasExtraValue = (horasExtra ?? zero) + noveltyHours;
    final bonificacionesValue = (bonificaciones ?? zero) + noveltyBonuses;
    final salarioDevengado = absenceImpact.totalIncome;
    final auxilioFlag = (empleado['auxilio_transporte'] as int) == 1;
    final nivelArl = empleado['nivel_arl']?.toString() ?? 'I';

    // Calcular auxilio de transporte si aplica
    var auxilio = auxilioFlag && salario < (smmlv * 2)
        ? MoneyValue.fromSql(
            param['transportation_allowance'],
            currency: currency,
          )
        : zero;
    if (absenceImpact.transportEligibleDays < 30 && auxilio.minorUnits > 0) {
      auxilio = auxilio.multiplyRatio(
        numerator: (absenceImpact.transportEligibleDays * 1000).round(),
        denominator: 30000,
      );
    }

    // Cálculos de aportes del empleado
    final baseIbc = salarioDevengado + horasExtraValue + bonificacionesValue;
    final saludEmpleado = baseIbc.multiplyDecimal(
      healthEmployeeRate.toString(),
    );
    final pensionEmpleado = baseIbc.multiplyDecimal(
      pensionEmployeeRate.toString(),
    );

    // Cálculo de FSP (Fondo de Solidaridad Pensional)
    final baseFsp = baseIbc;
    var fsp = zero;
    if (baseFsp > smmlv.multiplyDecimal(fspTrigger.toString())) {
      if (baseFsp > smmlv * 4 && baseFsp <= smmlv * 6) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_1'] as num).toString());
      } else if (baseFsp > smmlv * 6 && baseFsp <= smmlv * 8) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_2'] as num).toString());
      } else if (baseFsp > smmlv * 8 && baseFsp <= smmlv * 10) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_3'] as num).toString());
      } else if (baseFsp > smmlv * 10 && baseFsp <= smmlv * 12) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_4'] as num).toString());
      } else if (baseFsp > smmlv * 12 && baseFsp <= smmlv * 14) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_5'] as num).toString());
      } else if (baseFsp > smmlv * 14) {
        fsp = baseFsp.multiplyDecimal((param['fsp_rate_6'] as num).toString());
      }
    }

    // Cálculos de aportes del empleador
    final healthExonerated = (param['health_exonerated'] as num?)?.toInt() == 1;
    final saludEmpleador = healthExonerated
        ? zero
        : baseIbc.multiplyDecimal(healthEmployerRate.toString());
    final pensionEmpleador = baseIbc.multiplyDecimal(
      pensionEmployerRate.toString(),
    );

    // ARL según nivel
    var arl = zero;
    switch (nivelArl.toUpperCase()) {
      case 'I':
        arl = baseIbc.multiplyDecimal(arlLevel1.toString());
        break;
      case 'II':
        arl = baseIbc.multiplyDecimal(arlLevel2.toString());
        break;
      case 'III':
        arl = baseIbc.multiplyDecimal(arlLevel3.toString());
        break;
      case 'IV':
        arl = baseIbc.multiplyDecimal(arlLevel4.toString());
        break;
      case 'V':
        arl = baseIbc.multiplyDecimal(arlLevel5.toString());
        break;
    }

    // Parafiscales
    final parafiscalSena = healthExonerated
        ? zero
        : baseIbc.multiplyDecimal(senaRate.toString());
    final parafiscalIcbf = healthExonerated
        ? zero
        : baseIbc.multiplyDecimal(icbfRate.toString());
    final parafiscalCaja = baseIbc.multiplyDecimal(cajaRate.toString());

    // Provisiones mensuales
    final cesantias = salarioDevengado.multiplyDecimal(
      severanceRate.toString(),
    );
    final primaServicios = salarioDevengado.multiplyDecimal(
      serviceBonusRate.toString(),
    );
    // Ley 52 de 1975: 12 % anual sobre el saldo de cesantias. El valor
    // historico 0.01 era mensual y aqui se aplicaba una sola vez.
    final interesesCesantias = cesantias.percent('12');
    final vacaciones = salarioDevengado.multiplyDecimal(
      vacationRate.toString(),
    );

    // Total aportes empleador
    final parafiscales = parafiscalSena + parafiscalIcbf + parafiscalCaja;
    final provisiones =
        cesantias + primaServicios + interesesCesantias + vacaciones;
    final aportesEmpleador =
        saludEmpleador + pensionEmpleador + arl + parafiscales + provisiones;

    // Totales
    final totalDevengado =
        salarioDevengado + auxilio + horasExtraValue + bonificacionesValue;
    final taxableBase = baseIbc - saludEmpleado - pensionEmpleado;
    final retefuenteValue = PayrollWithholding.calculate(
      taxableBase: taxableBase,
      uvt: MoneyValue.fromSql(param['uvt'], currency: currency),
      zero: zero,
    );
    final mandatoryDeductions =
        saludEmpleado + pensionEmpleado + fsp + retefuenteValue;
    final additionalDeductions = const PayrollDeductionService().apply(
      noveltyRows: noveltyRows,
      manualOtherDeductions: otrasDeduccionesValue,
      grossIncome: totalDevengado,
      mandatoryDeductions: mandatoryDeductions,
      smmlv: smmlv,
      zero: zero,
    );
    final totalDeducciones = mandatoryDeductions + additionalDeductions.total;
    final netoPagar = totalDevengado - totalDeducciones;
    final payrollWarnings = [
      if (absenceSummary.warning != null) absenceSummary.warning!,
      if (additionalDeductions.warning != null) additionalDeductions.warning!,
    ];
    final payrollWarningText = payrollWarnings.isEmpty
        ? null
        : payrollWarnings.join(' | ');

    final metodoPago = empleado['metodo_pago']?.toString() ?? 'Efectivo';

    final esBanco = metodoPago.toUpperCase() != 'EFECTIVO';
    final origenCaja = esBanco ? 'banco' : 'caja';
    final cuentaDinero = esBanco ? '111005' : '110505';

    final fechaLiquidacion = DateTime(
      anio,
      mes,
      DateTime(anio, mes + 1, 0).day,
    );
    final id = await db.transaction((txn) async {
      final movimientoCajaId = await txn.insert('movimientos_caja', {
        'company_id': companyId,
        'tipo': 'egreso',
        'concepto': 'Nómina $mes/$anio - ${empleado['nombre']}',
        'monto': netoPagar.toSql(),
        'fecha': DateTime.now().toIso8601String(),
        'origen': origenCaja,
      });

      final asientoId = await _registrarAsientoConCodigos(
        txn: txn,
        concepto: 'Liquidación Nómina $mes/$anio - ${empleado['nombre']}',
        referencia: 'NOM-$empleadoId',
        origen: 'nomina',
        lineas: [
          {
            'codigo': '510506',
            'debito': salarioDevengado.toSql(),
            'credito': 0,
            'descripcion': 'Gasto Sueldo: ${empleado['nombre']}',
          },
          if (auxilio.minorUnits > 0)
            {
              'codigo': '510527',
              'debito': auxilio.toSql(),
              'credito': 0,
              'descripcion': 'Auxilio transporte: ${empleado['nombre']}',
            },
          if (horasExtraValue.minorUnits > 0)
            {
              'codigo': '510515',
              'debito': horasExtraValue.toSql(),
              'credito': 0,
              'descripcion': 'Horas extras: ${empleado['nombre']}',
            },
          if (bonificacionesValue.minorUnits > 0)
            {
              'codigo': '510548',
              'debito': bonificacionesValue.toSql(),
              'credito': 0,
              'descripcion': 'Bonificaciones: ${empleado['nombre']}',
            },
          {
            'codigo': '237005',
            'debito': 0,
            'credito': saludEmpleado.toSql(),
            'descripcion':
                'Retención Salud ${healthEmployeeRate * 100}%: ${empleado['nombre']}',
          },
          {
            'codigo': '238030',
            'debito': 0,
            'credito': pensionEmpleado.toSql(),
            'descripcion':
                'Retención Pensión ${pensionEmployeeRate * 100}%: ${empleado['nombre']}',
          },
          if (fsp.minorUnits > 0)
            {
              'codigo': '238035',
              'debito': 0,
              'credito': fsp.toSql(),
              'descripcion': 'FSP: ${empleado['nombre']}',
            },
          if (additionalDeductions.total.minorUnits > 0)
            {
              'codigo': '237095',
              'debito': 0,
              'credito': additionalDeductions.total.toSql(),
              'descripcion':
                  'Deducciones laborales adicionales: ${empleado['nombre']}',
            },
          if (saludEmpleador.minorUnits > 0)
            {
              'codigo': '510570',
              'debito': saludEmpleador.toSql(),
              'credito': 0,
              'descripcion': 'Salud empleador: ${empleado['nombre']}',
            },
          if (pensionEmpleador.minorUnits > 0)
            {
              'codigo': '510571',
              'debito': pensionEmpleador.toSql(),
              'credito': 0,
              'descripcion': 'Pension empleador: ${empleado['nombre']}',
            },
          if (arl.minorUnits > 0)
            {
              'codigo': '510572',
              'debito': arl.toSql(),
              'credito': 0,
              'descripcion': 'ARL empleador: ${empleado['nombre']}',
            },
          if (parafiscales.minorUnits > 0)
            {
              'codigo': '510573',
              'debito': parafiscales.toSql(),
              'credito': 0,
              'descripcion': 'Parafiscales empleador: ${empleado['nombre']}',
            },
          if (provisiones.minorUnits > 0)
            {
              'codigo': '510574',
              'debito': provisiones.toSql(),
              'credito': 0,
              'descripcion': 'Provisiones laborales: ${empleado['nombre']}',
            },
          if (saludEmpleador.minorUnits > 0)
            {
              'codigo': '237005',
              'debito': 0,
              'credito': saludEmpleador.toSql(),
              'descripcion': 'Salud empleador por pagar: ${empleado['nombre']}',
            },
          if (pensionEmpleador.minorUnits > 0)
            {
              'codigo': '238030',
              'debito': 0,
              'credito': pensionEmpleador.toSql(),
              'descripcion':
                  'Pension empleador por pagar: ${empleado['nombre']}',
            },
          if (arl.minorUnits > 0)
            {
              'codigo': '237010',
              'debito': 0,
              'credito': arl.toSql(),
              'descripcion': 'ARL por pagar: ${empleado['nombre']}',
            },
          if (parafiscales.minorUnits > 0)
            {
              'codigo': '237095',
              'debito': 0,
              'credito': parafiscales.toSql(),
              'descripcion': 'Parafiscales por pagar: ${empleado['nombre']}',
            },
          if (cesantias.minorUnits > 0)
            {
              'codigo': '2510',
              'debito': 0,
              'credito': cesantias.toSql(),
              'descripcion': 'Cesantias por pagar: ${empleado['nombre']}',
            },
          if (primaServicios.minorUnits > 0)
            {
              'codigo': '2520',
              'debito': 0,
              'credito': primaServicios.toSql(),
              'descripcion': 'Prima por pagar: ${empleado['nombre']}',
            },
          if (interesesCesantias.minorUnits > 0)
            {
              'codigo': '2515',
              'debito': 0,
              'credito': interesesCesantias.toSql(),
              'descripcion':
                  'Intereses de cesantias por pagar: ${empleado['nombre']}',
            },
          if (vacaciones.minorUnits > 0)
            {
              'codigo': '2525',
              'debito': 0,
              'credito': vacaciones.toSql(),
              'descripcion': 'Vacaciones por pagar: ${empleado['nombre']}',
            },
          if (retefuenteValue.minorUnits > 0)
            {
              'codigo': '236505',
              'debito': 0,
              'credito': retefuenteValue.toSql(),
              'descripcion':
                  'Retencion laboral por pagar: ${empleado['nombre']}',
            },
          {
            'codigo': cuentaDinero,
            'debito': 0,
            'credito': netoPagar.toSql(),
            'descripcion': 'Pago neto nómina: ${empleado['nombre']}',
          },
        ],
        fecha: fechaLiquidacion,
      );

      final calculoJson = {
        'salario_base': salario.toWireMap(),
        'salario_devengado': salarioDevengado.toWireMap(),
        'auxilio_transporte': auxilio.toWireMap(),
        'horas_extra': horasExtraValue.toWireMap(),
        'bonificaciones': bonificacionesValue.toWireMap(),
        'otras_deducciones_solicitadas': otrasDeduccionesValue.toWireMap(),
        'deducciones_laborales_adicionales': additionalDeductions.toMap(),
        'salud_empleado': saludEmpleado.toWireMap(),
        'salud_empleador': saludEmpleador.toWireMap(),
        'pension_empleado': pensionEmpleado.toWireMap(),
        'pension_empleador': pensionEmpleador.toWireMap(),
        'fsp': fsp.toWireMap(),
        'arl': arl.toWireMap(),
        'parafiscal_sena': parafiscalSena.toWireMap(),
        'parafiscal_icbf': parafiscalIcbf.toWireMap(),
        'parafiscal_caja': parafiscalCaja.toWireMap(),
        'cesantias': cesantias.toWireMap(),
        'prima_servicios': primaServicios.toWireMap(),
        'intereses_cesantias': interesesCesantias.toWireMap(),
        'vacaciones': vacaciones.toWireMap(),
        'retefuente': retefuenteValue.toWireMap(),
        'hrm_ausencias': absenceSummary.toMap(),
        'hrm_impacto_nomina': absenceImpact.toMap(),
      };

      final liquidationId = await txn.insert('nomina_liquidaciones', {
        'company_id': companyId,
        'empleado_id': empleadoId,
        'empleado': empleado['nombre'],
        'periodo': periodo,
        'salario_base': salario.toSql(),
        'total_devengado': totalDevengado.toSql(),
        'total_deducciones': totalDeducciones.toSql(),
        'neto_pagar': netoPagar.toSql(),
        'aportes_empleador': aportesEmpleador.toSql(),
        'salud_empleado': saludEmpleado.toSql(),
        'salud_empleador': saludEmpleador.toSql(),
        'pension_empleado': pensionEmpleado.toSql(),
        'pension_empleador': pensionEmpleador.toSql(),
        'fsp': fsp.toSql(),
        'arl': arl.toSql(),
        'parafiscal_sena': parafiscalSena.toSql(),
        'parafiscal_icbf': parafiscalIcbf.toSql(),
        'parafiscal_caja': parafiscalCaja.toSql(),
        'cesantias': cesantias.toSql(),
        'prima_servicios': primaServicios.toSql(),
        'intereses_cesantias': interesesCesantias.toSql(),
        'vacaciones': vacaciones.toSql(),
        'retefuente': retefuenteValue.toSql(),
        'movimiento_caja_id': movimientoCajaId,
        'asiento_id': asientoId,
        'estado': 'liquidada',
        'calculo_json': calculoJson.toString(),
        'novedades_hrm': payrollWarningText,
        'fecha': DateTime.now().toIso8601String(),
      });

      return liquidationId;
    });

    await registrarEventoAuditoria(
      accion: 'LIQUIDAR_NOMINA',
      entidad: 'nomina_liquidaciones',
      entidadId: id,
      detalle:
          '${empleado['nombre']} $periodo neto $netoPagar'
          '${payrollWarningText == null ? '' : ' - $payrollWarningText'}',
    );
    return id;
  }

  Future<void> anularLiquidacionNomina(int id) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final liquidaciones = await db.query(
      'nomina_liquidaciones',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (liquidaciones.isEmpty) return;
    final liq = liquidaciones.first;

    await db.update(
      'nomina_liquidaciones',
      {'estado': 'anulada'},
      where: 'id = ?',
      whereArgs: [id],
    );

    final movId = liq['movimiento_caja_id'] as int?;
    if (movId != null) {
      await db.update(
        'movimientos_caja',
        {'activo': 0},
        where: 'id = ? AND company_id = ?',
        whereArgs: [movId, companyId],
      );
    }

    final asientoId = liq['asiento_id'] as int?;
    if (asientoId != null) {
      final lineas = await db.query(
        'asiento_lineas',
        where: 'asiento_id = ?',
        whereArgs: [asientoId],
      );
      final lineasReversion = lineas
          .map(
            (l) => {
              'codigo': l['codigo'].toString(),
              'debito': l['credito'] as int,
              'credito': l['debito'] as int,
              'descripcion': 'Reversión: ${l['descripcion']}',
            },
          )
          .toList();

      await _registrarAsientoConCodigos(
        concepto: 'Reversión liquidación nómina #${liq['id']}',
        referencia: 'REV-NOM-${liq['id']}',
        origen: 'nomina_reversion',
        lineas: lineasReversion,
      );
    }

    await registrarEventoAuditoria(
      accion: 'ANULAR_NOMINA',
      entidad: 'nomina_liquidaciones',
      entidadId: id,
      detalle: 'Anulación liquidación nómina #$id',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerNomina() async {
    final db = await instance.database;
    return await db.query(
      'nomina_liquidaciones',
      orderBy: 'periodo DESC, id DESC',
    );
  }

  Future<int> guardarActivoFijo({
    required String nombre,
    required double costo,
    required int vidaUtilMeses,
    String categoria = '',
    String observacion = '',
    String tipoDepreciacion = 'maquinaria',
    String codigoPuc = '1524',
    String codigoPucDepreciacion = '5160',
  }) async {
    final db = await instance.database;
    return await db.insert('activos_fijos', {
      'nombre': nombre,
      'categoria': categoria,
      'costo': costo,
      'fecha_compra': DateTime.now().toIso8601String(),
      'vida_util_meses': vidaUtilMeses,
      'depreciacion_acumulada': 0,
      'valor_libros': costo,
      'estado': 'activo',
      'observacion': observacion,
      'tipo_depreciacion': tipoDepreciacion,
      'codigo_puc': codigoPuc,
      'codigo_puc_depreciacion': codigoPucDepreciacion,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerActivosFijos() async {
    final db = await instance.database;
    final activos = await db.query(
      'activos_fijos',
      orderBy: 'fecha_compra DESC',
    );
    return activos.map((a) {
      final costo = (a['costo'] as num).toDouble();
      final vida = (a['vida_util_meses'] as num).toInt();
      final fecha =
          DateTime.tryParse(a['fecha_compra'].toString()) ?? DateTime.now();
      final meses =
          (DateTime.now().year - fecha.year) * 12 +
          DateTime.now().month -
          fecha.month;
      final depMensual = vida <= 0 ? 0 : costo / vida;
      final depAcumulada = (depMensual * meses).clamp(0, costo).toDouble();
      return {
        ...a,
        'depreciacion_acumulada_calc': depAcumulada,
        'valor_libros_calc': costo - depAcumulada,
        'depreciacion_mensual': depMensual,
      };
    }).toList();
  }

  Future<int> importarMovimientoExtracto({
    required String cuenta,
    required String fecha,
    required String descripcion,
    required MoneyValue valor,
    String referencia = '',
  }) async {
    final db = await instance.database;
    return await db.insert('extractos_bancarios', {
      'cuenta': cuenta,
      'fecha': fecha,
      'descripcion': descripcion,
      'valor': valor.abs().toSql(),
      'tipo': valor.minorUnits >= 0 ? 'ingreso' : 'egreso',
      'conciliado': 0,
      'referencia': referencia,
      'creado': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> obtenerExtractosBancarios() async {
    final db = await instance.database;
    return await db.query('extractos_bancarios', orderBy: 'fecha DESC');
  }

  Future<int> guardarAdjunto({
    required String entidad,
    required String nombre,
    required String ruta,
    int? entidadId,
    String notas = '',
  }) async {
    final db = await instance.database;
    return await db.insert('adjuntos_documentos', {
      'entidad': entidad,
      'entidad_id': entidadId,
      'nombre': nombre,
      'ruta': ruta,
      'notas': notas,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> obtenerAdjuntos() async {
    final db = await instance.database;
    return await db.query('adjuntos_documentos', orderBy: 'fecha DESC');
  }

  Future<Map<String, MoneyValue>> obtenerReporteFiscal({
    required int anio,
    required int mes,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final inicio = DateTime(anio, mes, 1).toIso8601String();
    final fin = DateTime(anio, mes + 1, 1).toIso8601String();

    Future<MoneyValue> total(String sql) async {
      final res = await db.rawQuery(sql, [companyId, inicio, fin]);
      return MoneyValue.fromSql(
        res.first['total'],
        currency: currency,
        nullableAsZero: true,
      );
    }

    final ventas = await total(
      "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, 'emitida') != 'anulada'",
    );
    final compras = await total(
      "SELECT COALESCE(SUM(total), 0) AS total FROM compras WHERE company_id = ? AND fecha >= ? AND fecha < ? AND estado != 'anulada'",
    );
    final ivaGenerado = await total(
      "SELECT COALESCE(SUM(impuesto_total), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, 'emitida') != 'anulada'",
    );
    final ivaDescontable = await total(
      "SELECT COALESCE(SUM(impuesto_total), 0) AS total FROM compras WHERE company_id = ? AND fecha >= ? AND fecha < ? AND estado != 'anulada'",
    );
    final nomina = await total(
      "SELECT COALESCE(SUM(neto_pagar), 0) AS total FROM nomina_liquidaciones WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, 'activo') != 'anulado'",
    );
    final retefuenteVentas = await total(
      'SELECT COALESCE(SUM(retefuente), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, \'emitida\') != \'anulada\'',
    );
    final reteivaVentas = await total(
      'SELECT COALESCE(SUM(reteiva), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, \'emitida\') != \'anulada\'',
    );
    final reteicaVentas = await total(
      'SELECT COALESCE(SUM(reteica), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, \'emitida\') != \'anulada\'',
    );
    final retefuenteCompras = await total(
      'SELECT COALESCE(SUM(retefuente), 0) AS total FROM compras WHERE company_id = ? AND fecha >= ? AND fecha < ? AND estado != \'anulada\'',
    );

    return {
      'ventas': ventas,
      'compras': compras,
      'iva_generado': ivaGenerado,
      'iva_descontable': ivaDescontable,
      'iva_por_pagar': ivaGenerado - ivaDescontable,
      'nomina': nomina,
      'retefuente_practicada': retefuenteVentas,
      'reteiva_practicada': reteivaVentas,
      'reteica_practicada': reteicaVentas,
      'retefuente_recibida': retefuenteCompras,
    };
  }

  Future<int> registrarEventoAuditoria({
    required String accion,
    required String entidad,
    int? entidadId,
    String detalle = '',
    String? oldValues,
    String? newValues,
    String? ipAddress,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    String? deviceId;
    try {
      deviceId = await HardwareFingerprintService().generateFingerprint();
    } catch (_) {
      // La auditoría de negocio no debe fallar porque el SO no exponga datos
      // de dispositivo. En ese caso el evento conserva el resto de identidad.
    }
    return await db.insert('auditoria_eventos', {
      'company_id': companyId,
      'fecha': DateTime.now().toIso8601String(),
      'accion': accion,
      'entidad': entidad,
      'entidad_id': entidadId,
      'detalle': detalle,
      'usuario': AuditIdentity.current,
      'old_values': oldValues,
      'new_values': newValues,
      'ip_address': ipAddress,
      'device_id': deviceId,
    });
  }

  /// Verifica si la licencia está suspendida y bloquea operaciones si es necesario
  Future<bool> licenciaEstaSuspendida() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    final tenants = await db.query(
      'tenants',
      where: 'id = ?',
      whereArgs: [companyId],
      limit: 1,
    );

    if (tenants.isEmpty) return false;

    final status = tenants.first['license_status']?.toString() ?? 'active';
    return status == 'suspended';
  }

  /// Actualiza el estado de la licencia (webhook de pasarela de pagos)
  Future<void> actualizarEstadoLicencia(
    int tenantId,
    String nuevoEstado,
  ) async {
    final db = await instance.database;

    await db.update(
      'tenants',
      {'license_status': nuevoEstado},
      where: 'id = ?',
      whereArgs: [tenantId],
    );

    if (nuevoEstado == 'suspended') {
      await cambiarBloqueoOperativo(true);
      await registrarEventoAuditoria(
        accion: 'LICENCIA_SUSPENDIDA',
        entidad: 'tenants',
        entidadId: tenantId,
        detalle: 'Licencia suspendida por falta de pago',
      );
    } else if (nuevoEstado == 'active') {
      await cambiarBloqueoOperativo(false);
      await registrarEventoAuditoria(
        accion: 'LICENCIA_ACTIVADA',
        entidad: 'tenants',
        entidadId: tenantId,
        detalle: 'Licencia reactivada',
      );
    }
  }

  /// Verifica si las operaciones están bloqueadas por licencia suspendida
  Future<bool> operacionBloqueadaPorLicencia() async {
    return await licenciaEstaSuspendida();
  }

  /// Conciliación Bancaria Automática
  /// Compara extracto bancario (importado) con payments_received
  /// Emparejamiento exacto si date y amount_paid coinciden
  Future<Map<String, dynamic>> conciliarBancosAutomaticamente() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    // Obtener extractos bancarios no conciliados
    final extractos = await db.query(
      'extractos_bancarios',
      where: 'company_id = ? AND conciliado = 0',
      whereArgs: [companyId],
    );

    // Obtener abonos CxC no conciliados
    final abonos = await db.query(
      'abonos_cxc',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );

    int conciliados = 0;
    int noConciliados = 0;
    var totalConciliado = MoneyValue(minorUnits: 0, currency: currency);

    for (final extracto in extractos) {
      final extractoFecha = extracto['fecha']?.toString() ?? '';
      final extractoValor = MoneyValue.fromSql(
        extracto['valor'],
        currency: currency,
      );
      final extractoTipo = extracto['tipo']?.toString() ?? '';

      // Solo conciliar ingresos (abonos)
      if (extractoTipo.toLowerCase() != 'ingreso') continue;

      bool encontrado = false;

      for (final abono in abonos) {
        final abonoFecha = abono['fecha']?.toString() ?? '';
        final abonoMonto = MoneyValue.fromSql(
          abono['monto'],
          currency: currency,
        );

        // Emparejamiento exacto: fecha y monto
        if (abonoFecha == extractoFecha && abonoMonto == extractoValor) {
          // Conciliar
          await db.update(
            'extractos_bancarios',
            {'conciliado': 1, 'asiento_linea_id': abono['id']},
            where: 'id = ?',
            whereArgs: [extracto['id']],
          );

          await db.update(
            'abonos_cxc',
            {'conciliado': 1},
            where: 'id = ?',
            whereArgs: [abono['id']],
          );

          conciliados++;
          totalConciliado = totalConciliado + extractoValor;
          encontrado = true;
          break;
        }
      }

      if (!encontrado) {
        noConciliados++;
      }
    }

    await registrarEventoAuditoria(
      accion: 'CONCILIACION_BANCARIA_AUTOMATICA',
      entidad: 'extractos_bancarios',
      detalle:
          'Conciliados: $conciliados, No conciliados: $noConciliados, Total: $totalConciliado',
    );

    return {
      'conciliados': conciliados,
      'no_conciliados': noConciliados,
      'total_conciliado': totalConciliado.toWireMap(),
    };
  }

  /// Actualiza el estado de comisiones por recaudo (anti-fraude)
  /// Solo cambia status a "Pagada" cuando la factura tiene balance_due = 0
  Future<void> actualizarComisionesPorRecaudo(int ventaId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    // Verificar si la factura está totalmente pagada
    final cuentas = await db.query(
      'cuentas_por_cobrar',
      where: 'venta_id = ? AND company_id = ?',
      whereArgs: [ventaId, companyId],
    );

    bool facturaPagada = true;
    for (final cuenta in cuentas) {
      final saldo = MoneyValue.fromSql(
        cuenta['saldo'],
        currency: currency,
        nullableAsZero: true,
      );
      if (saldo.minorUnits > 0) {
        facturaPagada = false;
        break;
      }
    }

    if (facturaPagada) {
      // Actualizar comisiones de recaudo a "Pagada"
      await db.update(
        'comisiones_liquidadas',
        {'status': 'Pagada'},
        where:
            'venta_id = ? AND company_id = ? AND commission_type = ? AND status = ?',
        whereArgs: [ventaId, companyId, 'Recaudo', 'Pendiente'],
      );

      await registrarEventoAuditoria(
        accion: 'ACTUALIZAR_COMISIONES_RECAUDO',
        entidad: 'comisiones_liquidadas',
        entidadId: ventaId,
        detalle:
            'Comisiones de recaudo actualizadas a Pagada por factura totalmente pagada',
      );
    }
  }

  /// Registra una garantía con validación de tiempo de garantía
  Future<int> registrarGarantia({
    required int ventaId,
    required int productoId,
    String? numeroSerie,
    required String descripcionProblema,
    required int diasGarantia,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    // Validar que la venta existe
    final ventas = await db.query(
      'ventas',
      where: 'id = ? AND company_id = ?',
      whereArgs: [ventaId, companyId],
      limit: 1,
    );

    if (ventas.isEmpty) {
      throw Exception('La venta #$ventaId no existe');
    }

    final venta = ventas.first;
    final ventaFecha = DateTime.parse(venta['fecha'] as String);
    final hoy = DateTime.now();
    final diasDesdeVenta = hoy.difference(ventaFecha).inDays;

    // Validar que no supere el tiempo de garantía
    if (diasDesdeVenta > diasGarantia) {
      throw Exception(
        'La garantía ha expirado. Han pasado $diasDesdeVenta días desde la compra (garantía: $diasGarantia días)',
      );
    }

    final id = await db.insert('warranties', {
      'company_id': companyId,
      'venta_id': ventaId,
      'producto_id': productoId,
      'numero_serie': numeroSerie,
      'descripcion_problema': descripcionProblema,
      'status': 'Recibido',
      'fecha_recepcion': hoy.toIso8601String(),
      'dias_garantia': diasGarantia,
    });

    await registrarEventoAuditoria(
      accion: 'REGISTRAR_GARANTIA',
      entidad: 'warranties',
      entidadId: id,
      detalle:
          'Garantía registrada para venta #$ventaId, producto #$productoId',
    );

    return id;
  }

  /// Actualización automática de tasas de cambio.
  ///
  /// FAIL-CLOSED: no se inventa una TRM. Mientras no exista una fuente oficial
  /// configurada y verificable, la tasa debe registrarse por el flujo manual.
  Future<void> actualizarTasasCambioAutomaticamente() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final hoy = DateTime.now().toIso8601String().split('T').first;

    final existente = await db.query(
      'exchange_rates',
      where: 'date = ? AND company_id = ?',
      whereArgs: [hoy, companyId],
      limit: 1,
    );
    if (existente.isNotEmpty) return;

    await registrarEventoAuditoria(
      accion: 'TRM_AUTO_NO_CONFIGURADA',
      entidad: 'exchange_rates',
      detalle:
          'No se creó una tasa automática para $hoy: no hay fuente oficial configurada.',
    );
    throw StateError(
      'Actualización automática de TRM no configurada. Registre una tasa válida manualmente o configure una fuente oficial.',
    );
  }

  /// Convierte un monto de una moneda a la moneda base
  Future<double> convertirAMonedaBase(double monto, String currencyCode) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final hoy = DateTime.now().toIso8601String().split('T').first;

    // Verificar si es la moneda base
    final monedas = await db.query(
      'currencies',
      where: 'code = ? AND is_base_currency = 1',
      whereArgs: [currencyCode],
      limit: 1,
    );

    if (monedas.isNotEmpty) {
      return monto; // Ya está en moneda base
    }

    // Obtener tasa de cambio del día
    final tasas = await db.query(
      'exchange_rates',
      where: 'currency_code = ? AND date = ? AND company_id = ?',
      whereArgs: [currencyCode, hoy, companyId],
      limit: 1,
    );

    if (tasas.isEmpty) {
      throw Exception(
        'No hay tasa de cambio disponible para $currencyCode el día $hoy',
      );
    }

    final tasa = (tasas.first['rate_to_base'] as num).toDouble();
    return monto * tasa;
  }

  /// Dispara webhooks suscritos a un evento específico usando el servicio
  /// real de entrega, firma HMAC, logging y reintentos.
  Future<void> dispararWebhooks(
    String evento,
    Map<String, dynamic> payload,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await WebhookService.instance.triggerEvent(db, companyId, evento, payload);
  }

  /// Marca un paso de onboarding como completado
  Future<void> marcarPasoOnboardingCompletado(String stepName) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    await db.insert('onboarding_steps', {
      'company_id': companyId,
      'step_name': stepName,
      'is_completed': 1,
      'completed_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Obtiene el progreso de onboarding (porcentaje completado)
  Future<Map<String, dynamic>> obtenerProgresoOnboarding() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    final pasosEsperados = [
      'create_company',
      'add_taxes',
      'first_invoice',
      'upload_rut',
      'upload_signature',
    ];

    int completados = 0;
    final pasosActuales = <String, bool>{};

    for (final paso in pasosEsperados) {
      final pasos = await db.query(
        'onboarding_steps',
        where: 'company_id = ? AND step_name = ? AND is_completed = 1',
        whereArgs: [companyId, paso],
        limit: 1,
      );

      final completado = pasos.isNotEmpty;
      if (completado) completados++;
      pasosActuales[paso] = completado;
    }

    final porcentaje = (completados / pasosEsperados.length) * 100;

    return {
      'pasos_completados': completados,
      'total_pasos': pasosEsperados.length,
      'porcentaje_completado': porcentaje,
      'pasos_detalle': pasosActuales,
    };
  }

  /// Verifica si un paso crítico está completado
  Future<bool> pasoCriticoCompletado(String stepName) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    final pasos = await db.query(
      'onboarding_steps',
      where: 'company_id = ? AND step_name = ? AND is_completed = 1',
      whereArgs: [companyId, stepName],
      limit: 1,
    );

    return pasos.isNotEmpty;
  }

  /// Query Builder para reportes dinámicos
  /// Acepta parámetros estandarizados: date_range, group_by, filters, export_format
  Future<List<Map<String, dynamic>>> generarReporteDinamico({
    required String tabla,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    String? groupBy,
    Map<String, dynamic>? filters,
    String exportFormat = 'json',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    const allowedTables = {
      'ventas',
      'ventas_detalle',
      'compras',
      'compras_detalle',
      'productos',
      'movimientos_caja',
      'movimientos_inventario',
      'cuentas_por_cobrar',
      'cuentas_por_pagar',
      'facturas_electronicas',
      'empleados',
      'nomina_liquidaciones',
      'asientos_contables',
      'comprobantes_contables',
    };
    if (!allowedTables.contains(tabla)) {
      throw ArgumentError.value(
        tabla,
        'tabla',
        'Tabla de reporte no permitida',
      );
    }
    final columnRows = await db.rawQuery('PRAGMA table_info($tabla)');
    final allowedColumns = columnRows
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    if (!allowedColumns.contains('company_id')) {
      throw StateError(
        'La tabla de reporte no tiene aislamiento multiempresa.',
      );
    }
    final requestedColumns = <String>{?groupBy, ...?filters?.keys};
    final invalidColumns = requestedColumns.difference(allowedColumns);
    if (invalidColumns.isNotEmpty) {
      throw ArgumentError(
        'Columnas de reporte no permitidas: ${invalidColumns.join(', ')}',
      );
    }

    // Construir query base
    String query = 'SELECT * FROM $tabla WHERE company_id = ?';
    List<dynamic> whereArgs = [companyId];

    // Agregar filtro de rango de fechas si existe
    if (fechaDesde != null && fechaHasta != null) {
      if (!allowedColumns.contains('fecha')) {
        throw ArgumentError('La tabla $tabla no admite rango por fecha.');
      }
      query += ' AND fecha >= ? AND fecha < ?';
      whereArgs.add(fechaDesde.toIso8601String());
      whereArgs.add(fechaHasta.add(const Duration(days: 1)).toIso8601String());
    }

    // Agregar filtros adicionales
    if (filters != null) {
      filters.forEach((key, value) {
        query += ' AND $key = ?';
        whereArgs.add(value);
      });
    }

    // Agregar agrupación si existe
    if (groupBy != null) {
      query += ' GROUP BY $groupBy';
    }

    // Ejecutar query
    final resultados = await db.rawQuery(query, whereArgs);

    // Generar auditoría
    await registrarEventoAuditoria(
      accion: 'REPORTE_GENERADO',
      entidad: tabla,
      detalle: 'Reporte dinámico generado: $tabla, formato: $exportFormat',
    );

    return resultados;
  }

  /// Motor de renderizado de templates
  /// Reemplaza tags dinámicos como {{client_name}} con datos reales
  Future<String> renderizarTemplate(
    String tipo,
    Map<String, dynamic> datos,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    // Obtener template activo del tipo especificado
    final templates = await db.query(
      'templates',
      where: 'type = ? AND company_id = ? AND is_active = 1',
      whereArgs: [tipo, companyId],
      limit: 1,
    );

    if (templates.isEmpty) {
      throw Exception('No hay template activo para el tipo $tipo');
    }

    String htmlContent = templates.first['html_content']?.toString() ?? '';

    // Reemplazar tags dinámicos
    datos.forEach((key, value) {
      final tag = '{{$key}}';
      htmlContent = htmlContent.replaceAll(tag, value.toString());
    });

    return htmlContent;
  }

  Future<List<Map<String, dynamic>>> obtenerAuditoria() async {
    final db = await instance.database;
    return await db.query('auditoria_eventos', orderBy: 'fecha DESC');
  }

  Future<Map<String, MoneyValue>> obtenerEstadosFinancieros() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final balance = await obtenerBalanceComprobacion();
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    var activos = zero;
    var pasivos = zero;
    var patrimonio = zero;
    var ingresos = zero;
    var gastos = zero;
    var costos = zero;

    for (final cuenta in balance) {
      final tipo = cuenta['tipo'].toString();
      final saldo = MoneyValue.fromSql(
        cuenta['saldo'],
        currency: currency,
        nullableAsZero: true,
      );

      switch (tipo) {
        case 'activo':
          activos += saldo;
          break;
        case 'pasivo':
          pasivos += saldo;
          break;
        case 'patrimonio':
          patrimonio += saldo;
          break;
        case 'ingreso':
          ingresos += saldo;
          break;
        case 'gasto':
          gastos += saldo;
          break;
        case 'costo':
          costos += saldo;
          break;
      }
    }

    final utilidad = ingresos - costos - gastos;

    return {
      'activos': activos,
      'pasivos': pasivos,
      'patrimonio': patrimonio,
      'ingresos': ingresos,
      'costos': costos,
      'gastos': gastos,
      'utilidad': utilidad,
      'cuadre': activos - (pasivos + patrimonio + utilidad),
    };
  }

  Future<Map<String, dynamic>> obtenerEmpresaConfig() async {
    final db = await instance.database;
    final res = await db.query('empresa_config', where: 'id = 1', limit: 1);
    if (res.isEmpty) {
      return {'id': 1, 'nombre': 'MerkaERP', 'moneda': 'COP'};
    }
    return res.first;
  }

  /// Devuelve el marco NIIF declarado para la empresa activa.
  Future<FinancialFrameworkGroup> obtenerGrupoNiif([
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    final rows = await db.query(
      'companies',
      columns: ['niif_group'],
      where: 'id = ?',
      whereArgs: [companyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        'No se encontro la empresa activa para leer el marco NIIF.',
      );
    }
    return FinancialFrameworkGroup.fromDbValue(
      rows.first['niif_group']?.toString(),
    );
  }

  /// Guarda el marco declarado sin cambiar saldos historicos ni consolidacion.
  Future<void> configurarGrupoNiif(FinancialFrameworkGroup group) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final changed = await db.update(
      'companies',
      {
        'niif_group': group.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [companyId],
    );
    if (changed != 1) {
      throw StateError(
        'No se pudo guardar el marco NIIF de la empresa activa.',
      );
    }
    await registrarEventoAuditoria(
      accion: 'CONFIGURAR_MARCO_NIIF',
      entidad: 'companies',
      entidadId: companyId,
      detalle: 'Marco declarado: ${group.dbValue}',
    );
  }

  /// Expone el comportamiento de presentacion esperado por el marco.
  Future<Map<String, dynamic>> obtenerPoliticaMarcoContable() async {
    final group = await obtenerGrupoNiif();
    return FinancialFrameworkPolicy.forGroup(group).toMap();
  }

  Future<void> guardarEmpresaConfig(Map<String, dynamic> datos) async {
    final db = await instance.database;
    await db.insert('empresa_config', {
      'id': 1,
      ...datos,
      'actualizado': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> obtenerEmpresas() async {
    final db = await instance.database;
    await _crearTablasMultiempresaYConfig(db);
    return await db.query('empresas', orderBy: 'activa DESC, nombre ASC');
  }

  Future<int> guardarEmpresa(Map<String, dynamic> datos) async {
    final db = await instance.database;
    await _crearTablasMultiempresaYConfig(db);
    return await db.insert('empresas', {
      ...datos,
      'fecha': DateTime.now().toIso8601String(),
      'activa': datos['activa'] ?? 1,
    });
  }

  Future<void> actualizarEmpresa(int id, Map<String, dynamic> datos) async {
    final db = await instance.database;
    await db.update(
      'empresas',
      {...datos, 'fecha': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminarEmpresa(int id) async {
    final db = await instance.database;
    await db.delete('empresas', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> seleccionarEmpresa(Map<String, dynamic> empresa) async {
    await guardarEmpresaConfig({
      'nombre': empresa['nombre'] ?? 'MerkaERP',
      'nit': empresa['nit'] ?? '',
      'regimen': empresa['regimen'] ?? '',
      'direccion': empresa['direccion'] ?? '',
      'telefono': empresa['telefono'] ?? '',
      'email': empresa['email'] ?? '',
      'ciudad': empresa['ciudad'] ?? '',
      'moneda': empresa['moneda'] ?? 'COP',
      'logo_path': empresa['logo_path'] ?? '',
    });
    await _guardarAppConfig('empresa_actual_id', empresa['id'].toString());
  }

  Future<void> _guardarAppConfig(String clave, String valor) async {
    final db = await instance.database;
    await _crearTablasMultiempresaYConfig(db);
    await db.insert('app_config', {
      'clave': clave,
      'valor': valor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> obtenerAppConfig(String clave) async {
    final db = await instance.database;
    await _crearTablasMultiempresaYConfig(db);
    final res = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    return res.isEmpty ? null : res.first['valor']?.toString();
  }

  Future<ActiveCompanyConfiguration> obtenerConfiguracionActiva() async {
    final db = await instance.database;
    final companyId = await _sincronizarEmpresaLegacy(db);

    final companyRows = await db.query(
      'companies',
      where: 'id = ?',
      whereArgs: [companyId],
      limit: 1,
    );
    final company = companyRows.isEmpty
        ? {'id': companyId, 'name': 'MerkaERP'}
        : companyRows.first;

    final featureRows = await db.query(
      'company_features',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    final features = FeatureRegistry.defaultFeatures();
    for (final row in featureRows) {
      features[row['feature_key'].toString()] =
          (row['enabled'] as num? ?? 0) == 1;
    }

    final settingRows = await db.query(
      'company_settings',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    final settings = <String, String>{};
    for (final row in settingRows) {
      settings[row['setting_key'].toString()] =
          row['setting_value']?.toString() ?? '';
    }

    return ActiveCompanyConfiguration(
      companyId: companyId,
      companyName: company['name']?.toString() ?? 'MerkaERP',
      features: features,
      settings: settings,
      onboardingCompleted: settings['onboarding_completed'] == '1',
    );
  }

  Future<void> guardarConfiguracionInicial({
    required Company company,
    required CompanyProfile profile,
    required Map<String, bool> features,
    required Map<String, String> settings,
  }) async {
    final db = await instance.database;
    await _crearTablasConfiguracionEmpresarial(db);
    await _crearTablasEmpresaYComprobantes(db);
    await _crearTablasMultiempresaYConfig(db);

    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final companyId = await txn.insert('companies', {
        ...company.toMap(),
        'created_at': now,
        'updated_at': now,
      });

      await txn.insert('company_profiles', {
        ...profile.toMap(),
        'company_id': companyId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _guardarCompanyFeaturesEnDB(txn, companyId, features);
      await _guardarCompanySettingsEnDB(txn, companyId, {
        ...settings,
        'onboarding_completed': '1',
      });

      if (settings['tipo_entidad'] == 'publica') {
        await SchemaMultiTenant.crearEntidadPublicaDesdeConfiguracion(
          txn,
          companyId: companyId,
          nombreEmpresa: company.name,
          nit: company.taxId,
          subtipoLegado: settings['subtipo_entidad_publica'],
        );
      }

      await txn.insert('app_config', {
        'clave': 'company_active_id',
        'valor': companyId.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.insert('empresa_config', {
        'id': 1,
        'nombre': company.name,
        'nit': company.taxId,
        'regimen': profile.taxRegime,
        'moneda': company.currency,
        'actualizado': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await registrarEventoAuditoria(
      accion: 'CONFIGURACION_INICIAL',
      entidad: 'companies',
      detalle: '${company.name} configurada por onboarding',
    );
  }

  Future<void> aplicarCatalogoInicial({
    required List<Map<String, dynamic>> baseCatalog,
    required Map<String, bool> features,
    required Map<String, String> settings,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final vatEnabled = settings['vat_enabled'] != '0';
    final defaultTax = vatEnabled
        ? (double.tryParse(settings['default_tax'] ?? '') ?? 0)
        : 0.0;
    final invoicePrefix = settings['invoice_prefix']?.trim();
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await _sembrarCatalogosMaestrosSiNecesario(txn, companyId);

      if (invoicePrefix != null && invoicePrefix.isNotEmpty) {
        for (final tipo in const ['venta', 'ventas']) {
          await txn.insert('secuencias_documentos', {
            'company_id': companyId,
            'tipo': tipo,
            'prefijo': invoicePrefix,
            'siguiente': 1,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.update(
            'secuencias_documentos',
            {'prefijo': invoicePrefix},
            where: 'company_id = ? AND tipo = ?',
            whereArgs: [companyId, tipo],
          );
        }
      }

      for (final method in const [
        'EFECTIVO',
        'TRANSFERENCIA',
        'TARJETA',
        'NEQUI',
        'DAVIPLATA',
        'CREDITO',
        'PAGO MIXTO',
      ]) {
        await txn.insert('metodos_pago', {
          'nombre': method,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final inventoryEnabled = features[FeatureKey.inventory] == true;
      if (inventoryEnabled) {
        for (final item in baseCatalog) {
          final name = item['nombre']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          final exists = await txn.query(
            'productos',
            where: 'company_id = ? AND lower(nombre) = lower(?)',
            whereArgs: [companyId, name],
            limit: 1,
          );
          if (exists.isNotEmpty) continue;
          await txn.insert('productos', {
            'company_id': companyId,
            'nombre': name,
            'unidad_base': item['unidad']?.toString() ?? 'UND',
            'stock': 0,
            'costo': 0,
            'precio': 0,
            'impuesto_pct': defaultTax,
            'codigo_barras': '',
            'conversion_nombre': '',
            'conversion_cantidad': 0,
          });
        }
      }

      await txn.insert('company_settings', {
        'company_id': companyId,
        'setting_key': 'catalog_seeded_at',
        'setting_value': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, dynamic>>> obtenerCatalogoImpuestos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await _sembrarCatalogosMaestrosSiNecesario(db, companyId);
    return await db.query(
      'tax_catalog',
      where: 'company_id = ? AND active = 1',
      whereArgs: [companyId],
      orderBy: 'rate ASC',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerCatalogoUnidades() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await _sembrarCatalogosMaestrosSiNecesario(db, companyId);
    return await db.query(
      'unit_catalog',
      where: 'company_id = ? AND active = 1',
      whereArgs: [companyId],
      orderBy: 'label ASC',
    );
  }

  Future<Map<String, String>> obtenerReglasContablesEmpresa([
    DatabaseExecutor? txn,
  ]) async {
    final executor = txn ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    if (txn == null) {
      final db = await instance.database;
      await _sembrarCatalogosMaestrosSiNecesario(db, companyId);
    }
    final rows = await executor.query(
      'accounting_rule_settings',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    return {
      for (final row in rows)
        row['rule_key'].toString(): row['account_code'].toString(),
    };
  }

  Future<void> guardarCompanyFeatures(
    int companyId,
    Map<String, bool> features,
  ) async {
    final db = await instance.database;
    await _crearTablasConfiguracionEmpresarial(db);
    await _guardarCompanyFeaturesEnDB(db, companyId, features);
    await registrarEventoAuditoria(
      accion: 'ACTUALIZAR_FEATURES',
      entidad: 'company_features',
      entidadId: companyId,
      detalle: features.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .join(', '),
    );
  }

  Future<void> guardarCompanySettings(
    int companyId,
    Map<String, String> settings,
  ) async {
    final db = await instance.database;
    await _crearTablasConfiguracionEmpresarial(db);
    await _guardarCompanySettingsEnDB(db, companyId, settings);
    await registrarEventoAuditoria(
      accion: 'ACTUALIZAR_SETTINGS',
      entidad: 'company_settings',
      entidadId: companyId,
      detalle: settings.keys.join(', '),
    );
  }

  Future<void> _guardarCompanyFeaturesEnDB(
    DatabaseExecutor db,
    int companyId,
    Map<String, bool> features,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final entry in features.entries) {
      if (!FeatureRegistry.isKnown(entry.key)) continue;
      await db.insert('company_features', {
        'company_id': companyId,
        'feature_key': entry.key,
        'enabled': entry.value ? 1 : 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _guardarCompanySettingsEnDB(
    DatabaseExecutor db,
    int companyId,
    Map<String, String> settings,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final entry in settings.entries) {
      await db.insert('company_settings', {
        'company_id': companyId,
        'setting_key': entry.key,
        'setting_value': entry.value,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<bool> operacionBloqueadaPorCierre() async {
    return (await obtenerAppConfig('operacion_bloqueada')) == '1';
  }

  Future<bool> featureEstaHabilitada(String featureKey) async {
    final config = await obtenerConfiguracionActiva();
    return config.features[featureKey] ?? false;
  }

  Future<void> validarFeatureHabilitada(String featureKey) async {
    if (!await featureEstaHabilitada(featureKey)) {
      throw Exception('Modulo deshabilitado para la empresa activa.');
    }
  }

  Future<void> cambiarBloqueoOperativo(bool bloqueado) async {
    await _guardarAppConfig('operacion_bloqueada', bloqueado ? '1' : '0');
    await registrarEventoAuditoria(
      accion: bloqueado ? 'BLOQUEAR_OPERACION' : 'ABRIR_OPERACION',
      entidad: 'app_config',
      detalle: bloqueado
          ? 'Operacion bloqueada por cierre de caja'
          : 'Operacion reabierta manualmente',
    );
  }

  Future<String> _tomarConsecutivo(
    Transaction txn,
    String tipo,
    int companyId,
  ) async {
    final secuencia = await txn.query(
      'secuencias_documentos',
      where: 'company_id = ? AND tipo = ?',
      whereArgs: [companyId, tipo],
      limit: 1,
    );

    if (secuencia.isEmpty) {
      await txn.insert('secuencias_documentos', {
        'company_id': companyId,
        'tipo': tipo,
        'prefijo': 'DOC',
        'siguiente': 2,
      });
      return 'DOC-000001';
    }

    final prefijo = secuencia.first['prefijo'].toString();
    final siguiente = (secuencia.first['siguiente'] as num).toInt();
    final consecutivo = '$prefijo-${siguiente.toString().padLeft(6, '0')}';

    await txn.update(
      'secuencias_documentos',
      {'siguiente': siguiente + 1},
      where: 'company_id = ? AND tipo = ?',
      whereArgs: [companyId, tipo],
    );

    return consecutivo;
  }

  Future<int> _registrarComprobanteEnTransaccion(
    Transaction txn, {
    required int companyId,
    required int asientoId,
    required String tipo,
    required String concepto,
    required MoneyValue total,
    String? tercero,
    DateTime? fecha,
  }) async {
    final secuencia = await txn.query(
      'secuencias_documentos',
      where: 'company_id = ? AND tipo = ?',
      whereArgs: [companyId, tipo],
      limit: 1,
    );
    final prefijo = secuencia.isEmpty
        ? 'DOC'
        : secuencia.first['prefijo'].toString();
    final consecutivo = await _tomarConsecutivo(txn, tipo, companyId);
    final numero = int.tryParse(consecutivo.split('-').last) ?? 0;

    return await txn.insert('comprobantes_contables', {
      'company_id': companyId,
      'tipo': tipo,
      'prefijo': prefijo,
      'numero': numero,
      'consecutivo': consecutivo,
      'asiento_id': asientoId,
      'fecha': (fecha ?? DateTime.now()).toIso8601String(),
      'concepto': concepto,
      'tercero': tercero,
      'total': total.toSql(),
      'estado': 'emitido',
    });
  }

  Future<List<Map<String, dynamic>>> obtenerComprobantes() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'comprobantes_contables',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleComprobante(
    int comprobanteId,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        l.*,
        c.codigo,
        c.nombre AS cuenta,
        c.tipo,
        c.naturaleza
      FROM comprobantes_contables cc
      INNER JOIN asiento_lineas l ON l.asiento_id = cc.asiento_id
      INNER JOIN cuentas_contables c ON c.id = l.cuenta_id
      WHERE cc.id = ? AND cc.company_id = ?
      ORDER BY l.id ASC
      ''',
      [comprobanteId, companyId],
    );
  }

  // ── ABONOS CUENTAS POR PAGAR ─────────────────────────────

  Future<List<Map<String, dynamic>>> obtenerPeriodosContables() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'periodos_contables',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'anio DESC, mes DESC',
    );
  }

  Future<void> abrirPeriodoContable({
    required int anio,
    required int mes,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await db.insert('periodos_contables', {
      'company_id': companyId,
      'anio': anio,
      'mes': mes,
      'estado': 'abierto',
      'fecha_apertura': DateTime.now().toIso8601String(),
      'observacion': observacion,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await registrarEventoAuditoria(
      accion: 'ABRIR_PERIODO',
      entidad: 'periodos_contables',
      detalle: '$anio-${mes.toString().padLeft(2, '0')}',
    );
  }

  Future<void> cerrarPeriodoContable({
    required int anio,
    required int mes,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    await db.insert('periodos_contables', {
      'company_id': companyId,
      'anio': anio,
      'mes': mes,
      'estado': 'cerrado',
      'fecha_apertura': DateTime.now().toIso8601String(),
      'fecha_cierre': DateTime.now().toIso8601String(),
      'observacion': observacion,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.update(
      'periodos_contables',
      {
        'estado': 'cerrado',
        'fecha_cierre': DateTime.now().toIso8601String(),
        'observacion': observacion,
      },
      where: 'company_id = ? AND anio = ? AND mes = ?',
      whereArgs: [companyId, anio, mes],
    );

    await registrarEventoAuditoria(
      accion: 'CERRAR_PERIODO',
      entidad: 'periodos_contables',
      detalle: '$anio-${mes.toString().padLeft(2, '0')}',
    );
  }

  Future<bool> periodoEstaCerrado(
    DateTime fecha, [
    DatabaseExecutor? txn,
  ]) async {
    final executor = txn ?? await instance.database;
    final companyId = await obtenerEmpresaActivaId(executor);
    final res = await executor.query(
      'periodos_contables',
      where: 'company_id = ? AND anio = ? AND mes = ? AND estado = ?',
      whereArgs: [companyId, fecha.year, fecha.month, 'cerrado'],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  Future<void> _validarPeriodoAbierto(
    DateTime fecha, [
    DatabaseExecutor? txn,
  ]) async {
    if (await periodoEstaCerrado(fecha, txn)) {
      throw Exception(
        'El periodo ${fecha.year}-${fecha.month.toString().padLeft(2, '0')} está cerrado.',
      );
    }
  }

  Future<void> registrarAbonoCXP({
    required int cuentaId,
    required MoneyValue monto,
    required String metodoPago,
    String observacion = '',
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();

    // 🔥 obtener cuenta actual
    final cuentas = await db.query(
      'cuentas_por_pagar',
      where: 'id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
    );

    if (cuentas.isEmpty) return;

    final cuenta = cuentas.first;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final saldoActual = MoneyValue.fromSql(cuenta['saldo'], currency: currency);
    if (monto.minorUnits <= 0) {
      throw Exception('El abono debe ser mayor que cero.');
    }
    if (monto > saldoActual) {
      throw Exception('El abono no puede superar el saldo pendiente.');
    }

    final nuevoSaldo = saldoActual - monto;

    // 🔥 nuevo estado
    String nuevoEstado = 'parcial';

    if (nuevoSaldo.minorUnits == 0) {
      nuevoEstado = 'pagada';
    }

    // 🔥 registrar abono
    await db.insert('abonos_cxp', {
      'company_id': companyId,
      'cuenta_id': cuentaId,
      'monto': monto.toSql(),
      'metodo_pago': metodoPago,
      'observacion': observacion,
      'fecha': DateTime.now().toIso8601String(),
    });

    // 🔥 actualizar saldo
    await db.update(
      'cuentas_por_pagar',
      {'saldo': nuevoSaldo.toSql(), 'estado': nuevoEstado},
      where: 'id = ? AND company_id = ?',
      whereArgs: [cuentaId, companyId],
    );

    // 🔥 registrar salida de dinero
    final origen = metodoPago.toUpperCase() == 'EFECTIVO' ? 'caja' : 'banco';

    await db.insert('movimientos_caja', {
      'company_id': companyId,
      'tipo': 'egreso',
      'concepto': 'Abono cuenta por pagar #$cuentaId',
      'monto': monto.toSql(),
      'fecha': DateTime.now().toIso8601String(),
      'origen': origen,
    });

    await registrarAsientoAbonoCXP(
      cuentaId: cuentaId,
      monto: monto,
      metodoPago: metodoPago,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerCuentasContables() async {
    final db = await instance.database;
    return await db.query(
      'cuentas_contables',
      where: 'activa = 1',
      orderBy: 'codigo ASC',
    );
  }

  Future<int> insertarCuentaContable(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('cuentas_contables', row);
  }

  Future<int> registrarAsientoContable({
    required String concepto,
    required List<Map<String, dynamic>> lineas,
    String? referencia,
    String origen = 'manual',
    DateTime? fecha,
  }) async {
    if (lineas.length < 2) {
      throw Exception('Un asiento necesita al menos dos líneas.');
    }

    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final totalDebito = lineas.fold<MoneyValue>(
      zero,
      (sum, linea) =>
          sum +
          MoneyValue.fromSql(
            linea['debito'],
            currency: currency,
            nullableAsZero: true,
          ),
    );
    final totalCredito = lineas.fold<MoneyValue>(
      zero,
      (sum, linea) =>
          sum +
          MoneyValue.fromSql(
            linea['credito'],
            currency: currency,
            nullableAsZero: true,
          ),
    );

    if (totalDebito != totalCredito) {
      throw Exception('El asiento no está balanceado.');
    }
    if (totalDebito.minorUnits <= 0) {
      throw Exception('El asiento debe tener valor.');
    }

    final fechaAsiento = fecha ?? DateTime.now();
    await _validarPeriodoAbierto(fechaAsiento);

    return await db.transaction((txn) async {
      final asientoId = await txn.insert('asientos_contables', {
        'company_id': companyId,
        'fecha': fechaAsiento.toIso8601String(),
        'concepto': concepto,
        'referencia': referencia,
        'origen': origen,
        'estado': 'borrador',
      });

      for (final linea in lineas) {
        final debito = MoneyValue.fromSql(
          linea['debito'],
          currency: currency,
          nullableAsZero: true,
        );
        final credito = MoneyValue.fromSql(
          linea['credito'],
          currency: currency,
          nullableAsZero: true,
        );

        if (debito.minorUnits < 0 ||
            credito.minorUnits < 0 ||
            (debito.minorUnits > 0 && credito.minorUnits > 0)) {
          throw Exception('Cada línea debe tener débito o crédito, no ambos.');
        }

        // Validar asociación de terceros para cuentas específicas
        // CxC (1305), CxP (2205), Impuestos (2408), Retenciones (2365)
        final cuentaId = linea['cuenta_id'] as int;
        final cuentas = await txn.query(
          'cuentas_contables',
          where: 'id = ? AND company_id = ?',
          whereArgs: [cuentaId, companyId],
        );

        if (cuentas.isNotEmpty) {
          final codigo = cuentas.first['codigo']?.toString() ?? '';
          final requiereTercero =
              codigo.startsWith('1305') ||
              codigo.startsWith('2205') ||
              codigo.startsWith('2408') ||
              codigo.startsWith('2365');

          if (requiereTercero &&
              (linea['tercero'] == null ||
                  linea['tercero'].toString().isEmpty)) {
            throw Exception(
              'La cuenta $codigo requiere obligatoriamente un tercero (NIT) para generar exógena/medios magnéticos.',
            );
          }
        }

        await txn.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': asientoId,
          'cuenta_id': linea['cuenta_id'],
          'descripcion': linea['descripcion'] ?? concepto,
          'debito': debito.toSql(),
          'credito': credito.toSql(),
          'tercero': linea['tercero'],
        });
      }

      await txn.update(
        'asientos_contables',
        {'estado': 'registrado'},
        where: 'id = ?',
        whereArgs: [asientoId],
      );

      await _registrarComprobanteEnTransaccion(
        txn,
        companyId: companyId,
        asientoId: asientoId,
        tipo: origen == 'manual' ? 'asiento' : origen,
        concepto: concepto,
        total: totalDebito,
        fecha: fechaAsiento,
      );

      return asientoId;
    });
  }

  Future<List<Map<String, dynamic>>> obtenerAsientosContables() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        a.id,
        a.fecha,
        a.concepto,
        a.referencia,
        a.origen,
        a.estado,
        COALESCE(SUM(l.debito), 0) AS debito,
        COALESCE(SUM(l.credito), 0) AS credito
      FROM asientos_contables a
      LEFT JOIN asiento_lineas l ON l.asiento_id = a.id
      WHERE a.company_id = ?
      GROUP BY a.id
      ORDER BY a.fecha DESC, a.id DESC
    ''',
      [companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerDetalleAsiento(
    int asientoId,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        l.*,
        c.codigo,
        c.nombre AS cuenta,
        c.tipo,
        c.naturaleza
      FROM asiento_lineas l
      INNER JOIN cuentas_contables c ON c.id = l.cuenta_id
      WHERE l.asiento_id = ? AND l.company_id = ?
      ORDER BY l.id ASC
    ''',
      [asientoId, companyId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerBalanceComprobacion() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.rawQuery(
      '''
      SELECT
        c.id,
        c.codigo,
        c.nombre,
        c.tipo,
        c.naturaleza,
        COALESCE(SUM(l.debito), 0) AS debito,
        COALESCE(SUM(l.credito), 0) AS credito,
        CASE
          WHEN c.naturaleza = 'debito'
          THEN COALESCE(SUM(l.debito), 0) - COALESCE(SUM(l.credito), 0)
          ELSE COALESCE(SUM(l.credito), 0) - COALESCE(SUM(l.debito), 0)
        END AS saldo
      FROM cuentas_contables c
      LEFT JOIN asiento_lineas l ON l.cuenta_id = c.id AND l.company_id = ?
      WHERE c.activa = 1
      GROUP BY c.id
      ORDER BY c.codigo ASC
    ''',
      [companyId],
    );
  }

  Future<int> _cuentaIdPorCodigo(Transaction txn, String codigo) async {
    final res = await txn.query(
      'cuentas_contables',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );

    if (res.isEmpty) {
      throw Exception('No existe la cuenta contable $codigo.');
    }

    return res.first['id'] as int;
  }

  Future<int> _registrarAsientoConCodigos({
    required String concepto,
    required List<Map<String, dynamic>> lineas,
    String? referencia,
    String origen = 'automatico',
    DateTime? fecha,
    Transaction? txn,
  }) async {
    final fechaAsiento = fecha ?? DateTime.now();
    await _validarPeriodoAbierto(fechaAsiento, txn);
    final companyId = await obtenerEmpresaActivaId(txn);
    final executor = txn ?? await instance.database;
    final currency = await MoneyCurrencyResolver.resolve(
      executor,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);

    Future<int> performRegistration(Transaction t) async {
      final lineasConCuenta = <Map<String, dynamic>>[];

      for (final linea in lineas) {
        lineasConCuenta.add({
          ...linea,
          'cuenta_id': await _cuentaIdPorCodigo(t, linea['codigo'].toString()),
        });
      }

      final totalDebito = lineasConCuenta.fold<MoneyValue>(
        zero,
        (sum, linea) =>
            sum +
            MoneyValue.fromSql(
              linea['debito'],
              currency: currency,
              nullableAsZero: true,
            ),
      );
      final totalCredito = lineasConCuenta.fold<MoneyValue>(
        zero,
        (sum, linea) =>
            sum +
            MoneyValue.fromSql(
              linea['credito'],
              currency: currency,
              nullableAsZero: true,
            ),
      );

      if (totalDebito != totalCredito) {
        throw Exception('El asiento automático no está balanceado.');
      }

      final asientoId = await t.insert('asientos_contables', {
        'company_id': companyId,
        'fecha': fechaAsiento.toIso8601String(),
        'concepto': concepto,
        'referencia': referencia,
        'origen': origen,
        'estado': 'borrador',
      });

      for (final linea in lineasConCuenta) {
        await t.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': asientoId,
          'cuenta_id': linea['cuenta_id'],
          'descripcion': linea['descripcion'] ?? concepto,
          'debito': MoneyValue.fromSql(
            linea['debito'],
            currency: currency,
            nullableAsZero: true,
          ).toSql(),
          'credito': MoneyValue.fromSql(
            linea['credito'],
            currency: currency,
            nullableAsZero: true,
          ).toSql(),
          'tercero': linea['tercero'],
        });
      }

      await t.update(
        'asientos_contables',
        {'estado': 'registrado'},
        where: 'id = ?',
        whereArgs: [asientoId],
      );

      final terceros = lineasConCuenta
          .map((linea) => linea['tercero'])
          .where((tercero) => tercero != null && tercero.toString().isNotEmpty)
          .map((tercero) => tercero.toString())
          .toList();

      await _registrarComprobanteEnTransaccion(
        t,
        companyId: companyId,
        asientoId: asientoId,
        tipo: origen,
        concepto: concepto,
        total: totalDebito,
        tercero: terceros.isEmpty ? null : terceros.first,
        fecha: fechaAsiento,
      );

      return asientoId;
    }

    if (txn != null) {
      return await performRegistration(txn);
    } else {
      final db = await instance.database;
      return await db.transaction((t) => performRegistration(t));
    }
  }

  /// Cierra el ejercicio comercial en dos asientos auditables.
  ///
  /// El primer asiento salda las cuentas de ingresos, gastos y costos contra
  /// 3605/3610. El segundo mueve ese resultado a 3705. Ambos se registran en
  /// la misma transaccion para que el trigger de partida doble vea solo
  /// asientos completos y nunca quede un cierre a medias.
  Future<Map<String, dynamic>> cerrarEjercicioContable({
    required int anio,
    DateTime? fechaCierre,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final fecha = fechaCierre ?? DateTime(anio, 12, 31);
    final referenciaBase = 'CIERRE_EJERCICIO:$anio';
    final cierresPrevios = await db.query(
      'asientos_contables',
      columns: ['id', 'referencia'],
      where: 'company_id = ? AND referencia LIKE ?',
      whereArgs: [companyId, '$referenciaBase:%'],
      limit: 1,
    );
    if (cierresPrevios.isNotEmpty) {
      throw StateError('El ejercicio $anio ya tiene un cierre registrado.');
    }

    await _validarPeriodoAbierto(fecha);
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);

    return await db.transaction((txn) async {
      final balances = await txn.rawQuery(
        '''
        SELECT c.codigo, c.nombre, c.naturaleza,
               COALESCE(SUM(l.debito), 0) AS debito,
               COALESCE(SUM(l.credito), 0) AS credito
        FROM cuentas_contables c
        INNER JOIN asiento_lineas l ON l.cuenta_id = c.id
        INNER JOIN asientos_contables a ON a.id = l.asiento_id
        WHERE a.company_id = ?
          AND l.company_id = ?
          AND a.estado = 'registrado'
          AND substr(c.codigo, 1, 1) IN ('4', '5', '6', '7')
          AND substr(a.fecha, 1, 4) = ?
          AND (a.referencia IS NULL OR a.referencia NOT LIKE ?)
        GROUP BY c.id, c.codigo, c.nombre, c.naturaleza
        ORDER BY c.codigo ASC
        ''',
        [companyId, companyId, anio.toString(), '$referenciaBase:%'],
      );

      final lineasCierre = <Map<String, dynamic>>[];
      var debitoResultado = zero;
      var creditoResultado = zero;

      for (final balance in balances) {
        final debito = MoneyValue.fromSql(
          balance['debito'],
          currency: currency,
          nullableAsZero: true,
        );
        final credito = MoneyValue.fromSql(
          balance['credito'],
          currency: currency,
          nullableAsZero: true,
        );
        final naturaleza = balance['naturaleza']?.toString() ?? 'debito';
        final saldo = naturaleza == 'credito'
            ? credito - debito
            : debito - credito;
        if (saldo.minorUnits == 0) continue;

        if (naturaleza == 'credito') {
          lineasCierre.add({
            'codigo': balance['codigo'],
            'debito': saldo.toSql(),
            'credito': 0,
            'descripcion': 'Cierre de ${balance['nombre']}',
          });
          creditoResultado += saldo;
        } else {
          lineasCierre.add({
            'codigo': balance['codigo'],
            'debito': 0,
            'credito': saldo.toSql(),
            'descripcion': 'Cierre de ${balance['nombre']}',
          });
          debitoResultado += saldo;
        }
      }

      final resultado = creditoResultado - debitoResultado;
      if (resultado.minorUnits == 0) {
        throw StateError('No hay resultado contable para cerrar en $anio.');
      }

      final esUtilidad = resultado.minorUnits > 0;
      final resultadoAbs = esUtilidad ? resultado : resultado.abs();
      lineasCierre.add({
        'codigo': esUtilidad ? '3605' : '3610',
        'debito': esUtilidad ? 0 : resultadoAbs.toSql(),
        'credito': esUtilidad ? resultadoAbs.toSql() : 0,
        'descripcion': 'Resultado del ejercicio $anio',
      });

      final resultadoId = await _registrarAsientoConCodigos(
        concepto: 'Cierre de ingresos y gastos del ejercicio $anio',
        referencia: '$referenciaBase:RESULTADO',
        origen: 'cierre_ejercicio',
        fecha: fecha,
        lineas: lineasCierre,
        txn: txn,
      );

      final transferenciaId = await _registrarAsientoConCodigos(
        concepto: 'Traslado del resultado a ganancias acumuladas $anio',
        referencia: '$referenciaBase:PATRIMONIO',
        origen: 'cierre_ejercicio',
        fecha: fecha,
        lineas: [
          {
            'codigo': esUtilidad ? '3605' : '3705',
            'debito': resultadoAbs.toSql(),
            'credito': 0,
            'descripcion': 'Cierre de resultado del ejercicio',
          },
          {
            'codigo': esUtilidad ? '3705' : '3610',
            'debito': 0,
            'credito': resultadoAbs.toSql(),
            'descripcion': 'Traslado a resultados acumulados',
          },
        ],
        txn: txn,
      );

      return {
        'company_id': companyId,
        'anio': anio,
        'resultado_id': resultadoId,
        'transferencia_id': transferenciaId,
        'resultado_minor_units': resultadoAbs.minorUnits,
        'tipo_resultado': esUtilidad ? 'utilidad' : 'perdida',
      };
    });
  }

  String _codigoCuentaDinero(String origen) {
    final cuenta = origen.toLowerCase().trim();
    if (cuenta == 'banco') return '1110';
    if (cuenta == 'cartera') return '1305';
    return '1105';
  }

  Future<int> registrarAsientoVenta({
    required int ventaId,
    required MoneyValue total,
    required String metodoPago,
    required MoneyValue costoVenta,
    required MoneyValue impuesto,
    Transaction? txn,
  }) async {
    final companyId = await obtenerEmpresaActivaId(txn);
    final executor = txn ?? await instance.database;
    final currency = await MoneyCurrencyResolver.resolve(
      executor,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    List<Map<String, dynamic>> saleRows;

    if (txn != null) {
      saleRows = await txn.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
        limit: 1,
      );
    } else {
      final db = await instance.database;
      saleRows = await db.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [ventaId, companyId],
        limit: 1,
      );
    }

    var cashPayment = zero;
    var bankPayment = zero;
    var credit = zero;
    var retefuente = zero;
    var reteiva = zero;
    var reteica = zero;
    String clientName = 'Cliente general';

    if (saleRows.isNotEmpty) {
      final sale = saleRows.first;
      cashPayment = MoneyValue.fromSql(
        sale['efectivo'],
        currency: currency,
        nullableAsZero: true,
      );
      bankPayment = MoneyValue.fromSql(
        sale['transferencia'],
        currency: currency,
        nullableAsZero: true,
      );
      credit = MoneyValue.fromSql(
        sale['credito'],
        currency: currency,
        nullableAsZero: true,
      );
      retefuente = MoneyValue.fromSql(
        sale['retefuente'],
        currency: currency,
        nullableAsZero: true,
      );
      reteiva = MoneyValue.fromSql(
        sale['reteiva'],
        currency: currency,
        nullableAsZero: true,
      );
      reteica = MoneyValue.fromSql(
        sale['reteica'],
        currency: currency,
        nullableAsZero: true,
      );
      clientName = sale['cliente']?.toString() ?? 'Cliente general';
    }

    if ((cashPayment + bankPayment + credit).minorUnits == 0) {
      final normalized = metodoPago.toUpperCase().trim();
      if (normalized == 'CREDITO') {
        credit = total;
      } else if (normalized == 'TRANSFERENCIA' ||
          normalized == 'TARJETA' ||
          normalized == 'NEQUI' ||
          normalized == 'DAVIPLATA') {
        bankPayment = total;
      } else {
        cashPayment = total;
      }
    }

    final rules = await _reglasContablesActivas(txn);
    final draft = AccountingEngine(rules: rules).sale(
      saleId: ventaId,
      total: total,
      cashPayment: cashPayment,
      bankPayment: bankPayment,
      credit: credit,
      costOfSale: costoVenta,
      tax: impuesto,
      retefuente: retefuente,
      reteiva: reteiva,
      reteica: reteica,
      client: clientName,
    );

    return await _registrarAsientoConCodigos(
      concepto: draft.concept,
      referencia: draft.reference,
      origen: draft.origin,
      lineas: draft.toLegacyLines(),
      txn: txn,
    );
  }

  Future<int> registrarAsientoCompra({
    required int compraId,
    required MoneyValue total,
    required MoneyValue pagoCaja,
    required MoneyValue pagoBanco,
    required MoneyValue credito,
    String? proveedor,
    required MoneyValue impuesto,
    Transaction? txn,
  }) async {
    final zero = MoneyValue(minorUnits: 0, currency: total.currency);
    final rules = await _reglasContablesActivas(txn);
    final draft = AccountingEngine(rules: rules).purchase(
      purchaseId: compraId,
      total: total,
      cashPayment: pagoCaja,
      bankPayment: pagoBanco,
      credit: credito,
      supplier: proveedor,
      tax: impuesto,
      retefuente: zero,
      reteiva: zero,
      reteica: zero,
    );

    return await _registrarAsientoConCodigos(
      concepto: draft.concept,
      referencia: draft.reference,
      origen: draft.origin,
      lineas: draft.toLegacyLines(),
      txn: txn,
    );
  }

  Future<AccountingRuleSet> _reglasContablesActivas([
    DatabaseExecutor? txn,
  ]) async {
    final rules = await obtenerReglasContablesEmpresa(txn);
    return AccountingRuleSet(
      cashAccount: rules['cash'] ?? '1105',
      bankAccount: rules['bank'] ?? '1110',
      accountsReceivableAccount: rules['accounts_receivable'] ?? '1305',
      inventoryAccount: rules['inventory'] ?? '1435',
      taxDeductibleAccount: rules['tax_deductible'] ?? '1355',
      accountsPayableAccount: rules['accounts_payable'] ?? '2205',
      taxPayableAccount: rules['tax_payable'] ?? '2408',
      salesRevenueAccount: rules['sales_revenue'] ?? '4135',
      costOfSalesAccount: rules['cost_of_sales'] ?? '6135',
    );
  }

  Future<int> registrarAsientoMovimientoCaja({
    required String tipo,
    required String concepto,
    required MoneyValue monto,
    required String origen,
  }) async {
    final cuentaDinero = _codigoCuentaDinero(origen);
    final esIngreso = tipo.toLowerCase().trim() == 'ingreso';

    return await _registrarAsientoConCodigos(
      concepto: concepto,
      origen: 'caja',
      lineas: [
        {
          'codigo': esIngreso ? cuentaDinero : '5135',
          'debito': monto.toSql(),
          'credito': 0,
          'descripcion': concepto,
        },
        {
          'codigo': esIngreso ? '4135' : cuentaDinero,
          'debito': 0,
          'credito': monto.toSql(),
          'descripcion': concepto,
        },
      ],
    );
  }

  Future<int> registrarAsientoTransferencia({
    required String origen,
    required String destino,
    required MoneyValue monto,
    required String concepto,
  }) async {
    return await _registrarAsientoConCodigos(
      concepto: concepto,
      origen: 'transferencias',
      lineas: [
        {
          'codigo': _codigoCuentaDinero(destino),
          'debito': monto.toSql(),
          'credito': 0,
          'descripcion': concepto,
        },
        {
          'codigo': _codigoCuentaDinero(origen),
          'debito': 0,
          'credito': monto.toSql(),
          'descripcion': concepto,
        },
      ],
    );
  }

  Future<int> registrarAsientoAbonoCXP({
    required int cuentaId,
    required MoneyValue monto,
    required String metodoPago,
  }) async {
    final cuentaDinero = metodoPago.toUpperCase().trim() == 'EFECTIVO'
        ? '1105'
        : '1110';

    return await _registrarAsientoConCodigos(
      concepto: 'Abono cuenta por pagar #$cuentaId',
      referencia: 'CXP-$cuentaId',
      origen: 'cuentas_por_pagar',
      lineas: [
        {
          'codigo': '2205',
          'debito': monto.toSql(),
          'credito': 0,
          'descripcion': 'Disminución de cuenta por pagar #$cuentaId',
        },
        {
          'codigo': cuentaDinero,
          'debito': 0,
          'credito': monto.toSql(),
          'descripcion': 'Pago de cuenta por pagar #$cuentaId',
        },
      ],
    );
  }

  Future<int> registrarAsientoAbonoCXC({
    required int cuentaId,
    required MoneyValue monto,
    required String metodoPago,
  }) async {
    final cuentaDinero = metodoPago.toUpperCase().trim() == 'EFECTIVO'
        ? '1105'
        : '1110';

    return await _registrarAsientoConCodigos(
      concepto: 'Abono cuenta por cobrar #$cuentaId',
      referencia: 'CXC-$cuentaId',
      origen: 'cuentas_por_cobrar',
      lineas: [
        {
          'codigo': cuentaDinero,
          'debito': monto.toSql(),
          'credito': 0,
          'descripcion': 'Cobro de cartera #$cuentaId',
        },
        {
          'codigo': '1305',
          'debito': 0,
          'credito': monto.toSql(),
          'descripcion': 'Disminución de cuenta por cobrar #$cuentaId',
        },
      ],
    );
  }

  // ── CATÁLOGO DE BANCOS Y EXTRACTOS ─────────────────────────

  Future<List<Map<String, dynamic>>> obtenerBancos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'bancos',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
  }

  Future<int> guardarBanco({
    required String nombre,
    required String numeroCuenta,
    required String tipo,
    required MoneyValue saldoInicial,
    required String cuentaPuc,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.insert('bancos', {
      'company_id': companyId,
      'nombre': nombre,
      'numero_cuenta': numeroCuenta,
      'tipo': tipo,
      'saldo_inicial': saldoInicial.toSql(),
      'cuenta_puc': cuentaPuc,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  Future<void> eliminarBanco(int id) async {
    final db = await instance.database;
    await db.delete('bancos', where: 'id = ?', whereArgs: [id]);
  }

  // ── VALIDACIÓN Y OBTENCIÓN DE SALDO REAL ───────────────────

  Future<MoneyValue> obtenerSaldoDisponible(String metodo) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final codigoPuc = metodo.toUpperCase().trim() == 'EFECTIVO'
        ? '1105%'
        : '1110%';
    final List<Map<String, dynamic>> res = await db.rawQuery(
      '''
      SELECT SUM(debito) - SUM(credito) as saldo 
      FROM asiento_lineas 
      WHERE company_id = ? AND codigo LIKE ?
    ''',
      [companyId, codigoPuc],
    );
    return MoneyValue.fromSql(
      res.first['saldo'],
      currency: currency,
      nullableAsZero: true,
    );
  }

  Future<MoneyValue> obtenerSaldoBanco(int bancoId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final bancos = await db.query(
      'bancos',
      where: 'id = ?',
      whereArgs: [bancoId],
    );
    if (bancos.isEmpty) return zero;
    final banco = bancos.first;
    final cuentaPuc = banco['cuenta_puc']?.toString() ?? '111005';
    final List<Map<String, dynamic>> res = await db.rawQuery(
      '''
      SELECT SUM(debito) - SUM(credito) as saldo 
      FROM asiento_lineas 
      WHERE company_id = ? AND codigo LIKE ?
    ''',
      [companyId, '$cuentaPuc%'],
    );
    final saldoInicial = MoneyValue.fromSql(
      banco['saldo_inicial'],
      currency: currency,
      nullableAsZero: true,
    );
    final movimientos = MoneyValue.fromSql(
      res.first['saldo'],
      currency: currency,
      nullableAsZero: true,
    );
    return saldoInicial + movimientos;
  }

  // ── ANULACIÓN DE MOVIMIENTO DE CAJA/BANCOS ──────────────────

  Future<void> anularMovimientoCaja(int id) async {
    final db = await instance.database;
    final movs = await db.query(
      'movimientos_caja',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (movs.isEmpty) return;
    final mov = movs.first;

    await db.update(
      'movimientos_caja',
      {'activo': 0},
      where: 'id = ?',
      whereArgs: [id],
    );

    final concepto = 'Reversión: ${mov['concepto']}';
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final monto = MoneyValue.fromSql(mov['monto'], currency: currency);
    final esIngreso = mov['tipo'].toString().toLowerCase() == 'ingreso';

    final bancoId = mov['banco_id'] as int?;
    String cuentaDinero = '110505';
    if (bancoId != null) {
      final bancos = await db.query(
        'bancos',
        where: 'id = ?',
        whereArgs: [bancoId],
      );
      if (bancos.isNotEmpty) {
        cuentaDinero = bancos.first['cuenta_puc']?.toString() ?? '111005';
      }
    }

    await _registrarAsientoConCodigos(
      concepto: concepto,
      origen: 'caja_anulacion',
      lineas: [
        {
          'codigo': esIngreso ? '4135' : cuentaDinero,
          'debito': monto.toSql(),
          'credito': 0,
          'descripcion': concepto,
        },
        {
          'codigo': esIngreso ? cuentaDinero : '5135',
          'debito': 0,
          'credito': monto.toSql(),
          'descripcion': concepto,
        },
      ],
    );
  }

  // ── EXTRACTOS BANCARIOS Y CONCILIACIÓN ─────────────────────

  Future<int> guardarExtractoBancario({
    required int bancoId,
    required String fecha,
    required String descripcion,
    required MoneyValue monto,
    required String referencia,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.insert('extractos_bancarios', {
      'company_id': companyId,
      'cuenta': bancoId.toString(),
      'fecha': fecha,
      'descripcion': descripcion,
      'valor': monto.abs().toSql(),
      'tipo': monto.minorUnits >= 0 ? 'ingreso' : 'egreso',
      'referencia': referencia,
      'conciliado': 0,
      'creado': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> obtenerExtractosPorBanco(
    int bancoId,
  ) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    return await db.query(
      'extractos_bancarios',
      where: 'company_id = ? AND cuenta = ?',
      whereArgs: [companyId, bancoId.toString()],
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>>
  obtenerLineasContablesBancariasNoConciliadas(int bancoId) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final bancos = await db.query(
      'bancos',
      where: 'id = ? AND company_id = ?',
      whereArgs: [bancoId, companyId],
    );
    if (bancos.isEmpty) return [];
    final cuentaPuc = bancos.first['cuenta_puc']?.toString() ?? '111005';

    return await db.rawQuery(
      '''
      SELECT al.*, ac.fecha as fecha_asiento, ac.concepto as concepto_asiento
      FROM asiento_lineas al
      JOIN asientos_contables ac ON al.asiento_id = ac.id
      WHERE al.company_id = ? AND al.codigo LIKE ?
      AND al.id NOT IN (
        SELECT IFNULL(asiento_linea_id, 0) FROM extractos_bancarios WHERE company_id = ? AND conciliado = 1
      )
      ORDER BY ac.fecha DESC
    ''',
      [companyId, '$cuentaPuc%', companyId],
    );
  }

  Future<void> conciliarTransacciones(
    int extractoId,
    int asientoLineaId,
  ) async {
    final db = await instance.database;
    await db.update(
      'extractos_bancarios',
      {'conciliado': 1, 'asiento_linea_id': asientoLineaId},
      where: 'id = ?',
      whereArgs: [extractoId],
    );
  }

  Future<void> desconciliarTransaccion(int extractoId) async {
    final db = await instance.database;
    await db.update(
      'extractos_bancarios',
      {'conciliado': 0, 'asiento_linea_id': null},
      where: 'id = ?',
      whereArgs: [extractoId],
    );
  }

  // ── ACTIVOS FIJOS Y DEPRECIACIÓN AUTOMÁTICA ─────────────────

  Future<void> procesarDepreciacionMensual() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final activos = await db.query(
      'activos_fijos',
      where: 'company_id = ? AND estado = ?',
      whereArgs: [companyId, 'activo'],
    );
    final ahoraStr = DateTime.now().toIso8601String().split('T').first;

    for (final act in activos) {
      final id = act['id'] as int;
      final costo = (act['costo'] as num).toDouble();
      final valorResidual = (act['valor_residual'] as num?)?.toDouble() ?? 0;
      final vidaUtilMeses = (act['vida_util_meses'] as num).toInt();
      final depreciacionAcumulada =
          (act['depreciacion_acumulada'] as num?)?.toDouble() ?? 0;
      final valorLibros = (act['valor_libros'] as num?)?.toDouble() ?? costo;

      if (vidaUtilMeses <= 0 || valorLibros <= valorResidual) continue;

      final ultDep = act['fecha_depreciacion']?.toString();

      if (ultDep != null &&
          ultDep.substring(0, 7) == ahoraStr.substring(0, 7)) {
        continue;
      }

      // Fórmula de Depreciación (Línea Recta)
      // Cuota Mensual = (purchase_value - salvage_value) / useful_life_months
      final cuotaMensual = (costo - valorResidual) / vidaUtilMeses;

      // Verificar que no exceda el valor residual
      final nuevaDepreciacionAcumulada = depreciacionAcumulada + cuotaMensual;
      final nuevoValorLibros = costo - nuevaDepreciacionAcumulada;

      if (nuevoValorLibros < valorResidual) {
        // No depreciar más allá del valor residual
        continue;
      }

      final codigoPucActivo = act['codigo_puc']?.toString() ?? '1524';
      final codigoPucGasto =
          act['codigo_puc_depreciacion']?.toString() ?? '5160';

      await _registrarAsientoConCodigos(
        concepto: 'Depreciación Mensual Activo #$id - ${act['nombre']}',
        referencia: 'DEP-$id',
        origen: 'activos_fijos',
        lineas: [
          {
            'codigo': codigoPucGasto,
            'debito': cuotaMensual,
            'credito': 0,
            'descripcion': 'Depreciación gasto mensual: ${act['nombre']}',
          },
          {
            'codigo': codigoPucActivo,
            'debito': 0,
            'credito': cuotaMensual,
            'descripcion': 'Depreciación acumulada mensual: ${act['nombre']}',
          },
        ],
      );

      await db.update(
        'activos_fijos',
        {
          'depreciacion_acumulada': nuevaDepreciacionAcumulada,
          'valor_libros': nuevoValorLibros,
          'fecha_depreciacion': ahoraStr,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ── PERIODOS CONTABLES: COMPROBACIÓN DE CIERRE Y REVERSIÓN ──

  Future<bool> esPeriodoAbierto(String fecha) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    if (fecha.isEmpty) return true;
    final anioMes = fecha.substring(0, 7);
    final partes = anioMes.split('-');
    final anio = int.tryParse(partes[0]) ?? 0;
    final mes = int.tryParse(partes[1]) ?? 0;

    final periodos = await db.query(
      'periodos_contables',
      where: 'company_id = ? AND anio = ? AND mes = ?',
      whereArgs: [companyId, anio, mes],
      limit: 1,
    );
    if (periodos.isEmpty) return true;
    return periodos.first['estado']?.toString() == 'abierto';
  }

  Future<void> cambiarEstadoPeriodo(int anio, int mes, String estado) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final periodos = await db.query(
      'periodos_contables',
      where: 'company_id = ? AND anio = ? AND mes = ?',
      whereArgs: [companyId, anio, mes],
    );

    if (periodos.isEmpty) {
      await db.insert('periodos_contables', {
        'company_id': companyId,
        'anio': anio,
        'mes': mes,
        'estado': estado,
        'fecha_apertura': DateTime.now().toIso8601String(),
      });
    } else {
      await db.update(
        'periodos_contables',
        {'estado': estado},
        where: 'company_id = ? AND anio = ? AND mes = ?',
        whereArgs: [companyId, anio, mes],
      );
    }
  }

  Future<int> actualizarBanco({
    required int id,
    required String nombre,
    required String numeroCuenta,
    required String tipo,
    required MoneyValue saldoInicial,
    required String cuentaPuc,
  }) async {
    final db = await instance.database;
    return await db.update(
      'bancos',
      {
        'nombre': nombre,
        'numero_cuenta': numeroCuenta,
        'tipo': tipo,
        'saldo_inicial': saldoInicial.toSql(),
        'cuenta_puc': cuentaPuc,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Borrador Formulario 300 (IVA) - DIAN Colombia.
  Future<List<Map<String, dynamic>>> obtenerDetalleFormulario300({
    required int anio,
    required int mes,
  }) async {
    final db = await database;
    final companyId = await obtenerEmpresaActivaId();
    final inicio = DateTime(anio, mes, 1).toIso8601String();
    final fin = DateTime(anio, mes + 1, 1).toIso8601String();
    final rows = <Map<String, dynamic>>[];

    rows.addAll(
      await db.rawQuery(
        '''
      SELECT vd.id AS documento_id, 'venta' AS origen,
             COALESCE(vd.impuesto_pct, v.impuesto_pct, 0) AS tarifa,
             vd.subtotal AS base, COALESCE(vd.impuesto_total, 0) AS impuesto
      FROM ventas_detalle vd
      INNER JOIN ventas v ON v.id = vd.venta_id
      WHERE v.company_id = ? AND v.fecha >= ? AND v.fecha < ?
        AND COALESCE(v.estado, 'emitida') != 'anulada'
    ''',
        [companyId, inicio, fin],
      ),
    );
    rows.addAll(
      await db.rawQuery(
        '''
      SELECT v.id AS documento_id, 'venta' AS origen,
             COALESCE(v.impuesto_pct, 0) AS tarifa,
             v.subtotal AS base, COALESCE(v.impuesto_total, 0) AS impuesto
      FROM ventas v
      WHERE v.company_id = ? AND v.fecha >= ? AND v.fecha < ?
        AND COALESCE(v.estado, 'emitida') != 'anulada'
        AND NOT EXISTS (
          SELECT 1 FROM ventas_detalle vd WHERE vd.venta_id = v.id
        )
    ''',
        [companyId, inicio, fin],
      ),
    );
    rows.addAll(
      await db.rawQuery(
        '''
      SELECT cd.id AS documento_id, 'compra' AS origen,
             COALESCE(cd.impuesto_pct, c.impuesto_pct, 0) AS tarifa,
             cd.subtotal AS base, COALESCE(cd.impuesto_total, 0) AS impuesto
      FROM compras_detalle cd
      INNER JOIN compras c ON c.id = cd.compra_id
      WHERE c.company_id = ? AND c.fecha >= ? AND c.fecha < ?
        AND COALESCE(c.estado, 'pagada') != 'anulada'
    ''',
        [companyId, inicio, fin],
      ),
    );
    rows.addAll(
      await db.rawQuery(
        '''
      SELECT c.id AS documento_id, 'compra' AS origen,
             COALESCE(c.impuesto_pct, 0) AS tarifa,
             c.subtotal AS base, COALESCE(c.impuesto_total, 0) AS impuesto
      FROM compras c
      WHERE c.company_id = ? AND c.fecha >= ? AND c.fecha < ?
        AND COALESCE(c.estado, 'pagada') != 'anulada'
        AND NOT EXISTS (
          SELECT 1 FROM compras_detalle cd WHERE cd.compra_id = c.id
        )
    ''',
        [companyId, inicio, fin],
      ),
    );
    return rows;
  }

  Future<Map<String, MoneyValue>> obtenerBorradorFormulario300({
    required int anio,
    required int mes,
  }) async {
    final db = await database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    var base0 = zero;
    var base5 = zero;
    var base19 = zero;
    var baseOther = zero;
    var iva0 = zero;
    var iva5 = zero;
    var iva19 = zero;
    var ivaOther = zero;
    var ivaDescontable = zero;

    for (final row in await obtenerDetalleFormulario300(anio: anio, mes: mes)) {
      final base = MoneyValue.fromSql(row['base'], currency: currency);
      final tax = MoneyValue.fromSql(
        row['impuesto'],
        currency: currency,
        nullableAsZero: true,
      );
      final rate = (row['tarifa'] as num?)?.toDouble() ?? 0;
      if (row['origen'] == 'compra') {
        ivaDescontable += tax;
        continue;
      }
      switch (rate) {
        case 0:
          base0 += base;
          iva0 += tax;
        case 5:
          base5 += base;
          iva5 += tax;
        case 19:
          base19 += base;
          iva19 += tax;
        default:
          baseOther += base;
          ivaOther += tax;
      }
    }
    final ivaGenerado = iva0 + iva5 + iva19 + ivaOther;
    final baseGravada = base5 + base19 + baseOther;
    final fiscal = await obtenerReporteFiscal(anio: anio, mes: mes);
    return {
      'ingresos_gravados': baseGravada,
      'base_gravada': baseGravada,
      'base_gravada_0': base0,
      'base_gravada_5': base5,
      'base_gravada_19': base19,
      'base_gravada_otra': baseOther,
      'iva_generado': ivaGenerado,
      'iva_generado_0': iva0,
      'iva_generado_5': iva5,
      'iva_generado_19': iva19,
      'iva_generado_otra': ivaOther,
      'iva_descontable': ivaDescontable,
      'saldo_pagar': ivaGenerado - ivaDescontable,
      'reteiva_practicada': fiscal['reteiva_practicada']!,
    };
  }

  /// Borrador Formulario 350 (Retención en la Fuente) - DIAN.
  Future<List<Map<String, dynamic>>> obtenerDetalleFormulario350({
    required int anio,
    required int mes,
  }) async {
    final db = await database;
    final companyId = await obtenerEmpresaActivaId();
    final inicio = DateTime(anio, mes, 1).toIso8601String();
    final fin = DateTime(anio, mes + 1, 1).toIso8601String();
    final rows = <Map<String, dynamic>>[];
    rows.addAll(
      await db.rawQuery(
        '''
      SELECT id AS documento_id, 'venta' AS origen,
             COALESCE(NULLIF(retefuente_concepto, ''), 'otros_ingresos') AS concepto,
             CASE WHEN COALESCE(retefuente_base, 0) = 0 THEN subtotal
                  ELSE retefuente_base END AS base,
             COALESCE(retefuente_tasa, 0) AS tasa,
             retefuente AS retencion
      FROM ventas
      WHERE company_id = ? AND fecha >= ? AND fecha < ?
        AND COALESCE(estado, 'emitida') != 'anulada'
        AND COALESCE(retefuente, 0) != 0
    ''',
        [companyId, inicio, fin],
      ),
    );
    rows.addAll(
      await db.rawQuery(
        '''
      SELECT id AS documento_id, 'compra' AS origen,
             COALESCE(NULLIF(retefuente_concepto, ''), 'compras') AS concepto,
             CASE WHEN COALESCE(retefuente_base, 0) = 0 THEN subtotal
                  ELSE retefuente_base END AS base,
             COALESCE(retefuente_tasa, 0) AS tasa,
             retefuente AS retencion
      FROM compras
      WHERE company_id = ? AND fecha >= ? AND fecha < ?
        AND COALESCE(estado, 'pagada') != 'anulada'
        AND COALESCE(retefuente, 0) != 0
    ''',
        [companyId, inicio, fin],
      ),
    );
    return rows;
  }

  Future<Map<String, MoneyValue>> obtenerBorradorFormulario350({
    required int anio,
    required int mes,
  }) async {
    final db = await database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final result = <String, MoneyValue>{
      'retefuente_compras': zero,
      'retefuente_servicios': zero,
      'retefuente_honorarios': zero,
      'retefuente_arrendamientos': zero,
      'retefuente_otros_ingresos': zero,
      'total_retenciones': zero,
    };

    for (final row in await obtenerDetalleFormulario350(anio: anio, mes: mes)) {
      final amount = MoneyValue.fromSql(row['retencion'], currency: currency);
      final concept = row['concepto'].toString().trim().toLowerCase();
      final key = switch (concept) {
        'compras' => 'retefuente_compras',
        'servicios' => 'retefuente_servicios',
        'honorarios' => 'retefuente_honorarios',
        'arrendamientos' => 'retefuente_arrendamientos',
        _ => 'retefuente_otros_ingresos',
      };
      result[key] = result[key]! + amount;
      result['total_retenciones'] = result['total_retenciones']! + amount;
    }
    return result;
  }

  /// Borrador Formulario 110 (Renta Personas Jurídicas) - resumen anual.
  Future<Map<String, MoneyValue>> obtenerBorradorFormulario110({
    required int anio,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final inicio = DateTime(anio, 1, 1).toIso8601String();
    final fin = DateTime(anio + 1, 1, 1).toIso8601String();

    Future<MoneyValue> sum(String sql) async {
      final res = await db.rawQuery(sql, [companyId, inicio, fin]);
      return MoneyValue.fromSql(
        res.first['total'],
        currency: currency,
        nullableAsZero: true,
      );
    }

    final ventas = await sum(
      "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, 'emitida') != 'anulada'",
    );
    final compras = await sum(
      "SELECT COALESCE(SUM(total), 0) AS total FROM compras WHERE company_id = ? AND fecha >= ? AND fecha < ? AND estado != 'anulada'",
    );
    final estados = await obtenerEstadosFinancieros();

    return {
      'patrimonio_bruto': estados['activos']!,
      'pasivos': estados['pasivos']!,
      'patrimonio_liquido': estados['patrimonio']!,
      'ingresos_operacionales': ventas,
      'costos_ventas': compras,
      'gastos_operativos': estados['gastos']!,
      'utilidad_gravable': estados['utilidad'] ?? (ventas - compras),
    };
  }

  /// Borrador ICA municipal (bimestral/anual).
  Future<Map<String, Object>> obtenerBorradorICA({
    required int anio,
    required int mesInicio,
    required int mesFin,
    double tarifaPorMil = 11.04,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final inicio = DateTime(anio, mesInicio, 1).toIso8601String();
    final fin = DateTime(anio, mesFin + 1, 1).toIso8601String();
    final res = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ? AND COALESCE(estado, 'emitida') != 'anulada'",
      [companyId, inicio, fin],
    );
    final ingresosBrutos = MoneyValue.fromSql(
      res.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final ingresosNetos = ingresosBrutos.multiplyDecimal('0.95');
    final ica = ingresosNetos
        .multiplyDecimal(tarifaPorMil.toString())
        .divideDecimal('1000');
    final avisosTableros = ica.percent('15');

    final reteica = await db.rawQuery(
      'SELECT COALESCE(SUM(reteica), 0) AS total FROM ventas WHERE company_id = ? AND fecha >= ? AND fecha < ?',
      [companyId, inicio, fin],
    );
    final reteicaPracticada = MoneyValue.fromSql(
      reteica.first['total'],
      currency: currency,
      nullableAsZero: true,
    );

    return {
      'ingresos_brutos': ingresosBrutos,
      'ingresos_netos_gravables': ingresosNetos,
      'tarifa_por_mil': tarifaPorMil.toString(),
      'impuesto_ica': ica,
      'avisos_tableros': avisosTableros,
      'reteica_practicada': reteicaPracticada,
      'saldo_pagar': ica + avisosTableros - reteicaPracticada,
    };
  }

  /// Procesa un traslado de bodega de forma atómica (OUT en origen, IN en destino)
  Future<int> procesarTrasladoBodega({
    required int trasladoId,
    required String usuario,
  }) async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    await db.transaction((txn) async {
      final traslados = await txn.query(
        'traslados_bodega',
        where: 'id = ? AND company_id = ? AND estado = ?',
        whereArgs: [trasladoId, companyId, 'registrado'],
      );

      if (traslados.isEmpty) {
        throw Exception('Traslado no encontrado o ya procesado');
      }

      final traslado = traslados.first;
      final productoId = traslado['producto_id'] as int;
      final bodegaOrigenId = traslado['bodega_origen_id'] as int;
      final bodegaDestinoId = traslado['bodega_destino_id'] as int;
      final cantidad = (traslado['cantidad'] as num).toDouble();

      // Obtener stock en bodega origen
      final stockOrigen = await txn.query(
        'stock_bodega',
        where: 'producto_id = ? AND bodega_id = ? AND company_id = ?',
        whereArgs: [productoId, bodegaOrigenId, companyId],
      );

      if (stockOrigen.isEmpty) {
        throw Exception('No existe stock en bodega origen');
      }

      final stockActualOrigen = (stockOrigen.first['cantidad'] as num)
          .toDouble();
      if (stockActualOrigen < cantidad) {
        throw Exception('Stock insuficiente en bodega origen');
      }

      // Obtener costo actual del producto
      final productos = await txn.query(
        'productos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [productoId, companyId],
      );
      final costoActual = MoneyValue.fromSql(
        productos.first['costo'],
        currency: currency,
        nullableAsZero: true,
      );

      // Generar OUT en bodega origen
      final nuevoStockOrigen = stockActualOrigen - cantidad;
      final transferTimestamp = DateTime.now().toIso8601String();
      await txn.update(
        'stock_bodega',
        {'cantidad': nuevoStockOrigen, 'actualizado_en': transferTimestamp},
        where: 'producto_id = ? AND bodega_id = ? AND company_id = ?',
        whereArgs: [productoId, bodegaOrigenId, companyId],
      );

      await InventoryMovementService.record(
        db: txn,
        companyId: companyId,
        productId: productoId,
        type: 'salida',
        quantity: cantidad,
        stockBefore: stockActualOrigen,
        stockAfter: nuevoStockOrigen,
        warehouseId: bodegaOrigenId,
        costBeforeMinor: costoActual.toSql(),
        costAfterMinor: costoActual.toSql(),
        costTotalMinor: costoActual
            .multiplyDecimal(cantidad.toString())
            .toSql(),
        reason: 'TRASLADO #$trasladoId (BODEGA ORIGEN)',
        date: DateTime.now().toIso8601String(),
        documentType: 'traslado',
        documentId: trasladoId,
      );

      // Generar IN en bodega destino
      final stockDestino = await txn.query(
        'stock_bodega',
        where: 'producto_id = ? AND bodega_id = ? AND company_id = ?',
        whereArgs: [productoId, bodegaDestinoId, companyId],
      );

      if (stockDestino.isEmpty) {
        // Crear registro si no existe
        await txn.insert('stock_bodega', {
          'company_id': companyId,
          'producto_id': productoId,
          'bodega_id': bodegaDestinoId,
          'cantidad': cantidad,
          'costo': costoActual.toSql(),
          'actualizado_en': transferTimestamp,
        });
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productoId,
          type: 'entrada',
          quantity: cantidad,
          stockBefore: 0,
          stockAfter: cantidad,
          warehouseId: bodegaDestinoId,
          costBeforeMinor: costoActual.toSql(),
          costAfterMinor: costoActual.toSql(),
          costTotalMinor: costoActual
              .multiplyDecimal(cantidad.toString())
              .toSql(),
          reason: 'TRASLADO #$trasladoId (BODEGA DESTINO)',
          date: DateTime.now().toIso8601String(),
          documentType: 'traslado',
          documentId: trasladoId,
        );
      } else {
        final stockActualDestino = (stockDestino.first['cantidad'] as num)
            .toDouble();
        final nuevoStockDestino = stockActualDestino + cantidad;
        await txn.update(
          'stock_bodega',
          {'cantidad': nuevoStockDestino, 'actualizado_en': transferTimestamp},
          where: 'producto_id = ? AND bodega_id = ? AND company_id = ?',
          whereArgs: [productoId, bodegaDestinoId, companyId],
        );

        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productoId,
          type: 'entrada',
          quantity: cantidad,
          stockBefore: stockActualDestino,
          stockAfter: nuevoStockDestino,
          warehouseId: bodegaDestinoId,
          costBeforeMinor: costoActual.toSql(),
          costAfterMinor: costoActual.toSql(),
          costTotalMinor: costoActual
              .multiplyDecimal(cantidad.toString())
              .toSql(),
          reason: 'TRASLADO #$trasladoId (BODEGA DESTINO)',
          date: DateTime.now().toIso8601String(),
          documentType: 'traslado',
          documentId: trasladoId,
        );
      }

      // Actualizar estado del traslado
      await txn.update(
        'traslados_bodega',
        {'estado': 'completado', 'usuario': usuario},
        where: 'id = ?',
        whereArgs: [trasladoId],
      );
    });

    // La auditoria usa la conexion principal; debe ejecutarse despues de
    // cerrar la transaccion para no bloquear SQLite mientras se mueve stock.
    await registrarEventoAuditoria(
      accion: 'PROCESAR_TRASLADO_BODEGA',
      entidad: 'traslados_bodega',
      entidadId: trasladoId,
      detalle: 'Traslado #$trasladoId procesado por $usuario',
    );

    return trasladoId;
  }

  /// Bloquea lotes vencidos (Cron Job diario)
  /// Cambia el estado de lotes cuya fecha de vencimiento ya pasó a 'blocked'
  Future<int> bloquearLotesVencidos() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final hoy = DateTime.now().toIso8601String().split('T').first;

    final result = await db.update(
      'lotes',
      {'status': 'blocked'},
      where: 'company_id = ? AND status = ? AND fecha_vencimiento < ?',
      whereArgs: [companyId, 'active', hoy],
    );

    if (result > 0) {
      await registrarEventoAuditoria(
        accion: 'BLOQUEAR_LOTES_VENCIDOS',
        entidad: 'lotes',
        entidadId: 0,
        detalle: '$result lotes vencidos bloqueados',
      );
    }

    return result;
  }

  /// Calcula el aging de cartera (clasificación por días de vencimiento)
  /// Retorna un mapa con las columnas: al_dia, vencido_30, vencido_60, vencido_90, vencido_mas_90
  Future<Map<String, double>> calcularAgingCartera() async {
    final db = await instance.database;
    final companyId = await obtenerEmpresaActivaId();
    final hoy = DateTime.now();

    final cuentas = await db.query(
      'cuentas_por_cobrar',
      where: 'company_id = ? AND estado = ?',
      whereArgs: [companyId, 'pendiente'],
    );

    double alDia = 0;
    double vencido30 = 0;
    double vencido60 = 0;
    double vencido90 = 0;
    double vencidoMas90 = 0;

    for (final cuenta in cuentas) {
      final fechaVencimiento = DateTime.parse(cuenta['fecha'] as String);
      final saldo = (cuenta['saldo'] as num).toDouble();
      final diasVencidos = hoy.difference(fechaVencimiento).inDays;

      if (diasVencidos <= 0) {
        alDia += saldo;
      } else if (diasVencidos <= 30) {
        vencido30 += saldo;
      } else if (diasVencidos <= 60) {
        vencido60 += saldo;
      } else if (diasVencidos <= 90) {
        vencido90 += saldo;
      } else {
        vencidoMas90 += saldo;
      }
    }

    return {
      'al_dia': alDia,
      'vencido_30': vencido30,
      'vencido_60': vencido60,
      'vencido_90': vencido90,
      'vencido_mas_90': vencidoMas90,
      'total': alDia + vencido30 + vencido60 + vencido90 + vencidoMas90,
    };
  }

  /// Encola un registro para sincronización con el Control Center
  /// Esta función es atómica y no debe fallar la transacción principal
  Future<void> enqueueSync({
    required String table,
    required String recordId,
    required String action,
    required String payload,
  }) async {
    try {
      final db = await instance.database;
      await db.insert('control_center_sync_queue', {
        'table_name': table,
        'record_id': recordId,
        'action': action,
        'payload': payload,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // No lanzar excepción - la sincronización es secundaria
      debugPrint('Error en enqueueSync: $e');
    }
  }
}
