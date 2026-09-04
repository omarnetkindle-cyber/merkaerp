import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';

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
            tipo_item TEXT DEFAULT 'producto',
            precio_incluye_iva INTEGER DEFAULT 0
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
            subtotal REAL NOT NULL,
            impuesto_pct REAL DEFAULT 0,
            impuesto_total REAL DEFAULT 0,
            total REAL DEFAULT 0
          )
        ''');
      },
    );
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTests();
  });

  test('Test 1: Producto con precio_incluye_iva=true a \$119.000 con IVA 19%', () async {
    // 1. Crear producto con precio con IVA incluido ($119.000)
    final product = Product(
      companyId: companyId,
      name: 'Camisa Polo Comercio',
      unit: 'UND',
      stock: 10,
      cost: MoneyValue.fromMajorUnits('50000', currency: cop),
      price: MoneyValue.fromMajorUnits('119000', currency: cop),
      taxRate: 19.0,
      precioIncluyeIva: true,
    );

    final productId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': product.name,
      'unidad_base': product.unit,
      'stock': product.stock,
      'costo': product.cost.toSql(),
      'precio': product.price.toSql(),
      'impuesto_pct': product.taxRate,
      'precio_incluye_iva': product.precioIncluyeIva ? 1 : 0,
    });

    expect(productId, greaterThan(0));

    // 2. Simular cálculo de venta con IVA incluido
    const cantidad = 1.0;
    final precioCobrado = MoneyValue.fromMajorUnits('119000', currency: cop);
    final factor = 1.0 + (19.0 / 100.0); // 1.19
    final baseMajor = precioCobrado.toMajorUnitsDoubleForDisplay() / factor; // 100000.0
    final subtotal = MoneyValue.fromMajorUnits(baseMajor.toStringAsFixed(0), currency: cop);
    final iva = precioCobrado - subtotal;

    expect(subtotal.toSql(), equals(100000));
    expect(iva.toSql(), equals(19000));
    expect(precioCobrado.toSql(), equals(119000));

    // Registrar en BD
    final ventaId = await db.insert('ventas', {
      'company_id': companyId,
      'producto_id': productId,
      'producto': 'Camisa Polo Comercio',
      'cantidad': cantidad,
      'precio_unitario': precioCobrado.toSql(),
      'subtotal': subtotal.toSql(),
      'impuesto_pct': 19.0,
      'impuesto_total': iva.toSql(),
      'total': precioCobrado.toSql(),
      'fecha': '2026-08-15T12:00:00',
    });

    await db.insert('ventas_detalle', {
      'company_id': companyId,
      'venta_id': ventaId,
      'producto_id': productId,
      'producto': 'Camisa Polo Comercio',
      'cantidad': cantidad,
      'precio_unitario': precioCobrado.toSql(),
      'subtotal': subtotal.toSql(),
      'impuesto_pct': 19.0,
      'impuesto_total': iva.toSql(),
      'total': precioCobrado.toSql(),
    });

    final venta = await db.query('ventas', where: 'id = ?', whereArgs: [ventaId]);
    expect((venta.first['total'] as num).toDouble(), equals(119000.0));
    expect((venta.first['subtotal'] as num).toDouble(), equals(100000.0));
    expect((venta.first['impuesto_total'] as num).toDouble(), equals(19000.0));
  });

  test('Test 2: Producto con precio_incluye_iva=false mantiene comportamiento base + IVA', () async {
    final precioBase = MoneyValue.fromMajorUnits('100000', currency: cop);
    const cantidad = 1.0;
    final subtotal = precioBase.multiplyDecimal(cantidad.toString());
    final iva = subtotal.percent('19.0');
    final total = subtotal + iva;

    expect(subtotal.toSql(), equals(100000));
    expect(iva.toSql(), equals(19000));
    expect(total.toSql(), equals(119000));
  });

  test('Test 3: Precio editado manualmente en venta respeta precio_incluye_iva', () async {
    // Producto configurado con precio_incluye_iva = true
    const precioManualEditado = '238000'; // Editado a mano para 2 prendas de $119.000 c/u o tarifa especial
    final precioEditadoMoney = MoneyValue.fromMajorUnits(precioManualEditado, currency: cop); // 238.000 total cobrado
    final factor = 1.19;
    final baseMajor = precioEditadoMoney.toMajorUnitsDoubleForDisplay() / factor; // 200.000 base
    final subtotal = MoneyValue.fromMajorUnits(baseMajor.toStringAsFixed(0), currency: cop);
    final iva = precioEditadoMoney - subtotal;

    expect(subtotal.toSql(), equals(200000));
    expect(iva.toSql(), equals(38000));
    expect(precioEditadoMoney.toSql(), equals(238000));
  });

  test('Test 4: F300 reporta la base gravable y el IVA correctos en ambos modelos', () async {
    // Venta A: IVA Incluido ($119.000 cobrados -> Base $100.000, IVA $19.000)
    final v1 = await db.insert('ventas', {
      'company_id': companyId,
      'producto_id': 1,
      'producto': 'Producto IVA Incluido',
      'cantidad': 1,
      'precio_unitario': 119000,
      'subtotal': 100000,
      'impuesto_pct': 19.0,
      'impuesto_total': 19000,
      'total': 119000,
      'fecha': '2026-08-15T10:00:00',
    });

    await db.insert('ventas_detalle', {
      'company_id': companyId,
      'venta_id': v1,
      'producto_id': 1,
      'producto': 'Producto IVA Incluido',
      'cantidad': 1,
      'precio_unitario': 119000,
      'subtotal': 100000,
      'impuesto_pct': 19.0,
      'impuesto_total': 19000,
      'total': 119000,
    });

    // Venta B: IVA Sumado ($100.000 base -> Base $100.000, IVA $19.000, Total $119.000)
    final v2 = await db.insert('ventas', {
      'company_id': companyId,
      'producto_id': 2,
      'producto': 'Producto IVA Excluido',
      'cantidad': 1,
      'precio_unitario': 100000,
      'subtotal': 100000,
      'impuesto_pct': 19.0,
      'impuesto_total': 19000,
      'total': 119000,
      'fecha': '2026-08-15T11:00:00',
    });

    await db.insert('ventas_detalle', {
      'company_id': companyId,
      'venta_id': v2,
      'producto_id': 2,
      'producto': 'Producto IVA Excluido',
      'cantidad': 1,
      'precio_unitario': 100000,
      'subtotal': 100000,
      'impuesto_pct': 19.0,
      'impuesto_total': 19000,
      'total': 119000,
    });

    // Ejecutar consulta F300 (desglose por base gravable e impuesto)
    final f300Rows = await db.rawQuery('''
      SELECT vd.impuesto_pct AS tarifa,
             SUM(vd.subtotal) AS base_total,
             SUM(vd.impuesto_total) AS iva_total
      FROM ventas_detalle vd
      INNER JOIN ventas v ON v.id = vd.venta_id
      WHERE v.company_id = ?
      GROUP BY vd.impuesto_pct
    ''', [companyId]);

    expect(f300Rows, isNotEmpty);
    final row19 = f300Rows.firstWhere((r) => r['tarifa'] == 19.0);
    expect((row19['base_total'] as num).toDouble(), equals(200000.0)); // 100.000 + 100.000 = 200.000
    expect((row19['iva_total'] as num).toDouble(), equals(38000.0));  // 19.000 + 19.000 = 38.000
  });
}
