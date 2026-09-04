import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/backup/full_backup_service.dart';
import '../core/currency/currency.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';
import 'control_center_endpoint.dart';

class ProductLookupResult {
  const ProductLookupResult({
    required this.product,
    required this.matchedBy,
    required this.currency,
    this.lot,
    this.suggestions = const [],
  });

  final Map<String, dynamic> product;
  final String matchedBy;
  final Currency currency;
  final Map<String, dynamic>? lot;
  final List<Map<String, dynamic>> suggestions;

  String get name => product['nombre']?.toString() ?? 'Producto';
  double get stock => (product['stock'] as num?)?.toDouble() ?? 0;
  double get price => MoneyValue.fromSql(
    product['precio'],
    currency: currency,
    nullableAsZero: true,
  ).toMajorUnitsDoubleForDisplay();
  String get location {
    final code = product['ubicacion_codigo']?.toString().trim() ?? '';
    if (code.isNotEmpty) return code;
    final parts = [
      product['ubicacion_pasillo']?.toString() ?? '',
      product['ubicacion_estante']?.toString() ?? '',
      product['ubicacion_nivel']?.toString() ?? '',
    ].where((part) => part.trim().isNotEmpty).join('-');
    return parts;
  }
}

class OperationalAlert {
  const OperationalAlert({
    required this.title,
    required this.detail,
    required this.priority,
    required this.kind,
    this.entityId,
  });

  final String title;
  final String detail;
  final String priority;
  final String kind;
  final int? entityId;
}

class CopilotReply {
  const CopilotReply({
    required this.intent,
    required this.response,
    this.moduleId,
  });

  final String intent;
  final String response;
  final String? moduleId;
}

class DashboardRankingItem {
  const DashboardRankingItem({required this.label, required this.value});

  final String label;
  final double value;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.salesToday,
    required this.salesWeek,
    required this.salesMonth,
    required this.salesYear,
    required this.grossProfitMonth,
    required this.grossMarginPct,
    required this.criticalStock,
    required this.overdueReceivables,
    required this.payables,
    required this.cashAvailable,
    required this.bankAvailable,
    required this.inventoryValue,
    required this.cashFlow,
    required this.salesLast7Days,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.businessHealthScore,
    required this.topProducts,
    required this.lowMarginProducts,
    required this.topCustomers,
  });

  final double salesToday;
  final double salesWeek;
  final double salesMonth;
  final double salesYear;
  final double grossProfitMonth;
  final double grossMarginPct;
  final int criticalStock;
  final double overdueReceivables;
  final double payables;
  final double cashAvailable;
  final double bankAvailable;
  final double inventoryValue;
  final double cashFlow;
  final List<double> salesLast7Days;
  final double incomeMonth;
  final double expenseMonth;
  final int businessHealthScore;
  final List<DashboardRankingItem> topProducts;
  final List<DashboardRankingItem> lowMarginProducts;
  final List<DashboardRankingItem> topCustomers;
}

class MerkaIntelligenceService {
  MerkaIntelligenceService({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<ProductLookupResult?> findProduct(String query) async {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return null;
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final rows = await db.query(
      'productos',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
    Map<String, dynamic>? best;
    var matchedBy = 'nombre';
    for (final row in rows) {
      final barcode = _normalize(row['codigo_barras']);
      final reference = _normalize(row['referencia']);
      final name = _normalize(row['nombre']);
      final description = _normalize(row['descripcion']);
      if (barcode.isNotEmpty && barcode == normalized) {
        best = row;
        matchedBy = 'codigo_barras';
        break;
      }
      if (reference.isNotEmpty && reference == normalized) {
        best = row;
        matchedBy = 'referencia';
        break;
      }
      if (name.contains(normalized) || description.contains(normalized)) {
        best ??= row;
        matchedBy = name.contains(normalized) ? 'nombre' : 'descripcion';
      }
    }
    if (best == null) return null;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final productId = (best['id'] as num).toInt();
    return ProductLookupResult(
      product: best,
      matchedBy: matchedBy,
      currency: currency,
      lot: await nextFifoLot(productId),
      suggestions: await crossSellSuggestions(productId),
    );
  }

  Future<Map<String, dynamic>?> nextFifoLot(int productId) async {
    final db = await _db.database;
    final rows = await db.query(
      'lotes',
      where: 'producto_id = ? AND cantidad > 0',
      whereArgs: [productId],
      orderBy:
          "CASE WHEN fecha_vencimiento IS NULL OR fecha_vencimiento = '' THEN 1 ELSE 0 END, fecha_vencimiento ASC, id ASC",
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> crossSellSuggestions(int productId) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final rows = await db.rawQuery(
      '''
      SELECT p.*, COUNT(*) AS score
      FROM ventas_detalle base
      INNER JOIN ventas_detalle rel ON rel.venta_id = base.venta_id
      INNER JOIN productos p ON p.id = rel.producto_id
      WHERE base.producto_id = ?
        AND rel.producto_id != ?
        AND p.company_id = ?
      GROUP BY p.id
      ORDER BY score DESC, p.nombre ASC
      LIMIT 3
      ''',
      [productId, productId, companyId],
    );
    if (rows.isNotEmpty) return rows;
    return db.query(
      'productos',
      where: 'company_id = ? AND id != ? AND stock > 0',
      whereArgs: [companyId, productId],
      orderBy: 'stock DESC, nombre ASC',
      limit: 3,
    );
  }

  Future<List<OperationalAlert>> operationalAlerts() async {
    if (DatabaseHelper.disableAutoLoadsForTests) return const [];
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(db, companyId: companyId);
    final now = DateTime.now();
    final until = now.add(const Duration(days: 30)).toIso8601String();
    final alerts = <OperationalAlert>[];

    final expiringRows = await db.rawQuery('''
      SELECT l.id, l.producto_id, l.codigo_lote, l.fecha_vencimiento, l.cantidad, p.nombre
      FROM lotes l INNER JOIN productos p ON p.id = l.producto_id
      WHERE l.company_id = ? AND l.cantidad > 0
        AND l.fecha_vencimiento IS NOT NULL AND l.fecha_vencimiento != ''
        AND l.fecha_vencimiento <= ?
      ORDER BY l.fecha_vencimiento ASC LIMIT 8
    ''', [companyId, until]);
    for (final row in expiringRows) {
      alerts.add(OperationalAlert(
        title: '${row['nombre']} por vencer',
        detail: 'Lote ${row['codigo_lote']} vence ${_shortDate(row['fecha_vencimiento'])}. Cantidad ${(row['cantidad'] as num?)?.toStringAsFixed(0) ?? '0'}.',
        priority: 'urgent', kind: 'expiring_product',
        entityId: (row['producto_id'] as num?)?.toInt(),
      ));
    }

    final stockRows = await db.query('productos',
      where: 'company_id = ? AND stock <= COALESCE(stock_minimo, 5)',
      whereArgs: [companyId], orderBy: 'stock ASC', limit: 8);
    for (final row in stockRows) {
      final stock = (row['stock'] as num?)?.toDouble() ?? 0;
      alerts.add(OperationalAlert(
        title: stock < 0 ? 'Inventario negativo: ${row['nombre']}' : 'Stock crítico: ${row['nombre']}',
        detail: stock < 0
            ? 'El producto registra ${stock.toStringAsFixed(0)} unidades. Revisa Kardex, ajustes y anulaciones.'
            : 'Quedan ${stock.toStringAsFixed(0)} unidades. Revisa compra o traslado.',
        priority: stock < 0 ? 'urgent' : 'warning',
        kind: stock < 0 ? 'negative_stock' : 'critical_stock',
        entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final overdue = await db.rawQuery('''
      SELECT id, cliente, saldo, vencimiento FROM cuentas_por_cobrar
      WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'
        AND vencimiento IS NOT NULL AND vencimiento != '' AND vencimiento < ?
      ORDER BY vencimiento ASC LIMIT 8
    ''', [companyId, now.toIso8601String()]);
    for (final row in overdue) {
      final value = MoneyValue.fromSql(row['saldo'], currency: currency, nullableAsZero: true);
      alerts.add(OperationalAlert(
        title: 'Cartera vencida: ${row['cliente'] ?? 'Cliente'}',
        detail: 'Saldo ${value.format()} vencido desde ${_shortDate(row['vencimiento'])}.',
        priority: 'urgent', kind: 'overdue_receivable',
        entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final payables = await db.rawQuery('''
      SELECT id, proveedor, saldo, fecha FROM cuentas_por_pagar
      WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'
      ORDER BY fecha ASC LIMIT 5
    ''', [companyId]);
    for (final row in payables) {
      final value = MoneyValue.fromSql(row['saldo'], currency: currency, nullableAsZero: true);
      alerts.add(OperationalAlert(
        title: 'Proveedor por pagar: ${row['proveedor'] ?? 'Proveedor'}',
        detail: 'Saldo pendiente ${value.format()} desde ${_shortDate(row['fecha'])}.',
        priority: 'info', kind: 'payable', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final cashDifferences = await db.rawQuery('''
      SELECT id, diferencia, fecha FROM cierres_caja
      WHERE company_id = ? AND ABS(COALESCE(diferencia, 0)) > 0
      ORDER BY fecha DESC LIMIT 3
    ''', [companyId]);
    for (final row in cashDifferences) {
      final value = MoneyValue.fromSql(row['diferencia'], currency: currency, nullableAsZero: true);
      alerts.add(OperationalAlert(
        title: 'Caja descuadrada',
        detail: 'El cierre #${row['id']} registró una diferencia de ${value.format()} el ${_shortDate(row['fecha'])}.',
        priority: 'urgent', kind: 'cash_difference', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final lowMargin = await db.rawQuery('''
      SELECT id, nombre, precio, costo FROM productos
      WHERE company_id = ? AND precio > 0 AND costo > 0
        AND ((precio - costo) * 100.0 / precio) < 8
      ORDER BY ((precio - costo) * 100.0 / precio) ASC LIMIT 5
    ''', [companyId]);
    for (final row in lowMargin) {
      final price = MoneyValue.fromSql(row['precio'], currency: currency, nullableAsZero: true);
      final cost = MoneyValue.fromSql(row['costo'], currency: currency, nullableAsZero: true);
      alerts.add(OperationalAlert(
        title: 'Margen muy bajo: ${row['nombre']}',
        detail: 'Precio ${price.format()} frente a costo ${cost.format()}. Revisa precio, descuentos y costo vigente.',
        priority: 'warning', kind: 'low_margin', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final electronic = await db.rawQuery('''
      SELECT id, consecutivo, estado, fecha FROM facturas_electronicas
      WHERE company_id = ? AND LOWER(estado) NOT IN ('aceptada','validada','enviada','anulada')
      ORDER BY fecha ASC LIMIT 5
    ''', [companyId]);
    for (final row in electronic) {
      alerts.add(OperationalAlert(
        title: 'Factura electrónica pendiente',
        detail: '${row['consecutivo']} permanece en estado ${row['estado']} desde ${_shortDate(row['fecha'])}.',
        priority: 'warning', kind: 'electronic_invoice_pending', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    try {
      final backups = await FullBackupService.instance.listBackups();
      if (backups.isEmpty) {
        alerts.add(const OperationalAlert(
          title: 'No hay respaldo integral',
          detail: 'Crea un respaldo antes de continuar acumulando información crítica.',
          priority: 'urgent', kind: 'backup_missing',
        ));
      } else {
        final age = now.difference(await backups.first.lastModified());
        if (age.inHours >= 36) {
          alerts.add(OperationalAlert(
            title: 'Respaldo atrasado',
            detail: 'El último respaldo integral tiene ${age.inHours} horas. La recomendación operativa es mantener copia diaria.',
            priority: 'warning', kind: 'backup_stale',
          ));
        }
      }
    } catch (_) {}

    final tenant = await db.query('tenants', columns: ['subscription_end'],
      where: 'id = ?', whereArgs: [companyId], limit: 1);
    if (tenant.isNotEmpty) {
      final expires = DateTime.tryParse(tenant.first['subscription_end']?.toString() ?? '');
      if (expires != null) {
        final remaining = expires.difference(now).inDays;
        if (remaining <= 15) {
          alerts.add(OperationalAlert(
            title: remaining < 0 ? 'Licencia vencida' : 'Licencia próxima a vencer',
            detail: remaining < 0 ? 'La fecha registrada de suscripción ya venció.' : 'Quedan $remaining días según la licencia local verificada.',
            priority: remaining <= 3 ? 'urgent' : 'warning', kind: 'license_expiry',
          ));
        }
      }
    }
    return alerts;
  }

  Future<DashboardSnapshot> dashboardSnapshot() async {
    if (DatabaseHelper.disableAutoLoadsForTests) {
      return const DashboardSnapshot(
        salesToday: 0,
        salesWeek: 0,
        salesMonth: 0,
        salesYear: 0,
        grossProfitMonth: 0,
        grossMarginPct: 0,
        criticalStock: 0,
        overdueReceivables: 0,
        payables: 0,
        cashAvailable: 0,
        bankAvailable: 0,
        inventoryValue: 0,
        cashFlow: 0,
        salesLast7Days: [0, 0, 0, 0, 0, 0, 0],
        incomeMonth: 0,
        expenseMonth: 0,
        businessHealthScore: 0,
        topProducts: [],
        lowMarginProducts: [],
        topCustomers: [],
      );
    }
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final weekStart = dayStart.subtract(Duration(days: now.weekday - 1));
    final monthStartDate = DateTime(now.year, now.month, 1);
    final yearStart = DateTime(now.year, 1, 1);
    final salesToday = await _sumSales(db, companyId, dayStart, now, currency);
    final salesWeek = await _sumSales(db, companyId, weekStart, now, currency);
    final salesMonth = await _sumSales(db, companyId, monthStartDate, now, currency);
    final salesYear = await _sumSales(db, companyId, yearStart, now, currency);

    final criticalRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM productos WHERE company_id = ? AND stock <= COALESCE(stock_minimo, 5)',
      [companyId],
    );
    final productCountRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM productos WHERE company_id = ?',
      [companyId],
    );
    final receivableRows = await db.rawQuery(
      "SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_cobrar WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'",
      [companyId],
    );
    final payableRows = await db.rawQuery(
      "SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_pagar WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'",
      [companyId],
    );
    final incomeRows = await db.rawQuery(
      "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'ingreso'",
      [companyId],
    );
    final expenseRows = await db.rawQuery(
      "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'egreso'",
      [companyId],
    );
    final monthStart = monthStartDate.toIso8601String();
    final monthEnd = DateTime(now.year, now.month + 1, 1).toIso8601String();
    final monthIncomeRows = await db.rawQuery(
      "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'ingreso' AND fecha >= ? AND fecha < ?",
      [companyId, monthStart, monthEnd],
    );
    final monthExpenseRows = await db.rawQuery(
      "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'egreso' AND fecha >= ? AND fecha < ?",
      [companyId, monthStart, monthEnd],
    );
    final cogsRows = await db.rawQuery(
      "SELECT COALESCE(SUM(costo_total), 0) AS total FROM kardex_inventario WHERE company_id = ? AND documento_tipo = 'venta' AND fecha >= ? AND fecha < ?",
      [companyId, monthStart, monthEnd],
    );

    Future<MoneyValue> balanceFor(String origin) async {
      final rows = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE 0 END), 0) AS ingresos,
          COALESCE(SUM(CASE WHEN tipo IN ('egreso','transferencia') THEN monto ELSE 0 END), 0) AS egresos
        FROM movimientos_caja
        WHERE company_id = ? AND origen = ?
        ''',
        [companyId, origin],
      );
      return MoneyValue.fromSql(rows.first['ingresos'], currency: currency, nullableAsZero: true) -
          MoneyValue.fromSql(rows.first['egresos'], currency: currency, nullableAsZero: true);
    }

    final cashAvailable = await balanceFor('caja');
    final bankAvailable = await balanceFor('banco');
    var inventoryValue = MoneyValue(minorUnits: 0, currency: currency);
    final inventoryRows = await db.query(
      'productos',
      columns: ['stock', 'costo'],
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    for (final row in inventoryRows) {
      final stock = (row['stock'] as num?)?.toDouble() ?? 0;
      final cost = MoneyValue.fromSql(row['costo'], currency: currency, nullableAsZero: true);
      inventoryValue += cost.multiplyDecimal(stock.toString());
    }

    final cogs = MoneyValue.fromSql(
      cogsRows.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final grossProfit = salesMonth - cogs;
    final grossMargin = salesMonth.minorUnits <= 0
        ? 0.0
        : grossProfit.minorUnits * 100 / salesMonth.minorUnits;

    final sales7 = <double>[];
    for (var i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      sales7.add(
        (await _sumSales(db, companyId, day, day, currency))
            .toMajorUnitsDoubleForDisplay(),
      );
    }

    final topProductRows = await db.rawQuery(
      '''
      SELECT vd.producto AS label, COALESCE(SUM(vd.subtotal), 0) AS total
      FROM ventas_detalle vd
      JOIN ventas v ON v.id = vd.venta_id
      WHERE vd.company_id = ? AND v.estado = 'emitida' AND v.fecha >= ? AND v.fecha < ?
      GROUP BY vd.producto_id, vd.producto
      ORDER BY total DESC
      LIMIT 5
      ''',
      [companyId, monthStart, monthEnd],
    );
    final topCustomerRows = await db.rawQuery(
      '''
      SELECT COALESCE(NULLIF(cliente, ''), 'Venta mostrador') AS label,
             COALESCE(SUM(total), 0) AS total
      FROM ventas
      WHERE company_id = ? AND estado = 'emitida' AND fecha >= ? AND fecha < ?
      GROUP BY cliente_id, cliente
      ORDER BY total DESC
      LIMIT 5
      ''',
      [companyId, monthStart, monthEnd],
    );
    final productRevenueRows = await db.rawQuery(
      '''
      SELECT vd.producto_id, vd.producto AS label,
             COALESCE(SUM(vd.subtotal), 0) AS revenue
      FROM ventas_detalle vd
      JOIN ventas v ON v.id = vd.venta_id
      WHERE vd.company_id = ? AND v.estado = 'emitida' AND v.fecha >= ? AND v.fecha < ?
      GROUP BY vd.producto_id, vd.producto
      ''',
      [companyId, monthStart, monthEnd],
    );
    final costByProductRows = await db.rawQuery(
      '''
      SELECT producto_id, COALESCE(SUM(costo_total), 0) AS cost
      FROM kardex_inventario
      WHERE company_id = ? AND documento_tipo = 'venta' AND fecha >= ? AND fecha < ?
      GROUP BY producto_id
      ''',
      [companyId, monthStart, monthEnd],
    );
    final costByProduct = <int, MoneyValue>{
      for (final row in costByProductRows)
        (row['producto_id'] as num).toInt(): MoneyValue.fromSql(
          row['cost'],
          currency: currency,
          nullableAsZero: true,
        ),
    };
    final lowMargins = <DashboardRankingItem>[];
    for (final row in productRevenueRows) {
      final id = (row['producto_id'] as num).toInt();
      final revenue = MoneyValue.fromSql(row['revenue'], currency: currency, nullableAsZero: true);
      if (revenue.minorUnits <= 0) continue;
      final cost = costByProduct[id] ?? MoneyValue(minorUnits: 0, currency: currency);
      final marginPct = (revenue - cost).minorUnits * 100 / revenue.minorUnits;
      lowMargins.add(DashboardRankingItem(label: row['label'].toString(), value: marginPct));
    }
    lowMargins.sort((a, b) => a.value.compareTo(b.value));

    List<DashboardRankingItem> moneyRanking(List<Map<String, Object?>> rows) => rows
        .map(
          (row) => DashboardRankingItem(
            label: row['label']?.toString() ?? '-',
            value: MoneyValue.fromSql(
              row['total'],
              currency: currency,
              nullableAsZero: true,
            ).toMajorUnitsDoubleForDisplay(),
          ),
        )
        .toList();

    final income = MoneyValue.fromSql(incomeRows.first['total'], currency: currency);
    final expense = MoneyValue.fromSql(expenseRows.first['total'], currency: currency);
    final cashFlow = income - expense;
    final receivables = MoneyValue.fromSql(
      receivableRows.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final payables = MoneyValue.fromSql(
      payableRows.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
    final criticalStock = (criticalRows.first['total'] as num?)?.toInt() ?? 0;
    final productCount = (productCountRows.first['total'] as num?)?.toInt() ?? 0;

    var score = 50.0;
    if (grossMargin >= 25) {
      score += 15;
    } else if (grossMargin >= 10) {
      score += 8;
    } else if (grossMargin < 0) {
      score -= 20;
    }
    final liquidity = cashAvailable + bankAvailable;
    if (payables.minorUnits == 0 || liquidity.minorUnits >= payables.minorUnits) {
      score += 15;
    } else if (liquidity.minorUnits * 2 < payables.minorUnits) {
      score -= 15;
    }
    final criticalRatio = productCount == 0 ? 0 : criticalStock / productCount;
    if (criticalRatio <= 0.05) {
      score += 10;
    } else if (criticalRatio > 0.25) {
      score -= 10;
    }
    if (receivables.minorUnits > salesMonth.minorUnits && salesMonth.minorUnits > 0) {
      score -= 10;
    } else {
      score += 5;
    }
    if (sales7.length >= 7) {
      final firstHalf = sales7.take(3).fold<double>(0, (a, b) => a + b);
      final lastHalf = sales7.skip(4).fold<double>(0, (a, b) => a + b);
      if (lastHalf > firstHalf) score += 5;
    }
    final healthScore = score.round().clamp(0, 100);

    return DashboardSnapshot(
      salesToday: salesToday.toMajorUnitsDoubleForDisplay(),
      salesWeek: salesWeek.toMajorUnitsDoubleForDisplay(),
      salesMonth: salesMonth.toMajorUnitsDoubleForDisplay(),
      salesYear: salesYear.toMajorUnitsDoubleForDisplay(),
      grossProfitMonth: grossProfit.toMajorUnitsDoubleForDisplay(),
      grossMarginPct: grossMargin,
      criticalStock: criticalStock,
      overdueReceivables: receivables.toMajorUnitsDoubleForDisplay(),
      payables: payables.toMajorUnitsDoubleForDisplay(),
      cashAvailable: cashAvailable.toMajorUnitsDoubleForDisplay(),
      bankAvailable: bankAvailable.toMajorUnitsDoubleForDisplay(),
      inventoryValue: inventoryValue.toMajorUnitsDoubleForDisplay(),
      cashFlow: cashFlow.toMajorUnitsDoubleForDisplay(),
      salesLast7Days: sales7,
      incomeMonth: MoneyValue.fromSql(
        monthIncomeRows.first['total'],
        currency: currency,
      ).toMajorUnitsDoubleForDisplay(),
      expenseMonth: MoneyValue.fromSql(
        monthExpenseRows.first['total'],
        currency: currency,
      ).toMajorUnitsDoubleForDisplay(),
      businessHealthScore: healthScore,
      topProducts: moneyRanking(topProductRows),
      lowMarginProducts: lowMargins.take(5).toList(),
      topCustomers: moneyRanking(topCustomerRows),
    );
  }

  Future<CopilotReply> answer(
    String text, {
    String module = 'workspace',
    String role = 'local',
    String userName = 'local',
    String? userId,
    bool persistConversation = true,
  }) async {
    final normalized = _normalize(text);
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    CopilotReply reply;
    if (_matches(normalized, [
      'ventas hoy',
      'vendi hoy',
      'vendí hoy',
      'ventas dia',
    ])) {
      final total = await _sumSales(
        db,
        companyId,
        DateTime.now(),
        DateTime.now(),
        currency,
      );
      reply = CopilotReply(
        intent: 'sales_today',
        moduleId: 'sales',
        response:
            'Hoy vas en ${_money(total.toMajorUnitsDoubleForDisplay())} en ventas emitidas. Puedo abrir Ventas para revisar el detalle.',
      );
    } else if (_matches(normalized, [
      'ventas mes',
      'vendido mes',
      'ventas del mes',
    ])) {
      final now = DateTime.now();
      final total = await _sumSales(
        db,
        companyId,
        DateTime(now.year, now.month, 1),
        now,
        currency,
      );
      reply = CopilotReply(
        intent: 'sales_month',
        moduleId: 'reports',
        response:
            'Este mes llevas ${_money(total.toMajorUnitsDoubleForDisplay())} en ventas. Recomendacion: revisa top productos y cartera asociada.',
      );
    } else if (_matches(normalized, [
      'stock critico',
      'productos criticos',
      'bajo stock',
    ])) {
      final rows = await db.query(
        'productos',
        where: 'company_id = ? AND stock <= 5',
        whereArgs: [companyId],
        orderBy: 'stock ASC',
        limit: 5,
      );
      reply = CopilotReply(
        intent: 'critical_stock',
        moduleId: 'inventory',
        response: rows.isEmpty
            ? 'No veo productos con stock critico ahora mismo.'
            : 'Productos criticos: ${rows.map((r) => '${r['nombre']} (${r['stock']})').join(', ')}. Conviene crear compra o traslado.',
      );
    } else if (_matches(normalized, ['por vencer', 'vencimiento', 'vence'])) {
      final alerts = (await operationalAlerts())
          .where((item) => item.kind == 'expiring_product')
          .take(5)
          .toList();
      reply = CopilotReply(
        intent: 'expiring_products',
        moduleId: 'inventory',
        response: alerts.isEmpty
            ? 'No hay lotes por vencer en los proximos 30 dias.'
            : 'Estos productos requieren accion: ${alerts.map((a) => a.title).join(', ')}. Puedes venderlos primero por FIFO.',
      );
    } else if (_matches(normalized, [
      'cartera',
      'cobranza',
      'cobrar',
      'deuda',
    ])) {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_cobrar WHERE company_id = ? AND saldo > 0',
        [companyId],
      );
      reply = CopilotReply(
        intent: 'receivables',
        moduleId: 'receivables',
        response:
            'La cartera pendiente registrada es ${_money(MoneyValue.fromSql(rows.first['total'], currency: currency, nullableAsZero: true).toMajorUnitsDoubleForDisplay())}. Puedo llevarte a Cuentas por cobrar.',
      );
    } else if (_matches(normalized, [
      'pagar',
      'cuentas por pagar',
      'proveedores',
    ])) {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_pagar WHERE company_id = ? AND saldo > 0',
        [companyId],
      );
      reply = CopilotReply(
        intent: 'payables',
        moduleId: 'payables',
        response:
            'Tienes ${_money(MoneyValue.fromSql(rows.first['total'], currency: currency, nullableAsZero: true).toMajorUnitsDoubleForDisplay())} en cuentas por pagar. Revisa vencimientos antes de programar caja.',
      );
    } else if (_matches(normalized, [
      'crear compra',
      'orden de compra',
      'entrada mercancia',
    ])) {
      reply = const CopilotReply(
        intent: 'open_purchase',
        moduleId: 'purchases',
        response:
            'Puedo abrir Compras para que prepares una orden. No se guardara nada hasta que completes y confirmes el formulario.',
      );
    } else if (_matches(normalized, ['arqueo', 'cierre caja', 'cerrar caja'])) {
      reply = const CopilotReply(
        intent: 'cash_closing',
        moduleId: 'cash_closings',
        response:
            'Para cerrar caja debes registrar ventas, ingresos, egresos y justificar cualquier diferencia antes de confirmar el cierre.',
      );
    } else if (_matches(normalized, ['cotizacion', 'cotizacion', 'pedido'])) {
      reply = const CopilotReply(
        intent: 'quote_order',
        moduleId: 'sales',
        response:
            'El flujo comercial queda preparado como Cotizacion -> Pedido -> Factura. Abre Ventas para crear el documento inicial.',
      );
    } else if (_matches(normalized, [
      'factura electronica',
      'facturacion electronica',
      'dian',
      'cufe',
    ])) {
      reply = const CopilotReply(
        intent: 'electronic_invoice',
        moduleId: 'electronic_invoice',
        response:
            'El centro de Facturacion Electronica prepara documentos y configuracion local. La transmision real a DIAN depende de un proveedor y credenciales habilitados; sin un transporte real configurado el sistema permanece bloqueado y no reporta una validación oficial.',
      );
    } else if (_matches(normalized, [
      'licencia',
      'licencias',
      'activar licencia',
      'hwid',
      'plan',
    ])) {
      reply = const CopilotReply(
        intent: 'licensing',
        moduleId: 'licensing',
        response:
            'El modulo de Licencias te permite consultar tu plan activo, copiar tu Identificador de Dispositivo (HWID) y activar o renovar tu clave de suscripcion empresarial.',
      );
    } else if (_matches(normalized, ['instalaciones', 'control center'])) {
      reply = CopilotReply(
        intent: 'control_center_status',
        moduleId: 'erp_readiness',
        response: await controlCenterStatus(),
      );
    } else if (_matches(normalized, [
      'como funciona',
      'ayuda',
      'explicacion',
      'guia',
      'manual',
      'como hago',
      'como se',
      'que es',
    ])) {
      String manualResponse = 'Aquí tienes ayuda sobre el sistema:\n\n';
      if (_matches(normalized, [
        'caja',
        'cierre',
        'arqueo',
        'dinero',
        'billete',
        'moneda',
      ])) {
        manualResponse +=
            '• **Arqueo y Cierre de Caja**: Ahora puedes realizar el arqueo detallado utilizando la calculadora de Monedas y Billetes Colombianos (COP) en el diálogo de Cierre. Permite registrar billetes de \$100k a \$2k y monedas de \$1000 a \$50. El desglose se guarda en la observación del cierre y bloquea las operaciones para proteger el saldo.';
      } else if (_matches(normalized, [
        'lote',
        'vencimiento',
        'vence',
        'inventario',
        'caduca',
      ])) {
        manualResponse +=
            '• **Lotes y Vencimientos**: Al crear un nuevo producto con stock inicial, puedes indicar su código de lote y fecha de vencimiento. El sistema te alertará automáticamente si hay lotes a vencer en los próximos 30 días. Puedes ver los lotes de cada producto seleccionando "Ver lotes" en el listado de inventario.';
      } else if (_matches(normalized, [
        'factura',
        'dian',
        'electronica',
        'cufe',
        'xml',
        'ubl',
      ])) {
        manualResponse +=
            '• **Facturación Electrónica DIAN**: MerkaERP prepara datos y documentos locales. La validación y transmisión oficial solo están disponibles cuando existe un proveedor tecnológico y credenciales reales configurados; sin un transporte real configurado MerkaERP no transmite ni reporta aceptación DIAN.';
      } else if (_matches(normalized, [
        'licencia',
        'activar',
        'suscripcion',
        'hwid',
        'plan',
      ])) {
        manualResponse +=
            '• **Licenciamiento Empresarial**: El software se valida offline u online firmando el Hardware ID (HWID) del PC del cliente. Puedes ver tu plan activo, copiar tu HWID o renovar ingresando tu clave de activación desde el módulo de Licencias.';
      } else if (_matches(normalized, [
        'puc',
        'contabilidad',
        'cuenta',
        'asiento',
      ])) {
        manualResponse +=
            '• **Plan de Cuentas (PUC)**: Se precarga el catálogo del Plan Único de Cuentas (PUC) comercial de Colombia con más de 80 cuentas jerárquicas operativas (Caja, Bancos, Cartera, IVA, Retenciones, etc.) integradas automáticamente con las ventas, compras y cobros.';
      } else {
        manualResponse +=
            'MerkaERP cuenta con manuales detallados de:\n'
            '1. **Caja y Arqueo Detallado (COP)**: calculadora física de denominaciones.\n'
            '2. **Inventario y Lotes**: control de fechas de vencimiento y lotes iniciales.\n'
            '3. **Facturación Electrónica DIAN**: preparación local; transmisión oficial sujeta a proveedor configurado.\n'
            '4. **Licenciamiento y HWID**: control de suscripciones offline por Hardware ID.\n'
            '5. **Plan Único de Cuentas (PUC)**: catálogo contable oficial de Colombia.\n\n'
            'Pregúntame sobre cualquiera de estos temas para darte una explicación detallada.';
      }
      reply = CopilotReply(intent: 'manual_guide', response: manualResponse);
    } else {
      reply = const CopilotReply(
        intent: 'fallback',
        response:
            'Puedo ayudarte con ventas de hoy, ventas del mes, stock critico, productos por vencer, cartera, cuentas por pagar, facturacion electronica DIAN, licencias o estado de Control Center.',
      );
    }

    if (persistConversation) {
      await db.insert('conversaciones_copilot', {
        'company_id': companyId,
        'usuario': userName,
        'usuario_id': userId,
        'modulo': module,
        'rol': role,
        'mensaje_usuario': text,
        'respuesta': reply.response,
        'intent': reply.intent,
        'proveedor': 'deterministic',
        'resultado': 'exitoso',
        'creada_en': DateTime.now().toIso8601String(),
      });
    }
    return reply;
  }

  Future<String> controlCenterStatus() async {
    final endpoint = await _controlCenterEndpoint();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$endpoint/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return 'Control Center responde correctamente en $endpoint. Estado: $body';
      }
      return 'Control Center respondio HTTP ${response.statusCode} en $endpoint.';
    } catch (_) {
      return 'No pude conectar con Control Center en $endpoint. Verifica que este abierto y que el puerto 8787 sea accesible.';
    } finally {
      client.close(force: true);
    }
  }

  Future<MoneyValue> _sumSales(
    dynamic db,
    int companyId,
    DateTime from,
    DateTime to,
    Currency currency,
  ) async {
    final start = DateTime(from.year, from.month, from.day).toIso8601String();
    final end = DateTime(
      to.year,
      to.month,
      to.day,
      23,
      59,
      59,
    ).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) AS total
      FROM ventas
      WHERE company_id = ?
        AND fecha >= ?
        AND fecha <= ?
        AND COALESCE(estado, 'emitida') != 'anulada'
      ''',
      [companyId, start, end],
    );
    return MoneyValue.fromSql(rows.first['total'], currency: currency);
  }

  Future<String> _controlCenterEndpoint() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['control_center_endpoint'],
      limit: 1,
    );
    final value = rows.isEmpty
        ? ''
        : rows.first['valor']?.toString().trim() ?? '';
    return ControlCenterEndpoint.normalize(value.isEmpty ? null : value);
  }

  bool _matches(String text, List<String> patterns) {
    return patterns.any((pattern) => text.contains(_normalize(pattern)));
  }

  String _normalize(Object? value) {
    return (value?.toString() ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .trim();
  }

  String _shortDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'sin fecha';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _money(double value) {
    final text = value.toStringAsFixed(0);
    return '\$${text.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }
}
