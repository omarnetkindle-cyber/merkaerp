// ============================================================
// financial_consolidation.dart
// Servicio de consolidación financiera multi-empresa
// ============================================================

import 'package:sqflite/sqflite.dart';

import '../currency/currency.dart';
import '../currency/money_currency_resolver.dart';
import '../currency/money_value.dart';

class FinancialConsolidationService {
  static final FinancialConsolidationService instance =
      FinancialConsolidationService._internal();

  FinancialConsolidationService._internal();

  /// Obtiene el consolidado financiero de múltiples empresas
  Future<Map<String, dynamic>> getConsolidatedFinancials(
    Database db,
    List<int> companyIds, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (companyIds.isEmpty) {
      return _emptyConsolidation();
    }

    final effectiveStartDate =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final effectiveEndDate = endDate ?? DateTime.now();

    // Ventas consolidadas
    final currency = await _resolveCurrency(db, companyIds);
    final consolidatedSales = await _getConsolidatedSales(
      db,
      companyIds,
      effectiveStartDate,
      effectiveEndDate,
    );

    // Gastos consolidados
    final consolidatedExpenses = await _getConsolidatedExpenses(
      db,
      companyIds,
      effectiveStartDate,
      effectiveEndDate,
    );

    // Inventario consolidado
    final consolidatedInventory = await _getConsolidatedInventory(
      db,
      companyIds,
    );

    // Cuentas por cobrar consolidadas
    final consolidatedReceivables = await _getConsolidatedReceivables(
      db,
      companyIds,
    );

    // Cuentas por pagar consolidadas
    final consolidatedPayables = await _getConsolidatedPayables(db, companyIds);

    final totalRevenue = MoneyValue.fromSql(
      (consolidatedSales['total'] as Map)['minor_units'],
      currency: currency,
    );
    final totalExpenses = MoneyValue.fromSql(
      (consolidatedExpenses['total'] as Map)['minor_units'],
      currency: currency,
    );
    final totalProfit = totalRevenue - totalExpenses;

    return {
      'period': {
        'start': effectiveStartDate.toIso8601String(),
        'end': effectiveEndDate.toIso8601String(),
      },
      'companies': companyIds.length,
      'sales': consolidatedSales,
      'expenses': consolidatedExpenses,
      'inventory': consolidatedInventory,
      'accounts_receivable': consolidatedReceivables,
      'accounts_payable': consolidatedPayables,
      'profit': totalProfit.toWireMap(),
      'profit_margin': totalRevenue.minorUnits > 0
          ? (totalProfit.minorUnits / totalRevenue.minorUnits) * 100
          : 0,
      'net_cash_position':
          (MoneyValue.fromSql(
                    (consolidatedInventory['total_value']
                        as Map)['minor_units'],
                    currency: currency,
                  ) +
                  MoneyValue.fromSql(
                    (consolidatedReceivables['total'] as Map)['minor_units'],
                    currency: currency,
                  ) -
                  MoneyValue.fromSql(
                    (consolidatedPayables['total'] as Map)['minor_units'],
                    currency: currency,
                  ))
              .toWireMap(),
    };
  }

  /// Obtiene ventas consolidadas
  Future<Map<String, dynamic>> _getConsolidatedSales(
    Database db,
    List<int> companyIds,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final placeholders = List.filled(companyIds.length, '?').join(',');

    final result = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(total) as total,
        SUM(subtotal) as subtotal,
        SUM(impuesto_total) as tax,
        AVG(total) as average_ticket
      FROM ventas
      WHERE company_id IN ($placeholders) 
        AND fecha >= ? 
        AND fecha <= ? 
        AND estado = 'emitida'
    ''',
      [...companyIds, startDate.toIso8601String(), endDate.toIso8601String()],
    );
    final currency = await _currencyForQuery(db, companyIds);
    final elimination = await _getApprovedEliminations(
      db,
      companyIds,
      'sales_expenses',
      currency,
    );
    final total = MoneyValue.fromSql(
      result.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final subtotal = MoneyValue.fromSql(
      result.first['subtotal'],
      currency: currency,
      nullableAsZero: true,
    );
    final tax = MoneyValue.fromSql(
      result.first['tax'],
      currency: currency,
      nullableAsZero: true,
    );
    final averageTicket = MoneyValue.fromSql(
      (result.first['average_ticket'] as num?)?.round(),
      currency: currency,
      nullableAsZero: true,
    );

    return {
      'count': Sqflite.firstIntValue(result) ?? 0,
      'total': (total - elimination).toWireMap(),
      'subtotal': (subtotal - elimination).toWireMap(),
      'tax': tax.toWireMap(),
      'average_ticket': averageTicket.toWireMap(),
      'eliminated_intercompany': elimination.toWireMap(),
    };
  }

  /// Obtiene gastos consolidados
  Future<Map<String, dynamic>> _getConsolidatedExpenses(
    Database db,
    List<int> companyIds,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (!await _tableExists(db, 'gastos')) {
      final currency = await _currencyForQuery(db, companyIds);
      return {
        'count': 0,
        'total': MoneyValue(minorUnits: 0, currency: currency).toWireMap(),
        'eliminated_intercompany': MoneyValue(
          minorUnits: 0,
          currency: currency,
        ).toWireMap(),
      };
    }
    final placeholders = List.filled(companyIds.length, '?').join(',');

    final result = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(monto) as total
      FROM gastos
      WHERE company_id IN ($placeholders) 
        AND fecha >= ? 
        AND fecha <= ?
    ''',
      [...companyIds, startDate.toIso8601String(), endDate.toIso8601String()],
    );
    final currency = await _currencyForQuery(db, companyIds);
    final elimination = await _getApprovedEliminations(
      db,
      companyIds,
      'sales_expenses',
      currency,
    );
    final total = MoneyValue.fromSql(
      result.first['total'],
      currency: currency,
      nullableAsZero: true,
    );

    return {
      'count': Sqflite.firstIntValue(result) ?? 0,
      'total': (total - elimination).toWireMap(),
      'eliminated_intercompany': elimination.toWireMap(),
    };
  }

  /// Obtiene inventario consolidado
  Future<Map<String, dynamic>> _getConsolidatedInventory(
    Database db,
    List<int> companyIds,
  ) async {
    final placeholders = List.filled(companyIds.length, '?').join(',');

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_products,
        SUM(stock) as total_stock,
        SUM(stock * costo) as total_value
      FROM productos
      WHERE company_id IN ($placeholders)
    ''', companyIds);

    return {
      'total_products': Sqflite.firstIntValue(result) ?? 0,
      'total_stock': (result.first['total_stock'] as num?)?.toDouble() ?? 0,
      'total_value': _wire(
        result.first['total_value'],
        await _currencyForQuery(db, companyIds),
      ),
    };
  }

  /// Obtiene cuentas por cobrar consolidadas
  Future<Map<String, dynamic>> _getConsolidatedReceivables(
    Database db,
    List<int> companyIds,
  ) async {
    if (!await _tableExists(db, 'cuentas_por_cobrar')) {
      final currency = await _currencyForQuery(db, companyIds);
      return {
        'count': 0,
        'total': MoneyValue(minorUnits: 0, currency: currency).toWireMap(),
        'eliminated_intercompany': MoneyValue(
          minorUnits: 0,
          currency: currency,
        ).toWireMap(),
      };
    }
    final placeholders = List.filled(companyIds.length, '?').join(',');

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(saldo) as total
      FROM cuentas_por_cobrar
      WHERE company_id IN ($placeholders) AND estado = 'pendiente'
    ''', companyIds);

    final currency = await _currencyForQuery(db, companyIds);
    final elimination = await _getApprovedEliminations(
      db,
      companyIds,
      'receivable_payable',
      currency,
    );
    final total = MoneyValue.fromSql(
      result.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    return {
      'count': Sqflite.firstIntValue(result) ?? 0,
      'total': (total - elimination).toWireMap(),
      'eliminated_intercompany': elimination.toWireMap(),
    };
  }

  /// Obtiene cuentas por pagar consolidadas
  Future<Map<String, dynamic>> _getConsolidatedPayables(
    Database db,
    List<int> companyIds,
  ) async {
    if (!await _tableExists(db, 'cuentas_por_pagar')) {
      final currency = await _currencyForQuery(db, companyIds);
      return {
        'count': 0,
        'total': MoneyValue(minorUnits: 0, currency: currency).toWireMap(),
        'eliminated_intercompany': MoneyValue(
          minorUnits: 0,
          currency: currency,
        ).toWireMap(),
      };
    }
    final placeholders = List.filled(companyIds.length, '?').join(',');

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(saldo) as total
      FROM cuentas_por_pagar
      WHERE company_id IN ($placeholders) AND estado = 'pendiente'
    ''', companyIds);

    final currency = await _currencyForQuery(db, companyIds);
    final elimination = await _getApprovedEliminations(
      db,
      companyIds,
      'receivable_payable',
      currency,
    );
    final total = MoneyValue.fromSql(
      result.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    return {
      'count': Sqflite.firstIntValue(result) ?? 0,
      'total': (total - elimination).toWireMap(),
      'eliminated_intercompany': elimination.toWireMap(),
    };
  }

  /// Obtiene desglose por empresa
  Future<List<Map<String, dynamic>>> getBreakdownByCompany(
    Database db,
    List<int> companyIds, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final effectiveStartDate =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final effectiveEndDate = endDate ?? DateTime.now();

    final breakdown = <Map<String, dynamic>>[];

    for (final companyId in companyIds) {
      final companyData = await _getCompanyFinancials(
        db,
        companyId,
        effectiveStartDate,
        effectiveEndDate,
      );

      breakdown.add({'company_id': companyId, ...companyData});
    }

    return breakdown;
  }

  /// Obtiene financieras de una empresa específica
  Future<Map<String, dynamic>> _getCompanyFinancials(
    Database db,
    int companyId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final salesResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ? AND fecha <= ? AND estado = 'emitida'
    ''',
      [companyId, startDate.toIso8601String(), endDate.toIso8601String()],
    );

    final expensesResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(monto) as total
      FROM gastos
      WHERE company_id = ? AND fecha >= ? AND fecha <= ?
    ''',
      [companyId, startDate.toIso8601String(), endDate.toIso8601String()],
    );

    final inventoryResult = await db.rawQuery(
      '''
      SELECT 
        SUM(stock * costo) as total_value
      FROM productos
      WHERE company_id = ?
    ''',
      [companyId],
    );

    final currency = await _currencyForQuery(db, [companyId]);
    final sales = MoneyValue.fromSql(
      salesResult.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final expenses = MoneyValue.fromSql(
      expensesResult.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final inventoryValue = MoneyValue.fromSql(
      inventoryResult.first['total_value'],
      currency: currency,
      nullableAsZero: true,
    );

    return {
      'sales': {
        'count': Sqflite.firstIntValue(salesResult) ?? 0,
        'total': sales.toWireMap(),
      },
      'expenses': {
        'count': Sqflite.firstIntValue(expensesResult) ?? 0,
        'total': expenses.toWireMap(),
      },
      'inventory_value': inventoryValue.toWireMap(),
      'profit': (sales - expenses).toWireMap(),
    };
  }

  /// Genera reporte de consolidación en formato para exportación
  Future<Map<String, dynamic>> generateConsolidationReport(
    Database db,
    List<int> companyIds, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final consolidated = await getConsolidatedFinancials(
      db,
      companyIds,
      startDate: startDate,
      endDate: endDate,
    );

    final breakdown = await getBreakdownByCompany(
      db,
      companyIds,
      startDate: startDate,
      endDate: endDate,
    );

    return {
      'report_type': 'financial_consolidation',
      'generated_at': DateTime.now().toIso8601String(),
      'consolidated': consolidated,
      'breakdown_by_company': breakdown,
    };
  }

  /// Calcula KPIs consolidados
  Future<Map<String, dynamic>> getConsolidatedKPIs(
    Database db,
    List<int> companyIds,
  ) async {
    final consolidated = await getConsolidatedFinancials(db, companyIds);

    final sales = consolidated['sales'] as Map<String, dynamic>;
    final inventory = consolidated['inventory'] as Map<String, dynamic>;
    final currency = await _currencyForQuery(db, companyIds);
    final salesTotal = MoneyValue.fromSql(
      (sales['total'] as Map)['minor_units'],
      currency: currency,
    );
    final inventoryValue = MoneyValue.fromSql(
      (inventory['total_value'] as Map)['minor_units'],
      currency: currency,
    );
    final profit = MoneyValue.fromSql(
      (consolidated['profit'] as Map)['minor_units'],
      currency: currency,
    );

    return {
      'revenue_per_company': salesTotal.minorUnits / companyIds.length,
      'inventory_turnover': inventoryValue.minorUnits == 0
          ? 0
          : salesTotal.minorUnits / inventoryValue.minorUnits,
      'profit_per_company': profit.minorUnits / companyIds.length,
      'companies_count': companyIds.length,
    };
  }

  /// Consolidación vacía
  Map<String, dynamic> _emptyConsolidation() {
    return {
      'period': {
        'start': DateTime.now().toIso8601String(),
        'end': DateTime.now().toIso8601String(),
      },
      'companies': 0,
      'sales': {
        'count': 0,
        'total': 0,
        'subtotal': 0,
        'tax': 0,
        'average_ticket': 0,
      },
      'expenses': {'count': 0, 'total': 0},
      'inventory': {'total_products': 0, 'total_stock': 0, 'total_value': 0},
      'accounts_receivable': {'count': 0, 'total': 0},
      'accounts_payable': {'count': 0, 'total': 0},
      'profit': 0,
      'profit_margin': 0,
      'net_cash_position': 0,
    };
  }

  Future<Currency> _resolveCurrency(Database db, List<int> companyIds) async {
    return _currencyForQuery(db, companyIds);
  }

  Future<Currency> _currencyForQuery(Database db, List<int> companyIds) async {
    final first = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyIds.first,
    );
    for (final companyId in companyIds.skip(1)) {
      final current = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      if (current.code != first.code ||
          current.decimalPlaces != first.decimalPlaces) {
        throw StateError(
          'Cannot consolidate companies with different configured currencies',
        );
      }
    }
    return first;
  }

  Map<String, Object?> _wire(Object? value, Currency currency) {
    return MoneyValue.fromSql(
      value,
      currency: currency,
      nullableAsZero: true,
    ).toWireMap();
  }

  Future<MoneyValue> _getApprovedEliminations(
    Database db,
    List<int> companyIds,
    String metric,
    Currency currency,
  ) async {
    if (!await _tableExists(db, 'intercompany_eliminations')) {
      return MoneyValue(minorUnits: 0, currency: currency);
    }
    final placeholders = List.filled(companyIds.length, '?').join(',');
    final result = await db.rawQuery(
      '''
      SELECT SUM(amount) AS total
      FROM intercompany_eliminations
      WHERE metric = ?
        AND company_a_id IN ($placeholders)
        AND company_b_id IN ($placeholders)
    ''',
      [metric, ...companyIds, ...companyIds],
    );
    final total = result.first['total'];
    if (total == null) return MoneyValue(minorUnits: 0, currency: currency);
    return MoneyValue(minorUnits: (total as num).round(), currency: currency);
  }

  Future<bool> _tableExists(Database db, String table) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return result.isNotEmpty;
  }
}
