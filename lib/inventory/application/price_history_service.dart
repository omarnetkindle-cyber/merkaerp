// ============================================================
// price_history_service.dart
// Servicio de gestión de historial de precios
// ============================================================

import 'package:sqflite/sqflite.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../domain/price_history.dart';

class PriceHistoryService {
  static final PriceHistoryService instance = PriceHistoryService._internal();

  PriceHistoryService._internal();

  Future<Currency> _currencyFor(Database db, int companyId) {
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  /// Crea las tablas necesarias para historial de precios
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        old_price INTEGER NOT NULL,
        new_price INTEGER NOT NULL,
        percentage_change REAL NOT NULL,
        change_reason TEXT NOT NULL,
        changed_by TEXT,
        changed_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES productos(id)
      )
    ''');

    // Índices
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_price_product ON price_history(product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_price_company ON price_history(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_price_date ON price_history(changed_at)',
    );
  }

  /// Registra un cambio de precio
  Future<int> recordPriceChange(
    Database db,
    int companyId,
    int productId,
    String productName,
    MoneyValue oldPrice,
    MoneyValue newPrice,
    String changeReason, {
    String? changedBy,
  }) async {
    final percentageChange = oldPrice.minorUnits > 0
        ? ((newPrice.minorUnits - oldPrice.minorUnits) * 100) /
              oldPrice.minorUnits
        : 0.0;

    final history = PriceHistory(
      companyId: companyId,
      productId: productId,
      productName: productName,
      oldPrice: oldPrice,
      newPrice: newPrice,
      percentageChange: percentageChange,
      changeReason: changeReason,
      changedBy: changedBy,
      changedAt: DateTime.now(),
    );

    final id = await db.insert('price_history', history.toMap());
    return id;
  }

  /// Obtiene el historial de precios de un producto
  Future<List<PriceHistory>> getProductPriceHistory(
    Database db,
    int productId,
  ) async {
    final maps = await db.query(
      'price_history',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'changed_at DESC',
    );

    final rows = maps;
    if (rows.isEmpty) return [];
    final currency = await _currencyFor(db, rows.first['company_id'] as int);
    return rows
        .map((map) => PriceHistory.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene el historial de precios de una empresa
  Future<List<PriceHistory>> getCompanyPriceHistory(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'price_history',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'changed_at DESC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => PriceHistory.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene cambios de precio en un rango de fechas
  Future<List<PriceHistory>> getPriceHistoryByDateRange(
    Database db,
    int companyId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final maps = await db.query(
      'price_history',
      where: 'company_id = ? AND changed_at >= ? AND changed_at <= ?',
      whereArgs: [
        companyId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'changed_at DESC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => PriceHistory.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene productos con cambios de precio recientes
  Future<List<Map<String, dynamic>>> getRecentPriceChanges(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));

    final maps = await db.rawQuery(
      '''
      SELECT 
        product_id,
        product_name,
        COUNT(*) as change_count,
        AVG(ABS(percentage_change)) as avg_change,
        MAX(new_price) as current_price,
        MAX(changed_at) as last_change
      FROM price_history
      WHERE company_id = ? AND changed_at >= ?
      GROUP BY product_id
      ORDER BY change_count DESC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    final currency = await _currencyFor(db, companyId);
    return maps.map((map) {
      final copy = Map<String, dynamic>.from(map);
      copy['current_price'] = MoneyValue.fromSql(
        copy['current_price'],
        currency: currency,
        nullableAsZero: true,
      );
      return copy;
    }).toList();
  }

  /// Obtiene productos con aumentos de precio
  Future<List<PriceHistory>> getPriceIncreases(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));

    final maps = await db.query(
      'price_history',
      where: 'company_id = ? AND new_price > old_price AND changed_at >= ?',
      whereArgs: [companyId, startDate.toIso8601String()],
      orderBy: 'percentage_change DESC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => PriceHistory.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene productos con disminuciones de precio
  Future<List<PriceHistory>> getPriceDecreases(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));

    final maps = await db.query(
      'price_history',
      where: 'company_id = ? AND new_price < old_price AND changed_at >= ?',
      whereArgs: [companyId, startDate.toIso8601String()],
      orderBy: 'percentage_change ASC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => PriceHistory.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene el precio anterior de un producto
  Future<MoneyValue?> getPreviousPrice(Database db, int productId) async {
    final maps = await db.query(
      'price_history',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'changed_at DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final companyId = maps.first['company_id'] as int;
    final currency = await _currencyFor(db, companyId);
    final history = PriceHistory.fromMap(maps.first, currency: currency);
    return history.oldPrice;
  }

  /// Obtiene estadísticas de cambios de precio
  Future<Map<String, dynamic>> getPriceChangeStatistics(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));

    final totalChangesResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM price_history 
      WHERE company_id = ? AND changed_at >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    final increasesResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM price_history 
      WHERE company_id = ? AND new_price > old_price AND changed_at >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    final decreasesResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM price_history 
      WHERE company_id = ? AND new_price < old_price AND changed_at >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    final avgChangeResult = await db.rawQuery(
      '''
      SELECT AVG(ABS(percentage_change)) as avg_change 
      FROM price_history 
      WHERE company_id = ? AND changed_at >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    return {
      'total_changes': Sqflite.firstIntValue(totalChangesResult) ?? 0,
      'increases': Sqflite.firstIntValue(increasesResult) ?? 0,
      'decreases': Sqflite.firstIntValue(decreasesResult) ?? 0,
      'average_change':
          (avgChangeResult.first['avg_change'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Limpia historial de precios antiguo
  Future<int> cleanOldHistory(
    Database db,
    int companyId, {
    int monthsToKeep = 12,
  }) async {
    final cutoffDate = DateTime.now().subtract(
      Duration(days: 30 * monthsToKeep),
    );

    final result = await db.delete(
      'price_history',
      where: 'company_id = ? AND changed_at < ?',
      whereArgs: [companyId, cutoffDate.toIso8601String()],
    );

    return result;
  }

  /// Elimina historial de precios de un producto
  Future<void> deleteProductHistory(Database db, int productId) async {
    await db.delete(
      'price_history',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }
}
