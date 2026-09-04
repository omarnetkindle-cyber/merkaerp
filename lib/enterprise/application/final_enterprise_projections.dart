import '../../core/database/database_gateway.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/event_store.dart';

class FinalEnterpriseProjection implements EventProjection {
  FinalEnterpriseProjection({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
  }) : _gateway = gateway;

  final DatabaseGateway _gateway;

  @override
  String get name => 'final_enterprise_projection';

  @override
  Future<void> apply(EventEnvelope event) async {
    switch (event.name) {
      case 'SalePostedEvent':
        await _insertMetric(event, 'ar_created', _amount(event, 'total'));
        break;
      case 'InvoicePaidEvent':
        await _insertMetric(event, 'ar_collected', _amount(event, 'amount'));
        break;
      case 'SupplierInvoicePostedEvent':
        await _insertMetric(event, 'ap_created', _amount(event, 'total'));
        break;
      case 'TreasuryTransferCreatedEvent':
        await _insertMetric(
          event,
          'treasury_transfers',
          _amount(event, 'amount'),
        );
        break;
      case 'BankReconciledEvent':
        await _insertMetric(
          event,
          'bank_reconciliations',
          _amount(event, 'matched'),
        );
        break;
      case 'AssetDepreciatedEvent':
        await _insertMetric(
          event,
          'asset_depreciation',
          _amount(event, 'depreciation'),
        );
        break;
      case 'TaxCalculatedEvent':
        await _insertMetric(event, 'tax_calculated', _amount(event, 'tax'));
        break;
      case 'ReportGeneratedEvent':
        await _insertMetric(event, 'reports_generated', 1);
        break;
    }
  }

  Future<void> _insertMetric(
    EventEnvelope event,
    String metric,
    int value,
  ) async {
    await _gateway.insert('enterprise_event_metrics', {
      'company_id': event.companyId,
      'branch_id': event.branchId,
      'metric_key': metric,
      'metric_value': value,
      'event_name': event.name,
      'correlation_id': event.correlationId,
      'created_at': event.occurredAt.toIso8601String(),
    });
  }

  int _amount(EventEnvelope event, String key) {
    final value = event.payload[key];
    if (value is Map) {
      return (value['minor_units'] as num?)?.toInt() ?? 0;
    }
    return (value as num?)?.toInt() ??
        int.tryParse(value?.toString() ?? '') ??
        0;
  }
}
