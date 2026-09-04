import 'package:sqflite/sqflite.dart';

import 'currency.dart';

/// Resolves the currency before a commercial SQLite row becomes MoneyValue.
class MoneyCurrencyResolver {
  const MoneyCurrencyResolver._();

  static Future<Currency> resolve(
    DatabaseExecutor db, {
    int? companyId,
    String? explicitCode,
  }) async {
    var code = explicitCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) {
      if (companyId != null) {
        final companies = await db.query(
          'companies',
          columns: ['currency'],
          where: 'id = ?',
          whereArgs: [companyId],
          limit: 1,
        );
        if (companies.isNotEmpty) {
          code = companies.first['currency']?.toString().trim().toUpperCase();
        }
      }

      if (code == null || code.isEmpty) {
        final legacy = await db.query(
          'empresa_config',
          columns: ['moneda'],
          where: 'id = 1',
          limit: 1,
        );
        if (legacy.isNotEmpty) {
          code = legacy.first['moneda']?.toString().trim().toUpperCase();
        }
      }
    }

    if (code == null || code.isEmpty) {
      throw StateError(
        'No configured currency exists for the commercial money value',
      );
    }

    final currencies = await db.query(
      'app_currencies',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (currencies.isEmpty) {
      throw StateError('Currency $code has no configured decimal scale');
    }
    return Currency.fromMap(currencies.first);
  }
}
