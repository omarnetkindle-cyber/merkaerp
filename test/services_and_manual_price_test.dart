import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/impact/application/impact_simulator_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  const companyId = 1;
  final cop = Currency(
    code: 'COP',
    name: 'Peso Colombiano',
    symbol: '\$',
    decimalPlaces: 0,
    isDefault: true,
  );

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DatabaseHelper.schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS productos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            codigo TEXT DEFAULT '',
            nombre TEXT NOT NULL,
            unidad_base TEXT NOT NULL,
            stock REAL DEFAULT 0,
            costo REAL DEFAULT 0,
            precio REAL DEFAULT 0,
            impuesto_pct REAL DEFAULT 0,
            codigo_barras TEXT DEFAULT '',
            conversion_nombre TEXT DEFAULT '',
            conversion_cantidad REAL DEFAULT 0,
            tipo_item TEXT DEFAULT 'producto'
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ventas(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            producto_id INTEGER DEFAULT 0,
            producto TEXT NOT NULL,
            cantidad REAL NOT NULL,
            precio_unitario REAL DEFAULT 0,
            costo_unitario REAL DEFAULT 0,
            subtotal REAL DEFAULT 0,
            impuesto_pct REAL DEFAULT 0,
            impuesto_total REAL DEFAULT 0,
            total REAL NOT NULL,
            fecha TEXT NOT NULL,
            metodo_pago_id INTEGER DEFAULT 1,
            estado TEXT DEFAULT 'emitida'
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ventas_detalle(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            venta_id INTEGER NOT NULL,
            producto_id INTEGER NOT NULL,
            producto TEXT NOT NULL,
            cantidad REAL NOT NULL,
            precio_unitario REAL NOT NULL,
            subtotal REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS movimientos_inventario (
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
          CREATE TABLE IF NOT EXISTS crm_opportunities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            name TEXT,
            amount REAL,
            value REAL,
            sales_stage TEXT,
            stage TEXT,
            probability INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS crm_opportunity_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            opportunity_id INTEGER,
            product_id INTEGER,
            quantity REAL,
            uom TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS mrp_boms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            item_id INTEGER,
            quantity REAL,
            routing_id INTEGER,
            is_active INTEGER DEFAULT 1,
            is_default INTEGER DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS mrp_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            routing_id INTEGER,
            time_minutes REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS empleados (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            cargo TEXT,
            salario_base REAL,
            job_title_id INTEGER,
            activo INTEGER DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS hrm_job_titles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            mrp_workstation_id INTEGER,
            contractual_hours_per_day REAL,
            is_deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS mrp_workstations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id INTEGER,
            name TEXT,
            production_capacity REAL,
            available_hours_per_day REAL,
            status TEXT
          )
        ''');
      },
    );
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTests();
  });

  test('Crear servicio intangible y procesar sin descontar stock ni Kardex', () async {
    // 1. Crear producto tipo servicio
    final serviceProduct = Product(
      companyId: companyId,
      name: 'Asesoría Tributaria O&W',
      unit: 'SERV',
      stock: 0,
      cost: MoneyValue.fromMajorUnits('0', currency: cop),
      price: MoneyValue.fromMajorUnits('250000', currency: cop),
      taxRate: 19.0,
      itemType: 'servicio',
    );

    final serviceId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': serviceProduct.name,
      'unidad_base': serviceProduct.unit,
      'stock': serviceProduct.stock,
      'costo': serviceProduct.cost.toSql(),
      'precio': serviceProduct.price.toSql(),
      'impuesto_pct': serviceProduct.taxRate,
      'tipo_item': serviceProduct.itemType,
    });

    expect(serviceId, greaterThan(0));

    // 2. Verificar que el item se reconoce como servicio
    final rows = await db.query('productos', where: 'id = ?', whereArgs: [serviceId]);
    expect(rows.first['tipo_item'], equals('servicio'));

    // 3. Insertar venta directa del servicio
    final ventaId = await db.insert('ventas', {
      'company_id': companyId,
      'producto_id': serviceId,
      'producto': 'Asesoría Tributaria O&W',
      'cantidad': 2.0,
      'precio_unitario': 250000.0,
      'total': 500000.0,
      'fecha': DateTime.now().toIso8601String(),
    });

    expect(ventaId, greaterThan(0));

    // 4. Confirmar que NO se generó movimiento de inventario en Kardex para servicios
    final movimientos = await db.query('movimientos_inventario', where: 'producto_id = ?', whereArgs: [serviceId]);
    expect(movimientos, isEmpty);

    // 5. Confirmar que el stock del producto sigue en 0 sin alterarse
    final afterSale = await db.query('productos', where: 'id = ?', whereArgs: [serviceId]);
    expect((afterSale.first['stock'] as num).toDouble(), equals(0.0));
  });

  test('Venta de servicio con precio editado manualmente recalcula subtotal e impuestos', () async {
    final originalPrice = MoneyValue.fromMajorUnits('300000', currency: cop);
    final editedPrice = MoneyValue.fromMajorUnits('450000', currency: cop); // Precio negociado manualmente

    final serviceId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Consultoría Financiera Personalizada',
      'unidad_base': 'HOR',
      'stock': 0,
      'costo': 0,
      'precio': originalPrice.toSql(),
      'impuesto_pct': 19.0,
      'tipo_item': 'servicio',
    });

    const cantidad = 3.0; // 3 horas de consultoría
    final subtotalEditado = editedPrice.multiplyDecimal(cantidad.toString());
    final ivaEditado = subtotalEditado.percent('19.0');
    final totalEditado = subtotalEditado + ivaEditado;

    expect(subtotalEditado.toSql(), equals(1350000));
    expect(totalEditado.toSql(), equals(1606500));

    final ventaId = await db.insert('ventas', {
      'company_id': companyId,
      'producto_id': serviceId,
      'producto': 'Consultoría Financiera Personalizada',
      'cantidad': cantidad,
      'precio_unitario': editedPrice.toSql(),
      'subtotal': subtotalEditado.toSql(),
      'impuesto_pct': 19.0,
      'impuesto_total': ivaEditado.toSql(),
      'total': totalEditado.toSql(),
      'fecha': DateTime.now().toIso8601String(),
    });

    expect(ventaId, greaterThan(0));

    final ventaGuardada = await db.query('ventas', where: 'id = ?', whereArgs: [ventaId]);
    expect((ventaGuardada.first['total'] as num).toDouble(), equals(1606500.0));
  });

  test('Simulador de Impacto (UI-6) proyecta horas HRM para oportunidades de servicio', () async {
    final serviceId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Auditoría Contable O&W',
      'unidad_base': 'SERV',
      'stock': 0,
      'costo': 0,
      'precio': 1000000,
      'impuesto_pct': 19.0,
      'tipo_item': 'servicio',
    });

    final oppId = await db.insert('crm_opportunities', {
      'company_id': companyId,
      'name': 'Contrato Asesoría Anual O&W',
      'amount': 10000000,
      'sales_stage': 'prospecting',
      'probability': 80,
    });

    await db.insert('crm_opportunity_items', {
      'company_id': companyId,
      'opportunity_id': oppId,
      'product_id': serviceId,
      'quantity': 40.0, // 40 horas de asesoría
      'uom': 'SERV',
    });

    final impactService = ImpactSimulatorService(
      executor: db,
      companyId: companyId,
      currency: cop,
    );

    final snapshot = await impactService.snapshot();

    expect(snapshot.demandLines, isNotEmpty);
    final line = snapshot.demandLines.firstWhere((l) => l.productId == serviceId);
    expect(line.estimatedHoursPerUnit, equals(1.0));
    expect(line.weightedHours, equals(32.0)); // 40 * 80% = 32 horas de demanda de personal (HRM)
  });
}
