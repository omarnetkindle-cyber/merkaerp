import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTests();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTests();
  });

  test('lee y escribe company_settings con el esquema versionado', () async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final service = CurrencyService.instance;

    await service.setCompanyBaseCurrency(db, companyId, 'COP');
    final config = await service.getCompanyCurrencyConfig(db, companyId);

    expect(config?['base_currency'], 'COP');
    final rows = await db.query(
      'company_settings',
      where: 'company_id = ? AND setting_key = ?',
      whereArgs: [companyId, 'base_currency'],
    );
    expect(rows.single['updated_at'], isNotNull);
  });
}
