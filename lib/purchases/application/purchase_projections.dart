import '../../core/database/database_gateway.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/event_store.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class PurchaseAnalyticsProjection implements EventProjection {
  PurchaseAnalyticsProjection({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
  }) : _gateway = gateway;

  final DatabaseGateway _gateway;

  @override
  String get name => 'purchase_analytics';

  @override
  Future<void> apply(EventEnvelope event) async {
    if (!_supported.contains(event.name)) return;
    final totalValue = event.payload['total'] ?? event.payload['amount'];
    if (totalValue == null) return;
    final sign = event.name == 'PurchaseReversedEvent' ? -1 : 1;
    final total = _money(totalValue);
    final zero = MoneyValue(minorUnits: 0, currency: total.currency);
    final spend = total * sign;
    final tax =
        (event.payload['tax'] == null ? zero : _money(event.payload['tax'])) *
        sign;
    final retention =
        (event.payload['retention'] == null
            ? zero
            : _money(event.payload['retention'])) *
        sign;
    await _gateway.insert('purchase_analytics_read_model', {
      'company_id': event.companyId,
      'branch_id': event.branchId,
      'document_id':
          event.payload['purchase_id']?.toString() ?? event.aggregateId,
      'event_name': event.name,
      'spend': spend.toSql(),
      'tax': tax.toSql(),
      'retention': retention.toSql(),
      'occurred_at': event.occurredAt.toIso8601String(),
      'correlation_id': event.correlationId,
    });
  }

  static const _supported = {
    'PurchaseApprovedEvent',
    'GoodsReceivedEvent',
    'SupplierInvoicePostedEvent',
    'PurchaseReversedEvent',
    'SupplierBalanceUpdatedEvent',
    'purchases.approved',
  };

  MoneyValue _money(Object? value) {
    if (value is! Map) {
      throw StateError('El evento de compra no contiene dinero tipado.');
    }
    final code = value['currency']?.toString().trim();
    final scale = int.tryParse(value['scale']?.toString() ?? '');
    final minorUnits = int.tryParse(value['minor_units']?.toString() ?? '');
    if (code == null || code.isEmpty || scale == null || minorUnits == null) {
      throw StateError('El importe del evento de compra es invalido.');
    }
    return MoneyValue(
      minorUnits: minorUnits,
      currency: Currency(
        code: code,
        name: code,
        symbol: '',
        decimalPlaces: scale,
      ),
    );
  }
}
