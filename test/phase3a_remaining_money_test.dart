import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/payments/payment_service.dart';
import 'package:merka_erp/enterprise/domain/final_enterprise_contexts.dart';
import 'package:merka_erp/services/enterprise_feature_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_money.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('bloque periférico conserva dinero exacto en dominio y API', () {
    final line = EnterpriseLineItem(
      productoId: 1,
      producto: 'Servicio',
      cantidad: 3,
      precioUnitario: testMoney('10.01'),
    );
    expect(line.subtotal, testMoney('30.03'));

    final asset = FixedAsset(
      id: 'asset-1',
      name: 'Equipo',
      cost: testMoney('120.00'),
      usefulLifeMonths: 12,
      acquiredAt: DateTime(2026, 1, 1),
      accumulatedDepreciation: testMoney('0.00'),
      fiscalDepreciation: testMoney('0.00'),
    );
    expect(asset.depreciate().accumulatedDepreciation, testMoney('10.00'));
    expect(line.precioUnitario.toSql(), 1001);
  });

  test('pasarela persiste importes como INTEGER', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await PaymentService.instance.createTables(db);
    final columns = await db.rawQuery(
      'PRAGMA table_info(payment_transactions)',
    );
    final amount = columns.firstWhere((row) => row['name'] == 'amount');
    expect(amount['type'], 'INTEGER');
  });
}
