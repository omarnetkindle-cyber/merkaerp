abstract class DomainEvent {
  const DomainEvent({
    required this.name,
    required this.occurredAt,
    required this.payload,
  });

  final String name;
  final DateTime occurredAt;
  final Map<String, Object?> payload;

  Map<String, Object?> toMap() => {
    'name': name,
    'occurred_at': occurredAt.toIso8601String(),
    'payload': payload,
  };
}

class IntegrationEvent extends DomainEvent {
  IntegrationEvent({
    required super.name,
    required super.payload,
    DateTime? occurredAt,
  }) : super(occurredAt: occurredAt ?? DateTime.now());
}

abstract class DomainEventPublisher {
  Future<void> publish(DomainEvent event);
}

abstract class DomainEventListener {
  bool supports(DomainEvent event);

  Future<void> handle(DomainEvent event);
}

class InMemoryDomainEventBus implements DomainEventPublisher {
  InMemoryDomainEventBus({List<DomainEventListener> listeners = const []})
    : _listeners = listeners;

  final List<DomainEvent> _events = [];
  final List<DomainEventListener> _listeners;

  List<DomainEvent> get events => List.unmodifiable(_events);

  @override
  Future<void> publish(DomainEvent event) async {
    _events.add(event);
    for (final listener in _listeners) {
      if (listener.supports(event)) {
        await listener.handle(event);
      }
    }
  }
}

class NoopDomainEventPublisher implements DomainEventPublisher {
  const NoopDomainEventPublisher();

  @override
  Future<void> publish(DomainEvent event) async {}
}

class SaleCreatedEvent extends IntegrationEvent {
  SaleCreatedEvent({
    required int saleId,
    required double total,
    required int companyId,
    int? branchId,
    String? requestId,
  }) : super(
         name: 'sales.created',
         payload: {
           'sale_id': saleId,
           'total': total,
           'company_id': companyId,
           'branch_id': branchId,
           'request_id': requestId,
         },
       );
}

class PurchaseApprovedEvent extends IntegrationEvent {
  PurchaseApprovedEvent({
    required int purchaseId,
    required double total,
    required int companyId,
    int? branchId,
    String? approvedBy,
  }) : super(
         name: 'purchases.approved',
         payload: {
           'purchase_id': purchaseId,
           'total': total,
           'company_id': companyId,
           'branch_id': branchId,
           'approved_by': approvedBy,
         },
       );
}

class InvoiceCancelledEvent extends IntegrationEvent {
  InvoiceCancelledEvent({
    required String invoiceType,
    required int invoiceId,
    required int companyId,
    int? branchId,
    String? reason,
  }) : super(
         name: 'invoices.cancelled',
         payload: {
           'invoice_type': invoiceType,
           'invoice_id': invoiceId,
           'company_id': companyId,
           'branch_id': branchId,
           'reason': reason,
         },
       );
}

class InventoryAdjustedEvent extends IntegrationEvent {
  InventoryAdjustedEvent({
    required int productId,
    required double quantity,
    required int companyId,
    int? branchId,
    int? warehouseId,
    String? reason,
  }) : super(
         name: 'inventory.adjusted',
         payload: {
           'product_id': productId,
           'quantity': quantity,
           'company_id': companyId,
           'branch_id': branchId,
           'warehouse_id': warehouseId,
           'reason': reason,
         },
       );
}

class PaymentRegisteredEvent extends IntegrationEvent {
  PaymentRegisteredEvent({
    required String paymentType,
    required int documentId,
    required double amount,
    required int companyId,
    int? branchId,
  }) : super(
         name: 'payments.registered',
         payload: {
           'payment_type': paymentType,
           'document_id': documentId,
           'amount': amount,
           'company_id': companyId,
           'branch_id': branchId,
         },
       );
}
