import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/inventory/application/advanced_inventory_service.dart';
import 'package:merka_erp/inventory/application/inventory_control_service.dart';
import 'package:merka_erp/inventory/application/price_history_service.dart';
import 'package:merka_erp/inventory/domain/inventory_lot.dart';
import 'package:merka_erp/inventory/domain/price_history.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_money.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('inventario heredado calcula costos exactos en MoneyValue', () {
    final product = Product(
      name: 'Producto',
      unit: 'und',
      stock: 3,
      cost: testMoney('10.01'),
      price: testMoney('15.00'),
      taxRate: 19,
    );
    const service = InventoryControlService();
    final report = service.analyze([product]);
    expect(report.costValue, testMoney('30.03'));
    expect(report.saleValue, testMoney('45.00'));
    expect(
      service.weightedAverageCost(
        currentStock: 10,
        currentCost: testMoney('10.00'),
        incomingQuantity: 10,
        incomingCost: testMoney('14.00'),
      ),
      testMoney('12.00'),
    );
  });

  test('lotes e historial rehidratan dinero INTEGER con moneda resuelta', () {
    final lot = InventoryLot(
      companyId: 1,
      productId: 2,
      lotNumber: 'LOT-1',
      manufacturingDate: DateTime(2026, 1, 1),
      expirationDate: DateTime(2027, 1, 1),
      initialQuantity: 5,
      currentQuantity: 5,
      unitCost: testMoney('7.25'),
      createdAt: DateTime(2026, 1, 1),
    );
    final restoredLot = InventoryLot.fromMap(lot.toMap(), currency: testCop);
    expect(restoredLot.unitCost, testMoney('7.25'));

    final history = PriceHistory(
      companyId: 1,
      productId: 2,
      productName: 'Producto',
      oldPrice: testMoney('10.00'),
      newPrice: testMoney('12.50'),
      percentageChange: 25,
      changeReason: 'manual_update',
      changedAt: DateTime(2026, 1, 1),
    );
    final restoredHistory = PriceHistory.fromMap(
      history.toMap(),
      currency: testCop,
    );
    expect(restoredHistory.newPrice, testMoney('12.50'));
  });

  test('servicios de lotes e historial declaran costos como INTEGER', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await AdvancedInventoryService.instance.createTables(db);
    await PriceHistoryService.instance.createTables(db);

    for (final table in ['inventory_lots', 'price_history']) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final moneyColumns = columns
          .where(
            (column) => [
              'unit_cost',
              'old_price',
              'new_price',
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
  });
}
