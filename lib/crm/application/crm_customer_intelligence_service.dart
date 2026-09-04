import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';

class CrmCustomerInsight {
  const CrmCustomerInsight({
    required this.clientId,
    required this.name,
    required this.salesCount,
    required this.totalSales,
    required this.averageTicket,
    required this.outstanding,
    required this.lastPurchase,
    required this.averageDaysBetweenPurchases,
    required this.nextExpectedPurchase,
    required this.segment,
  });

  final int clientId;
  final String name;
  final int salesCount;
  final MoneyValue totalSales;
  final MoneyValue averageTicket;
  final MoneyValue outstanding;
  final DateTime? lastPurchase;
  final double? averageDaysBetweenPurchases;
  final DateTime? nextExpectedPurchase;
  final String segment;
}

class CrmCustomerIntelligenceSnapshot {
  const CrmCustomerIntelligenceSnapshot({
    required this.currency,
    required this.customers,
    required this.averageCustomerValue,
  });

  final Currency currency;
  final List<CrmCustomerInsight> customers;
  final MoneyValue averageCustomerValue;

  int get vipCount => customers.where((c) => c.segment == 'VIP').length;
  int get inactiveCount => customers.where((c) => c.segment == 'Inactivo').length;
  int get frequentCount => customers.where((c) => c.segment == 'Frecuente').length;
  int get atRiskCount => customers.where((c) => c.segment == 'En riesgo').length;
}

class CrmCustomerIntelligenceService {
  const CrmCustomerIntelligenceService();

  Future<CrmCustomerIntelligenceSnapshot> analyze() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final clients = await db.query(
      'clientes',
      columns: ['id', 'nombre'],
      where: 'company_id = ? AND estado != ?',
      whereArgs: [companyId, 'inactivo'],
      orderBy: 'nombre',
    );
    final salesRows = await db.query(
      'ventas',
      columns: ['cliente_id', 'cliente', 'fecha', 'total', 'estado'],
      where: 'company_id = ? AND estado = ?',
      whereArgs: [companyId, 'emitida'],
      orderBy: 'fecha ASC',
    );
    final receivableRows = await db.rawQuery(
      '''
      SELECT cliente_id, COALESCE(SUM(saldo), 0) AS saldo
      FROM cuentas_por_cobrar
      WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'
      GROUP BY cliente_id
      ''',
      [companyId],
    );
    final outstandingByClient = <int, MoneyValue>{};
    for (final row in receivableRows) {
      final id = (row['cliente_id'] as num?)?.toInt();
      if (id == null) continue;
      outstandingByClient[id] = MoneyValue.fromSql(
        row['saldo'],
        currency: currency,
        nullableAsZero: true,
      );
    }

    final salesByClient = <int, List<Map<String, Object?>>>{};
    for (final row in salesRows) {
      final id = (row['cliente_id'] as num?)?.toInt();
      if (id == null) continue;
      salesByClient.putIfAbsent(id, () => <Map<String, Object?>>[]).add(row);
    }

    final zero = MoneyValue(minorUnits: 0, currency: currency);
    var totalCustomerValue = zero;
    var customersWithSales = 0;
    final intermediate = <_IntermediateInsight>[];
    for (final client in clients) {
      final id = (client['id'] as num).toInt();
      final rows = salesByClient[id] ?? const <Map<String, Object?>>[];
      var total = zero;
      final dates = <DateTime>[];
      for (final row in rows) {
        total += MoneyValue.fromSql(
          row['total'],
          currency: currency,
          nullableAsZero: true,
        );
        final parsed = DateTime.tryParse(row['fecha']?.toString() ?? '');
        if (parsed != null) dates.add(parsed);
      }
      dates.sort();
      final count = rows.length;
      final average = count == 0 ? zero : total / count;
      final avgDays = _averageDays(dates);
      final last = dates.isEmpty ? null : dates.last;
      final next = last == null || avgDays == null
          ? null
          : last.add(Duration(days: avgDays.round().clamp(1, 3650)));
      if (count > 0) {
        totalCustomerValue += total;
        customersWithSales++;
      }
      intermediate.add(
        _IntermediateInsight(
          id: id,
          name: client['nombre']?.toString() ?? 'Cliente',
          count: count,
          total: total,
          average: average,
          outstanding: outstandingByClient[id] ?? zero,
          lastPurchase: last,
          averageDays: avgDays,
          nextExpected: next,
        ),
      );
    }
    final averageCustomerValue = customersWithSales == 0
        ? zero
        : totalCustomerValue / customersWithSales;
    final now = DateTime.now();
    final insights = <CrmCustomerInsight>[];
    for (final item in intermediate) {
      final daysSinceLast = item.lastPurchase == null
          ? 99999
          : now.difference(item.lastPurchase!).inDays;
      String segment;
      if (item.outstanding.minorUnits > 0 && daysSinceLast >= 30) {
        segment = 'En riesgo';
      } else if (item.count >= 3 &&
          item.total.minorUnits >= averageCustomerValue.minorUnits * 2) {
        segment = 'VIP';
      } else if (item.count >= 4 && daysSinceLast <= 60) {
        segment = 'Frecuente';
      } else if (item.count == 0 || daysSinceLast >= 60) {
        segment = 'Inactivo';
      } else {
        segment = 'Activo';
      }
      insights.add(
        CrmCustomerInsight(
          clientId: item.id,
          name: item.name,
          salesCount: item.count,
          totalSales: item.total,
          averageTicket: item.average,
          outstanding: item.outstanding,
          lastPurchase: item.lastPurchase,
          averageDaysBetweenPurchases: item.averageDays,
          nextExpectedPurchase: item.nextExpected,
          segment: segment,
        ),
      );
    }
    insights.sort((a, b) {
      const order = {'VIP': 0, 'En riesgo': 1, 'Inactivo': 2, 'Frecuente': 3, 'Activo': 4};
      final cmp = (order[a.segment] ?? 9).compareTo(order[b.segment] ?? 9);
      return cmp != 0 ? cmp : b.totalSales.minorUnits.compareTo(a.totalSales.minorUnits);
    });
    return CrmCustomerIntelligenceSnapshot(
      currency: currency,
      customers: insights,
      averageCustomerValue: averageCustomerValue,
    );
  }

  double? _averageDays(List<DateTime> dates) {
    if (dates.length < 2) return null;
    var total = 0;
    for (var i = 1; i < dates.length; i++) {
      total += dates[i].difference(dates[i - 1]).inDays.abs();
    }
    return total / (dates.length - 1);
  }
}

class _IntermediateInsight {
  const _IntermediateInsight({
    required this.id,
    required this.name,
    required this.count,
    required this.total,
    required this.average,
    required this.outstanding,
    required this.lastPurchase,
    required this.averageDays,
    required this.nextExpected,
  });

  final int id;
  final String name;
  final int count;
  final MoneyValue total;
  final MoneyValue average;
  final MoneyValue outstanding;
  final DateTime? lastPurchase;
  final double? averageDays;
  final DateTime? nextExpected;
}
