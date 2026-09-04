import '../../core/database/database_gateway.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/event_store.dart';

class SalesAnalyticsProjection implements EventProjection {
  SalesAnalyticsProjection({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
  }) : _gateway = gateway;

  final DatabaseGateway _gateway;

  @override
  String get name => 'sales_analytics';

  @override
  Future<void> apply(EventEnvelope event) async {
    if (event.name != 'SalePostedEvent' && event.name != 'sales.reversed') {
      return;
    }
    final amount = _money(event.payload['total']);
    final tax = _money(event.payload['tax']);
    final saleId = event.payload['sale_id']?.toString() ?? event.aggregateId;
    final sign = event.name == 'sales.reversed' ? -1 : 1;
    await _gateway.insert('sales_analytics_read_model', {
      'company_id': event.companyId,
      'branch_id': event.branchId,
      'document_id': saleId,
      'event_name': event.name,
      'revenue': (amount * sign).toSql(),
      'tax': (tax * sign).toSql(),
      'occurred_at': event.occurredAt.toIso8601String(),
      'correlation_id': event.correlationId,
    });
  }

  MoneyValue _money(Object? value) {
    if (value is! Map) {
      throw StateError('Sales analytics requires a MoneyValue wire payload.');
    }
    final code = value['currency']?.toString().trim() ?? '';
    final minorUnits = value['minor_units'];
    final scale = (value['scale'] as num?)?.toInt() ?? 2;
    if (code.isEmpty || minorUnits is! int) {
      throw StateError('Invalid monetary payload in sales analytics.');
    }
    return MoneyValue(
      minorUnits: minorUnits,
      currency: Currency(
        code: code,
        name: code,
        symbol: code,
        decimalPlaces: scale,
      ),
    );
  }
}
