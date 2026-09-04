import 'package:sqflite/sqflite.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../domain/order.dart';
import '../domain/order_line.dart';

class OrderService {
  static final OrderService instance = OrderService._internal();

  OrderService._internal();

  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        order_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        order_date TEXT NOT NULL,
        estimated_delivery_date TEXT,
        actual_delivery_date TEXT,
        subtotal INTEGER NOT NULL,
        tax_amount INTEGER NOT NULL,
        total INTEGER NOT NULL,
        discount_amount INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        notes TEXT,
        delivery_address TEXT,
        contact_phone TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        discount_amount INTEGER DEFAULT 0,
        tax_percentage REAL DEFAULT 0,
        tax_amount INTEGER DEFAULT 0,
        subtotal INTEGER NOT NULL,
        total INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES sales_orders(id),
        FOREIGN KEY (product_id) REFERENCES productos(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_company ON sales_orders(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_customer ON sales_orders(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status ON sales_orders(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_date ON sales_orders(order_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_order_lines_order ON order_lines(order_id)',
    );
  }

  Future<Currency> _currencyFor(Database db, int companyId) {
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  Future<String> generateOrderNumber(Database db, int companyId) async {
    final year = DateTime.now().year;
    final prefix = 'ORD-$year-';
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM sales_orders
      WHERE company_id = ? AND order_number LIKE ?
    ''',
      [companyId, '$prefix%'],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    return '$prefix${(count + 1).toString().padLeft(5, '0')}';
  }

  Future<int> createOrder(Database db, SalesOrder order) {
    return db.insert('sales_orders', order.toMap());
  }

  Future<int> addOrderLine(Database db, OrderLine line) async {
    final id = await db.insert('order_lines', line.toMap());
    await _updateOrderTotals(db, line.orderId);
    return id;
  }

  Future<void> _updateOrderTotals(Database db, int orderId) async {
    final linesResult = await db.query(
      'order_lines',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    if (linesResult.isEmpty) return;

    final currency = await _currencyFor(
      db,
      linesResult.first['company_id'] as int,
    );
    var subtotal = MoneyValue(minorUnits: 0, currency: currency);
    var taxAmount = MoneyValue(minorUnits: 0, currency: currency);
    var discountAmount = MoneyValue(minorUnits: 0, currency: currency);
    for (final lineMap in linesResult) {
      final line = OrderLine.fromMap(lineMap, currency: currency);
      subtotal += line.subtotal;
      taxAmount += line.taxAmount;
      discountAmount += line.discountAmount;
    }
    final total = subtotal - discountAmount + taxAmount;

    await db.update(
      'sales_orders',
      {
        'subtotal': subtotal.toSql(),
        'tax_amount': taxAmount.toSql(),
        'discount_amount': discountAmount.toSql(),
        'total': total.toSql(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<SalesOrder?> getOrderById(Database db, int orderId) async {
    final maps = await db.query(
      'sales_orders',
      where: 'id = ?',
      whereArgs: [orderId],
    );
    if (maps.isEmpty) return null;
    final map = maps.first;
    final currency = await _currencyFor(db, map['company_id'] as int);
    return SalesOrder.fromMap(map, currency: currency);
  }

  Future<List<OrderLine>> getOrderLines(Database db, int orderId) async {
    final maps = await db.query(
      'order_lines',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    if (maps.isEmpty) return [];
    final currency = await _currencyFor(db, maps.first['company_id'] as int);
    return maps
        .map((map) => OrderLine.fromMap(map, currency: currency))
        .toList();
  }

  Future<List<SalesOrder>> getOrdersByCustomer(
    Database db,
    int customerId,
    int companyId,
  ) async {
    final maps = await db.query(
      'sales_orders',
      where: 'customer_id = ? AND company_id = ?',
      whereArgs: [customerId, companyId],
      orderBy: 'order_date DESC',
    );
    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => SalesOrder.fromMap(map, currency: currency))
        .toList();
  }

  Future<List<SalesOrder>> getOrdersByStatus(
    Database db,
    String status,
    int companyId,
  ) async {
    final maps = await db.query(
      'sales_orders',
      where: 'status = ? AND company_id = ?',
      whereArgs: [status, companyId],
      orderBy: 'order_date DESC',
    );
    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => SalesOrder.fromMap(map, currency: currency))
        .toList();
  }

  Future<List<SalesOrder>> getPendingDeliveryOrders(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'sales_orders',
      where: 'status IN (?, ?) AND company_id = ?',
      whereArgs: ['confirmed', 'sent', companyId],
      orderBy: 'estimated_delivery_date ASC',
    );
    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => SalesOrder.fromMap(map, currency: currency))
        .toList();
  }

  Future<List<SalesOrder>> getOverdueOrders(Database db, int companyId) async {
    final now = DateTime.now().toIso8601String();
    final maps = await db.query(
      'sales_orders',
      where:
          'status NOT IN (?, ?, ?) AND company_id = ? AND estimated_delivery_date < ?',
      whereArgs: ['delivered', 'cancelled', 'pending', companyId, now],
      orderBy: 'estimated_delivery_date ASC',
    );
    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => SalesOrder.fromMap(map, currency: currency))
        .toList();
  }

  Future<void> updateOrderStatus(
    Database db,
    int orderId,
    String status,
  ) async {
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status == 'delivered') {
      updates['actual_delivery_date'] = DateTime.now().toIso8601String();
    }
    await db.update(
      'sales_orders',
      updates,
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<bool> reserveStockForOrder(Database db, int orderId) async {
    final order = await getOrderById(db, orderId);
    if (order == null) return false;
    final lines = await getOrderLines(db, orderId);
    for (final line in lines) {
      final productResult = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [line.productId],
      );
      if (productResult.isEmpty) return false;
      final currentStock = (productResult.first['stock'] as num).toDouble();
      if (currentStock < line.quantity) return false;
    }
    return true;
  }

  Future<int?> convertOrderToSale(Database db, int orderId) async {
    final order = await getOrderById(db, orderId);
    if (order == null || order.status != 'confirmed') return null;
    final taxPercentage = order.subtotal.minorUnits == 0
        ? 0.0
        : order.taxAmount.minorUnits * 100 / order.subtotal.minorUnits;
    final saleId = await db.insert('ventas', {
      'company_id': order.companyId,
      'producto': 'Pedido ${order.orderNumber}',
      'cantidad': 1,
      'precio_unitario': order.total.toSql(),
      'subtotal': order.subtotal.toSql(),
      'impuesto_pct': taxPercentage,
      'impuesto_total': order.taxAmount.toSql(),
      'total': order.total.toSql(),
      'fecha': DateTime.now().toIso8601String(),
      'estado': 'emitida',
      'metodo_pago_id': 1,
    });
    await updateOrderStatus(db, orderId, 'delivered');
    return saleId;
  }

  Future<void> cancelOrder(Database db, int orderId, String? reason) {
    return db
        .update(
          'sales_orders',
          {
            'status': 'cancelled',
            'notes': reason,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        )
        .then((_) {});
  }

  Future<void> removeOrderLine(Database db, int lineId) async {
    final maps = await db.query(
      'order_lines',
      where: 'id = ?',
      whereArgs: [lineId],
    );
    if (maps.isEmpty) return;
    final currency = await _currencyFor(db, maps.first['company_id'] as int);
    final line = OrderLine.fromMap(maps.first, currency: currency);
    await db.delete('order_lines', where: 'id = ?', whereArgs: [lineId]);
    await _updateOrderTotals(db, line.orderId);
  }

  Future<Map<String, dynamic>> getOrderStatistics(
    Database db,
    int companyId,
  ) async {
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as total FROM sales_orders WHERE company_id = ?',
      [companyId],
    );
    final pendingResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sales_orders WHERE company_id = ? AND status = 'pending'",
      [companyId],
    );
    final confirmedResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sales_orders WHERE company_id = ? AND status = 'confirmed'",
      [companyId],
    );
    final deliveredResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sales_orders WHERE company_id = ? AND status = 'delivered'",
      [companyId],
    );
    final totalValueResult = await db.rawQuery(
      "SELECT SUM(total) as value FROM sales_orders WHERE company_id = ? AND status != 'cancelled'",
      [companyId],
    );
    final currency = await _currencyFor(db, companyId);
    return {
      'total_orders': Sqflite.firstIntValue(totalResult) ?? 0,
      'pending_orders': Sqflite.firstIntValue(pendingResult) ?? 0,
      'confirmed_orders': Sqflite.firstIntValue(confirmedResult) ?? 0,
      'delivered_orders': Sqflite.firstIntValue(deliveredResult) ?? 0,
      'total_value': MoneyValue.fromSql(
        totalValueResult.first['value'],
        currency: currency,
        nullableAsZero: true,
      ),
    };
  }
}
