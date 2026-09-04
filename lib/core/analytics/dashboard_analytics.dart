// ============================================================
// dashboard_analytics.dart
// Servicio de analítica para dashboards avanzados
// ============================================================

import 'package:sqflite/sqflite.dart';

import '../currency/currency.dart';
import '../currency/money_currency_resolver.dart';
import '../currency/money_value.dart';

class DashboardAnalytics {
  static final DashboardAnalytics instance = DashboardAnalytics._internal();

  DashboardAnalytics._internal();

  /// Obtiene métricas de ventas para el dashboard
  Future<Map<String, dynamic>> getSalesMetrics(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final startDate = DateTime.now().subtract(Duration(days: days));

    // Ventas totales
    final totalSalesResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(total) as total_amount,
        AVG(total) as average_ticket
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Ventas por día
    final salesByDayResult = await db.rawQuery(
      '''
      SELECT 
        DATE(fecha) as date,
        COUNT(*) as count,
        SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
      GROUP BY DATE(fecha)
      ORDER BY date ASC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Productos más vendidos
    final topProductsResult = await db.rawQuery(
      '''
      SELECT 
        producto,
        SUM(cantidad) as total_quantity,
        SUM(total) as total_sales
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
      GROUP BY producto
      ORDER BY total_sales DESC
      LIMIT 10
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Ventas por método de pago
    final salesByPaymentResult = await db.rawQuery(
      '''
      SELECT 
        metodo_pago_id,
        COUNT(*) as count,
        SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
      GROUP BY metodo_pago_id
    ''',
      [companyId, startDate.toIso8601String()],
    );

    return {
      'total_sales': {
        'count': Sqflite.firstIntValue(totalSalesResult) ?? 0,
        'amount': _wire(totalSalesResult.first['total_amount'], currency),
        'average_ticket': _wire(
          (totalSalesResult.first['average_ticket'] as num?)?.round(),
          currency,
        ),
      },
      'sales_by_day': _wireRows(salesByDayResult, const ['total'], currency),
      'top_products': _wireRows(topProductsResult, const [
        'total_sales',
      ], currency),
      'sales_by_payment': _wireRows(salesByPaymentResult, const [
        'total',
      ], currency),
    };
  }

  /// Obtiene métricas de inventario para el dashboard
  Future<Map<String, dynamic>> getInventoryMetrics(
    Database db,
    int companyId,
  ) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    // Stock total
    final totalStockResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as total_products,
        SUM(stock) as total_stock,
        SUM(stock * costo) as total_value
      FROM productos
      WHERE company_id = ?
    ''',
      [companyId],
    );

    // Productos con stock bajo
    final lowStockResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM productos
      WHERE company_id = ? AND stock < stock_minimo
    ''',
      [companyId],
    );

    // Productos sin stock
    final outOfStockResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM productos
      WHERE company_id = ? AND stock <= 0
    ''',
      [companyId],
    );

    // Valor por categoría
    final valueByCategoryResult = await db.rawQuery(
      '''
      SELECT 
        categoria,
        SUM(stock * costo) as total_value,
        SUM(stock) as total_quantity
      FROM productos
      WHERE company_id = ?
      GROUP BY categoria
      ORDER BY total_value DESC
    ''',
      [companyId],
    );

    return {
      'total_inventory': {
        'products': Sqflite.firstIntValue(totalStockResult) ?? 0,
        'stock':
            (totalStockResult.first['total_stock'] as num?)?.toDouble() ?? 0,
        'value': _wire(totalStockResult.first['total_value'], currency),
      },
      'low_stock_count': Sqflite.firstIntValue(lowStockResult) ?? 0,
      'out_of_stock_count': Sqflite.firstIntValue(outOfStockResult) ?? 0,
      'value_by_category': _wireRows(valueByCategoryResult, const [
        'total_value',
      ], currency),
    };
  }

  /// Obtiene métricas financieras para el dashboard
  Future<Map<String, dynamic>> getFinancialMetrics(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final startDate = DateTime.now().subtract(Duration(days: days));

    // Ingresos
    final revenueResult = await db.rawQuery(
      '''
      SELECT 
        SUM(total) as total_revenue,
        SUM(subtotal) as subtotal,
        SUM(impuesto_total) as total_tax
      FROM ventas
      WHERE company_id = ? AND fecha >= ? AND estado = 'emitida'
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Gastos
    final expensesResult = await db.rawQuery(
      '''
      SELECT 
        SUM(monto) as total_expenses
      FROM gastos
      WHERE company_id = ? AND fecha >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Flujo de caja
    final cashFlowResult = await db.rawQuery(
      '''
      SELECT 
        DATE(fecha) as date,
        SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END) as net_flow
      FROM movimientos_caja
      WHERE company_id = ? AND fecha >= ?
      GROUP BY DATE(fecha)
      ORDER BY date ASC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Cuentas por cobrar
    final accountsReceivableResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(monto) as total
      FROM cuentas_por_cobrar
      WHERE company_id = ? AND estado = 'pendiente'
    ''',
      [companyId],
    );

    // Cuentas por pagar
    final accountsPayableResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(monto) as total
      FROM cuentas_por_pagar
      WHERE company_id = ? AND estado = 'pendiente'
    ''',
      [companyId],
    );

    final totalRevenue = _money(revenueResult.first['total_revenue'], currency);
    final totalExpenses = _money(
      expensesResult.first['total_expenses'],
      currency,
    );
    final profit = totalRevenue - totalExpenses;

    return {
      'revenue': {
        'total': totalRevenue.toWireMap(),
        'subtotal': _wire(revenueResult.first['subtotal'], currency),
        'tax': _wire(revenueResult.first['total_tax'], currency),
      },
      'expenses': {'total': totalExpenses.toWireMap()},
      'profit': profit.toWireMap(),
      'profit_margin': totalRevenue.minorUnits > 0
          ? (profit.minorUnits / totalRevenue.minorUnits) * 100
          : 0,
      'cash_flow': _wireRows(cashFlowResult, const ['net_flow'], currency),
      'accounts_receivable': {
        'count': Sqflite.firstIntValue(accountsReceivableResult) ?? 0,
        'total': _wire(accountsReceivableResult.first['total'], currency),
      },
      'accounts_payable': {
        'count': Sqflite.firstIntValue(accountsPayableResult) ?? 0,
        'total': _wire(accountsPayableResult.first['total'], currency),
      },
    };
  }

  /// Obtiene métricas de clientes para el dashboard
  Future<Map<String, dynamic>> getCustomerMetrics(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final startDate = DateTime.now().subtract(Duration(days: days));

    // Clientes nuevos
    final newCustomersResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM clientes
      WHERE company_id = ? AND fecha_registro >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Clientes activos (con compras en el periodo)
    final activeCustomersResult = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT cliente_id) as count
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Clientes más frecuentes
    final topCustomersResult = await db.rawQuery(
      '''
      SELECT 
        c.nombre,
        COUNT(v.id) as purchase_count,
        SUM(v.total) as total_spent
      FROM ventas v
      INNER JOIN clientes c ON v.cliente_id = c.id
      WHERE v.company_id = ? AND v.fecha >= ?
      GROUP BY c.id, c.nombre
      ORDER BY total_spent DESC
      LIMIT 10
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Valor promedio por cliente
    final avgCustomerValueResult = await db.rawQuery(
      '''
      SELECT 
        AVG(total_spent) as avg_value
      FROM (
        SELECT 
          cliente_id,
          SUM(total) as total_spent
        FROM ventas
        WHERE company_id = ? AND fecha >= ?
        GROUP BY cliente_id
      )
    ''',
      [companyId, startDate.toIso8601String()],
    );

    return {
      'new_customers': Sqflite.firstIntValue(newCustomersResult) ?? 0,
      'active_customers': Sqflite.firstIntValue(activeCustomersResult) ?? 0,
      'top_customers': _wireRows(topCustomersResult, const [
        'total_spent',
      ], currency),
      'average_customer_value': _wire(
        (avgCustomerValueResult.first['avg_value'] as num?)?.round(),
        currency,
      ),
    };
  }

  /// Obtiene métricas comparativas (periodo actual vs anterior)
  Future<Map<String, dynamic>> getComparativeMetrics(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final currentStart = DateTime.now().subtract(Duration(days: days));
    final previousStart = currentStart.subtract(Duration(days: days));
    final previousEnd = currentStart;

    // Ventas periodo actual
    final currentSalesResult = await db.rawQuery(
      '''
      SELECT SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ? AND fecha <= ?
    ''',
      [
        companyId,
        currentStart.toIso8601String(),
        DateTime.now().toIso8601String(),
      ],
    );

    // Ventas periodo anterior
    final previousSalesResult = await db.rawQuery(
      '''
      SELECT SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ? AND fecha <= ?
    ''',
      [
        companyId,
        previousStart.toIso8601String(),
        previousEnd.toIso8601String(),
      ],
    );

    final currentSales = _money(currentSalesResult.first['total'], currency);
    final previousSales = _money(previousSalesResult.first['total'], currency);

    final growth = previousSales.minorUnits > 0
        ? ((currentSales.minorUnits - previousSales.minorUnits) /
                  previousSales.minorUnits) *
              100
        : 0;

    return {
      'current_period': {
        'start': currentStart.toIso8601String(),
        'end': DateTime.now().toIso8601String(),
        'sales': currentSales.toWireMap(),
      },
      'previous_period': {
        'start': previousStart.toIso8601String(),
        'end': previousEnd.toIso8601String(),
        'sales': previousSales.toWireMap(),
      },
      'growth_percentage': growth,
      'is_positive_growth': growth >= 0,
    };
  }

  /// Obtiene datos para gráficos interactivos
  Future<Map<String, dynamic>> getChartData(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final startDate = DateTime.now().subtract(Duration(days: days));

    // Datos para gráfico de ventas diarias
    final dailySalesData = await db.rawQuery(
      '''
      SELECT 
        DATE(fecha) as date,
        SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
      GROUP BY DATE(fecha)
      ORDER BY date ASC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Datos para gráfico de ventas por categoría
    final categorySalesData = await db.rawQuery(
      '''
      SELECT 
        p.categoria,
        SUM(v.total) as total
      FROM ventas v
      INNER JOIN productos p ON v.producto_id = p.id
      WHERE v.company_id = ? AND v.fecha >= ?
      GROUP BY p.categoria
      ORDER BY total DESC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    // Datos para gráfico de ventas por hora
    final hourlySalesData = await db.rawQuery(
      '''
      SELECT 
        strftime('%H', fecha) as hour,
        COUNT(*) as count,
        SUM(total) as total
      FROM ventas
      WHERE company_id = ? AND fecha >= ?
      GROUP BY hour
      ORDER BY hour ASC
    ''',
      [companyId, startDate.toIso8601String()],
    );

    return {
      'daily_sales': _wireRows(dailySalesData, const ['total'], currency),
      'category_sales': _wireRows(categorySalesData, const ['total'], currency),
      'hourly_sales': _wireRows(hourlySalesData, const ['total'], currency),
    };
  }

  MoneyValue _money(Object? value, Currency currency) =>
      MoneyValue.fromSql(value, currency: currency, nullableAsZero: true);

  Map<String, Object?> _wire(Object? value, Currency currency) =>
      _money(value, currency).toWireMap();

  List<Map<String, Object?>> _wireRows(
    List<Map<String, Object?>> rows,
    List<String> fields,
    Currency currency,
  ) {
    return rows.map((row) {
      final copy = Map<String, Object?>.from(row);
      for (final field in fields) {
        if (copy.containsKey(field)) copy[field] = _wire(copy[field], currency);
      }
      return copy;
    }).toList();
  }
}
