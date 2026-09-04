import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sales/application/order_service.dart';
import 'package:merka_erp/sales/application/quote_service.dart';
import 'package:merka_erp/sales/domain/order.dart';
import 'package:merka_erp/sales/domain/order_line.dart';
import 'package:merka_erp/sales/domain/quote.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_money.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('pedidos y cotizaciones calculan y rehidratan importes exactos', () {
    final line = OrderLine.calculate(
      companyId: 1,
      orderId: 2,
      productId: 3,
      productName: 'Producto',
      quantity: 2,
      unitPrice: testMoney('10.01'),
      unitCost: testMoney('5.00'),
      discountAmount: testMoney('0.01'),
      taxPercentage: 19,
    );

    expect(line.subtotal, testMoney('20.02'));
    expect(line.taxAmount, testMoney('3.80'));
    expect(line.total, testMoney('23.81'));

    final order = SalesOrder(
      companyId: 1,
      orderNumber: 'ORD-1',
      customerName: 'Cliente',
      orderDate: DateTime(2026, 8, 8),
      subtotal: line.subtotal,
      taxAmount: line.taxAmount,
      total: line.total,
      discountAmount: line.discountAmount,
      createdAt: DateTime(2026, 8, 8),
    );
    final restoredOrder = SalesOrder.fromMap(order.toMap(), currency: testCop);
    expect(restoredOrder.total, testMoney('23.81'));

    final quote = SalesQuote(
      companyId: 1,
      quoteNumber: 'COT-1',
      customerName: 'Cliente',
      quoteDate: DateTime(2026, 8, 8),
      subtotal: line.subtotal,
      taxAmount: line.taxAmount,
      total: line.total,
      discountAmount: line.discountAmount,
      createdAt: DateTime(2026, 8, 8),
    );
    final restoredQuote = SalesQuote.fromMap(quote.toMap(), currency: testCop);
    expect(restoredQuote.total, testMoney('23.81'));
  });

  test(
    'las tablas de pedidos y cotizaciones declaran dinero como INTEGER',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await OrderService.instance.createTables(db);
      await QuoteService.instance.createTables(db);

      for (final table in [
        'sales_orders',
        'order_lines',
        'sales_quotes',
        'quote_lines',
      ]) {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final moneyColumns = columns
            .where(
              (column) => [
                'subtotal',
                'tax_amount',
                'total',
                'discount_amount',
                'unit_price',
                'unit_cost',
              ].contains(column['name']),
            )
            .toList();
        expect(moneyColumns, isNotEmpty, reason: table);
        expect(
          moneyColumns.every((column) => column['type'] == 'INTEGER'),
          isTrue,
          reason: table,
        );
      }
    },
  );
}
