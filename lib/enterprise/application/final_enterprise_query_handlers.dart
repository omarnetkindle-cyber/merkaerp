import '../data/final_enterprise_repository.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class FinalEnterpriseQueryHandlers {
  FinalEnterpriseQueryHandlers({required FinalEnterpriseRepository repository})
    : _repository = repository;

  final FinalEnterpriseRepository _repository;

  Future<List<Map<String, Object?>>> arLedger({int? customerId}) async {
    final rows = await _repository.queryScoped(
      'ar_ledger_entries',
      where: customerId == null ? null : 'customer_id = ?',
      whereArgs: customerId == null ? null : [customerId],
      orderBy: 'occurred_at DESC',
      limit: 500,
    );
    return rows;
  }

  Future<Map<String, Object?>> arAging() =>
      _aging(table: 'ar_ledger_entries', openField: 'open_amount');

  Future<List<Map<String, Object?>>> apLedger({int? supplierId}) async {
    final rows = await _repository.queryScoped(
      'ap_supplier_ledger',
      where: supplierId == null ? null : 'supplier_id = ?',
      whereArgs: supplierId == null ? null : [supplierId],
      orderBy: 'occurred_at DESC',
      limit: 500,
    );
    return rows;
  }

  Future<Map<String, Object?>> apAging() =>
      _aging(table: 'ap_supplier_ledger', openField: 'open_amount');

  Future<Map<String, Object?>> treasuryDashboard() async {
    final currency = await _repository.currency();
    final accounts = await _repository.queryScoped('treasury_bank_accounts');
    final movements = await _repository.queryScoped('treasury_bank_movements');
    final balance = accounts.fold<MoneyValue>(
      MoneyValue(minorUnits: 0, currency: currency),
      (sum, row) => sum + _moneySql(row['balance'], currency),
    );
    final inflow = movements
        .where((row) => row['direction'] == 'in')
        .fold<MoneyValue>(
          MoneyValue(minorUnits: 0, currency: currency),
          (sum, row) => sum + _moneySql(row['amount'], currency),
        );
    final outflow = movements
        .where((row) => row['direction'] == 'out')
        .fold<MoneyValue>(
          MoneyValue(minorUnits: 0, currency: currency),
          (sum, row) => sum + _moneySql(row['amount'], currency),
        );
    return {
      'bank_accounts': accounts.length,
      'treasury_position': balance.toWireMap(),
      'projected_cash_flow': (balance + inflow - outflow).toWireMap(),
      'inflow': inflow.toWireMap(),
      'outflow': outflow.toWireMap(),
    };
  }

  Future<List<Map<String, Object?>>> unmatchedBankOperations() async {
    return _repository.queryScoped(
      'bank_statement_lines',
      where: 'status = ?',
      whereArgs: ['unmatched'],
      orderBy: 'movement_date DESC',
      limit: 500,
    );
  }

  Future<List<Map<String, Object?>>> assets() async {
    return _repository.queryScoped(
      'enterprise_fixed_assets',
      orderBy: 'acquired_at DESC',
      limit: 500,
    );
  }

  Future<Map<String, Object?>> crmPipeline() async {
    final currency = await _repository.currency();
    final rows = await _repository.queryScoped('crm_opportunities');
    final totals = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final stage = row['stage']?.toString() ?? 'lead';
      final previous = totals[stage] == null
          ? MoneyValue(minorUnits: 0, currency: currency)
          : MoneyValue.fromSql(
              totals[stage]!['minor_units'],
              currency: currency,
            );
      totals[stage] = (previous + _moneySql(row['value'], currency))
          .toWireMap();
    }
    return {'count': rows.length, 'value_by_stage': totals, 'items': rows};
  }

  Future<List<Map<String, Object?>>> materializedReports() {
    return _repository.queryScoped(
      'materialized_reports',
      orderBy: 'created_at DESC',
      limit: 200,
    );
  }

  Future<Map<String, Object?>> _aging({
    required String table,
    required String openField,
  }) async {
    final rows = await _repository.queryScoped(table);
    final currency = await _repository.currency();
    final buckets = <String, MoneyValue>{
      'current': MoneyValue(minorUnits: 0, currency: currency),
      '1_30': MoneyValue(minorUnits: 0, currency: currency),
      '31_60': MoneyValue(minorUnits: 0, currency: currency),
      '61_90': MoneyValue(minorUnits: 0, currency: currency),
      '90_plus': MoneyValue(minorUnits: 0, currency: currency),
    };
    final now = DateTime.now();
    for (final row in rows) {
      final amount = _moneySql(row[openField], currency);
      if (amount.minorUnits <= 0) continue;
      final dueDate =
          DateTime.tryParse(row['due_date']?.toString() ?? '') ?? now;
      final days = now.difference(dueDate).inDays;
      if (days <= 0) {
        buckets['current'] = buckets['current']! + amount;
      } else if (days <= 30) {
        buckets['1_30'] = buckets['1_30']! + amount;
      } else if (days <= 60) {
        buckets['31_60'] = buckets['31_60']! + amount;
      } else if (days <= 90) {
        buckets['61_90'] = buckets['61_90']! + amount;
      } else {
        buckets['90_plus'] = buckets['90_plus']! + amount;
      }
    }
    return buckets.map((key, value) => MapEntry(key, value.toWireMap()));
  }

  MoneyValue _moneySql(Object? value, Currency currency) =>
      MoneyValue.fromSql(value, currency: currency, nullableAsZero: true);
}
