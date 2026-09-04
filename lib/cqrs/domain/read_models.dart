import '../../core/currency/money_value.dart';

class KpiMetric {
  const KpiMetric({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final MoneyValue value;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'key': key,
    'value': value.toSql(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class ExecutiveDashboardReadModel {
  const ExecutiveDashboardReadModel({
    required this.companyId,
    required this.branchId,
    required this.metrics,
  });

  final int companyId;
  final int branchId;
  final List<KpiMetric> metrics;

  MoneyValue value(String key) {
    if (metrics.isEmpty) {
      throw StateError('A currency-resolved KPI metric is required');
    }
    return metrics
        .where((metric) => metric.key == key)
        .fold<MoneyValue>(
          MoneyValue(minorUnits: 0, currency: metrics.first.value.currency),
          (sum, metric) => sum + metric.value,
        );
  }

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'branch_id': branchId,
    'metrics': metrics.map((metric) => metric.toMap()).toList(),
    'summary': {
      'sales_total': value('sales_total').toWireMap(),
      'purchases_total': value('purchases_total').toWireMap(),
      'inventory_adjustments': value('inventory_adjustments').toWireMap(),
      'payments_total': value('payments_total').toWireMap(),
    },
  };
}
