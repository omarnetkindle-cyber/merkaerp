// ============================================================
// currency_service.dart
// Servicio de gestión de monedas y tasas de cambio
// ============================================================

import 'package:sqflite/sqflite.dart';
import 'currency.dart';
import 'exchange_rate.dart';

class CurrencyService {
  static final CurrencyService instance = CurrencyService._internal();


  CurrencyService._internal();

  /// Crea las tablas necesarias para monedas
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_currencies (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        decimal_places INTEGER DEFAULT 2,
        is_default INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS currency_exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        from_currency TEXT NOT NULL,
        to_currency TEXT NOT NULL,
        rate REAL NOT NULL,
        effective_date TEXT NOT NULL,
        expiry_date TEXT,
        source TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(company_id, from_currency, to_currency, effective_date)
      )
    ''');

    // Índices
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rates_company ON currency_exchange_rates(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rates_from ON currency_exchange_rates(from_currency)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rates_to ON currency_exchange_rates(to_currency)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rates_date ON currency_exchange_rates(effective_date)',
    );

    // Insertar monedas comunes
    await _insertCommonCurrencies(db);
  }

  /// Inserta monedas comunes si no existen
  Future<void> _insertCommonCurrencies(Database db) async {
    for (final currency in Currency.commonCurrencies) {
      await db.insert(
        'app_currencies',
        currency.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Obtiene todas las monedas disponibles
  Future<List<Currency>> getAllCurrencies(Database db) async {
    final maps = await db.query('app_currencies');
    return maps.map((map) => Currency.fromMap(map)).toList();
  }

  /// Obtiene la moneda por defecto
  Future<Currency?> getDefaultCurrency(Database db) async {
    final maps = await db.query(
      'app_currencies',
      where: 'is_default = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Currency.fromMap(maps.first);
  }

  /// Establece la moneda por defecto
  Future<void> setDefaultCurrency(Database db, String currencyCode) async {
    await db.update('app_currencies', {'is_default': 0});

    await db.update(
      'app_currencies',
      {'is_default': 1},
      where: 'code = ?',
      whereArgs: [currencyCode],
    );
  }

  /// Registra una tasa de cambio
  Future<int> registerExchangeRate(Database db, ExchangeRate rate) async {
    final id = await db.insert('currency_exchange_rates', rate.toMap());
    return id;
  }

  /// Obtiene la tasa de cambio vigente entre dos monedas
  Future<ExchangeRate?> getExchangeRate(
    Database db,
    int companyId,
    String fromCurrency,
    String toCurrency,
  ) async {
    final now = DateTime.now().toIso8601String();

    final maps = await db.query(
      'currency_exchange_rates',
      where:
          'company_id = ? AND from_currency = ? AND to_currency = ? AND effective_date <= ? AND (expiry_date IS NULL OR expiry_date > ?)',
      whereArgs: [companyId, fromCurrency, toCurrency, now, now],
      orderBy: 'effective_date DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ExchangeRate.fromMap(maps.first);
  }

  /// Obtiene todas las tasas de cambio de una empresa
  Future<List<ExchangeRate>> getExchangeRatesByCompany(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'currency_exchange_rates',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'effective_date DESC',
    );

    return maps.map((map) => ExchangeRate.fromMap(map)).toList();
  }

  /// Las tasas automáticas se obtienen exclusivamente mediante la fuente
  /// configurada por la empresa en Centro de Integraciones. Este método legado
  /// se conserva por compatibilidad, pero no selecciona proveedores por cuenta
  /// propia ni inventa tasas.
  Future<bool> updateRatesFromAPI(
    Database db,
    int companyId,
    String baseCurrency,
  ) async {
    return false;
  }

  /// Convierte un monto entre monedas
  Future<double?> convertAmount(
    Database db,
    int companyId,
    double amount,
    String fromCurrency,
    String toCurrency,
  ) async {
    if (fromCurrency == toCurrency) return amount;

    final rate = await getExchangeRate(db, companyId, fromCurrency, toCurrency);
    if (rate == null) return null;

    return rate.convert(amount);
  }

  /// Obtiene historial de tasas de cambio
  Future<List<ExchangeRate>> getRateHistory(
    Database db,
    int companyId,
    String fromCurrency,
    String toCurrency, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String where = 'company_id = ? AND from_currency = ? AND to_currency = ?';
    final whereArgs = [companyId, fromCurrency, toCurrency];

    if (startDate != null) {
      where += ' AND effective_date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND effective_date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final maps = await db.query(
      'currency_exchange_rates',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'effective_date DESC',
    );

    return maps.map((map) => ExchangeRate.fromMap(map)).toList();
  }

  /// Elimina tasas de cambio expiradas
  Future<int> deleteExpiredRates(Database db, int companyId) async {
    final now = DateTime.now().toIso8601String();

    final result = await db.delete(
      'currency_exchange_rates',
      where: 'company_id = ? AND expiry_date < ?',
      whereArgs: [companyId, now],
    );

    return result;
  }

  /// Actualiza una tasa de cambio manualmente
  Future<void> updateExchangeRate(Database db, ExchangeRate rate) async {
    await db.update(
      'currency_exchange_rates',
      rate.toMap(),
      where: 'id = ?',
      whereArgs: [rate.id],
    );
  }

  /// Obtiene configuración de moneda de una empresa
  Future<Map<String, dynamic>?> getCompanyCurrencyConfig(
    Database db,
    int companyId,
  ) async {
    final configResult = await db.query(
      'company_settings',
      where: 'company_id = ? AND setting_key = ?',
      whereArgs: [companyId, 'base_currency'],
    );

    if (configResult.isEmpty) return null;

    return {
      'base_currency': configResult.first['setting_value'],
      'default_currency': await getDefaultCurrency(db),
    };
  }

  /// Establece la moneda base de una empresa
  Future<void> setCompanyBaseCurrency(
    Database db,
    int companyId,
    String currencyCode,
  ) async {
    await db.insert('company_settings', {
      'company_id': companyId,
      'setting_key': 'base_currency',
      'setting_value': currencyCode,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Formatea un monto con el símbolo de moneda
  Future<String> formatAmount(
    Database db,
    double amount,
    String currencyCode,
  ) async {
    final currencies = await getAllCurrencies(db);
    final currency = currencies.firstWhere(
      (c) => c.code == currencyCode,
      orElse: () => Currency.commonCurrencies.first,
    );

    return currency.format(amount);
  }
}
