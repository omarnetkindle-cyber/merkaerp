import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/crm/database/schema_crm.dart';
import 'package:merka_erp/crm/domain/crm_opportunity_item.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final currency = Currency(
    code: 'COP',
    name: 'Peso colombiano',
    symbol: r'$',
    decimalPlaces: 2,
  );

  test(
    'schema y linea CRM persisten producto, cantidad y total exactos',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE productos (
          id INTEGER PRIMARY KEY,
          company_id INTEGER NOT NULL,
          nombre TEXT NOT NULL
        )
      ''');
      await SchemaCrm.crearTablas(db);
      await db.insert('productos', {
        'id': 10,
        'company_id': 7,
        'nombre': 'Producto terminado',
      });
      await db.insert('crm_opportunities', {
        'id': 'OP-10',
        'company_id': 7,
        'customer_id': 1,
        'customer': 'Cuenta',
        'next_follow_up_at': '2026-08-09T00:00:00.000Z',
      });
      final line = CrmOpportunityItem(
        companyId: 7,
        opportunityId: 'OP-10',
        productId: 10,
        quantity: 2.5,
        unitPrice: MoneyValue.fromMajorUnits('100.00', currency: currency),
      );
      await db.insert('crm_opportunity_items', line.toPersistenceMap());

      final row = (await db.query('crm_opportunity_items')).single;
      final restored = CrmOpportunityItem.fromMap(row, currency: currency);
      expect(restored.quantity, 2.5);
      expect(restored.unitPrice.minorUnits, 10000);
      expect(restored.amount.minorUnits, 25000);
    },
  );

  test(
    'la migracion v84 crea la tabla de lineas de forma idempotente',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
      CREATE TABLE crm_opportunities (
        id TEXT PRIMARY KEY
      )
    ''');
      await DatabaseHelper.instance.migrarDBForTesting(db, 83, 84);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['crm_opportunity_items'],
      );
      expect(tables, hasLength(1));
      await DatabaseHelper.instance.migrarDBForTesting(db, 83, 84);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          ['crm_opportunity_items'],
        ),
        hasLength(1),
      );
    },
  );
}
