import '../../core/currency/money_value.dart';
import '../../core/events/domain_event.dart';

enum SalesDocumentType {
  quotation,
  salesOrder,
  invoice,
  posTransaction,
  creditNote,
  returnDocument,
}

enum SalesDocumentState {
  draft,
  pending,
  approved,
  posted,
  cancelled,
  reversed,
}

class MoneyAmount {
  const MoneyAmount(this.value);

  final MoneyValue value;
  String get currency => value.currencyCode;

  MoneyAmount operator +(MoneyAmount other) {
    return MoneyAmount(value + other.value);
  }

  MoneyAmount operator -(MoneyAmount other) {
    return MoneyAmount(value - other.value);
  }

  bool get isZero => value.minorUnits == 0;

  Map<String, Object?> toMap() => value.toWireMap();
}

class SalesDocumentLine {
  const SalesDocumentLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.taxTotal,
    this.warehouseId = 1,
  });

  final int productId;
  final String productName;
  final double quantity;
  final MoneyValue unitPrice;
  final MoneyValue discount;
  final double taxRate;
  final MoneyValue taxTotal;
  final int warehouseId;

  MoneyValue get subtotal =>
      unitPrice.multiplyDecimal(quantity.toString()) - discount;
  MoneyValue get total => subtotal + taxTotal;

  Map<String, Object?> toMap() => {
    'product_id': productId,
    'product': productName,
    'quantity': quantity,
    'unit_price': unitPrice.toSql(),
    'discount': discount.toSql(),
    'tax_rate': taxRate,
    'tax_total': taxTotal.toSql(),
    'subtotal': subtotal.toSql(),
    'total': total.toSql(),
    'warehouse_id': warehouseId,
  };
}

class SalesPaymentTerm {
  const SalesPaymentTerm({
    required this.method,
    required this.dueDate,
    this.creditDays = 0,
  });

  final String method;
  final DateTime dueDate;
  final int creditDays;

  bool get isCredit =>
      creditDays > 0 || method.toUpperCase().trim() == 'CREDITO';

  Map<String, Object?> toMap() => {
    'method': method,
    'due_date': dueDate.toIso8601String(),
    'credit_days': creditDays,
  };
}

class SalesDocument {
  const SalesDocument({
    this.id,
    required this.companyId,
    required this.branchId,
    required this.warehouseId,
    required this.costCenterId,
    required this.type,
    required this.state,
    required this.customerId,
    required this.customerName,
    required this.issueDate,
    required this.paymentTerm,
    required this.lines,
    this.approvedBy,
    this.postedAt,
    this.reversedDocumentId,
    this.correlationId,
  });

  final int? id;
  final int companyId;
  final int branchId;
  final int warehouseId;
  final int costCenterId;
  final SalesDocumentType type;
  final SalesDocumentState state;
  final int? customerId;
  final String customerName;
  final DateTime issueDate;
  final SalesPaymentTerm paymentTerm;
  final List<SalesDocumentLine> lines;
  final String? approvedBy;
  final DateTime? postedAt;
  final int? reversedDocumentId;
  final String? correlationId;

  MoneyValue get subtotal => _sum((line) => line.subtotal);
  MoneyValue get taxTotal => _sum((line) => line.taxTotal);
  MoneyValue get discountTotal => _sum((line) => line.discount);
  MoneyValue get total => subtotal + taxTotal;

  MoneyValue _sum(MoneyValue Function(SalesDocumentLine line) selector) {
    if (lines.isEmpty) {
      throw StateError('Un documento comercial requiere al menos una linea.');
    }
    final zero = MoneyValue(
      minorUnits: 0,
      currency: lines.first.unitPrice.currency,
    );
    return lines.fold(zero, (sum, line) => sum + selector(line));
  }

  bool get immutable =>
      state == SalesDocumentState.posted ||
      state == SalesDocumentState.reversed;

  SalesDocument approve(String userId) {
    _ensureTransition(SalesDocumentState.approved);
    return _copy(state: SalesDocumentState.approved, approvedBy: userId);
  }

  SalesDocument markPending() {
    _ensureTransition(SalesDocumentState.pending);
    return _copy(state: SalesDocumentState.pending);
  }

  SalesDocument post() {
    _ensureTransition(SalesDocumentState.posted);
    return _copy(state: SalesDocumentState.posted, postedAt: DateTime.now());
  }

  SalesDocument cancel() {
    _ensureTransition(SalesDocumentState.cancelled);
    return _copy(state: SalesDocumentState.cancelled);
  }

  SalesDocument reverse({required int reversalDocumentId}) {
    _ensureTransition(SalesDocumentState.reversed);
    return _copy(
      state: SalesDocumentState.reversed,
      reversedDocumentId: reversalDocumentId,
    );
  }

  List<DomainEvent> postedEvents({String? userId}) => [
    SalePostedEvent(
      saleId: id ?? 0,
      companyId: companyId,
      branchId: branchId,
      warehouseId: warehouseId,
      costCenterId: costCenterId,
      customerId: customerId,
      total: total,
      tax: taxTotal,
      userId: userId,
      correlationId: correlationId,
    ),
    TaxCalculatedEvent(
      documentType: type.name,
      documentId: id ?? 0,
      companyId: companyId,
      branchId: branchId,
      taxableBase: subtotal,
      tax: taxTotal,
      correlationId: correlationId,
    ),
  ];

  Map<String, Object?> toMap() => {
    'id': id,
    'company_id': companyId,
    'branch_id': branchId,
    'warehouse_id': warehouseId,
    'cost_center_id': costCenterId,
    'type': type.name,
    'state': state.name,
    'customer_id': customerId,
    'customer': customerName,
    'issue_date': issueDate.toIso8601String(),
    'payment_term': paymentTerm.toMap(),
    'subtotal': subtotal.toSql(),
    'discount_total': discountTotal.toSql(),
    'tax_total': taxTotal.toSql(),
    'total': total.toSql(),
    'approved_by': approvedBy,
    'posted_at': postedAt?.toIso8601String(),
    'reversed_document_id': reversedDocumentId,
    'correlation_id': correlationId,
    'lines': lines.map((line) => line.toMap()).toList(),
  };

  void assertEditable() {
    if (immutable) {
      throw StateError(
        'Los documentos posted/reversed son inmutables; use reversos.',
      );
    }
  }

  void validate() {
    if (lines.isEmpty) {
      throw StateError('El documento comercial requiere lineas.');
    }
    if (customerName.trim().isEmpty) {
      throw StateError('El cliente es obligatorio.');
    }
    if (lines.any(
      (line) => line.quantity <= 0 || line.unitPrice.minorUnits < 0,
    )) {
      throw StateError('Las lineas deben tener cantidades y precios validos.');
    }
  }

  void _ensureTransition(SalesDocumentState next) {
    final allowed = switch (state) {
      SalesDocumentState.draft => {
        SalesDocumentState.pending,
        SalesDocumentState.approved,
        SalesDocumentState.cancelled,
      },
      SalesDocumentState.pending => {
        SalesDocumentState.approved,
        SalesDocumentState.cancelled,
      },
      SalesDocumentState.approved => {
        SalesDocumentState.posted,
        SalesDocumentState.cancelled,
      },
      SalesDocumentState.posted => {SalesDocumentState.reversed},
      SalesDocumentState.cancelled => <SalesDocumentState>{},
      SalesDocumentState.reversed => <SalesDocumentState>{},
    };
    if (!allowed.contains(next)) {
      throw StateError(
        'Transicion de venta no permitida: ${state.name} -> ${next.name}.',
      );
    }
  }

  SalesDocument _copy({
    int? id,
    SalesDocumentState? state,
    String? approvedBy,
    DateTime? postedAt,
    int? reversedDocumentId,
  }) {
    return SalesDocument(
      id: id ?? this.id,
      companyId: companyId,
      branchId: branchId,
      warehouseId: warehouseId,
      costCenterId: costCenterId,
      type: type,
      state: state ?? this.state,
      customerId: customerId,
      customerName: customerName,
      issueDate: issueDate,
      paymentTerm: paymentTerm,
      lines: lines,
      approvedBy: approvedBy ?? this.approvedBy,
      postedAt: postedAt ?? this.postedAt,
      reversedDocumentId: reversedDocumentId ?? this.reversedDocumentId,
      correlationId: correlationId,
    );
  }
}

class SalePostedEvent extends IntegrationEvent {
  SalePostedEvent({
    required int saleId,
    required int companyId,
    required int branchId,
    required int warehouseId,
    required int costCenterId,
    required MoneyValue total,
    required MoneyValue tax,
    int? customerId,
    String? userId,
    String? correlationId,
  }) : super(
         name: 'SalePostedEvent',
         payload: {
           'aggregate_type': 'sales_document',
           'aggregate_id': saleId.toString(),
           'sale_id': saleId,
           'company_id': companyId,
           'branch_id': branchId,
           'warehouse_id': warehouseId,
           'cost_center_id': costCenterId,
           'customer_id': customerId,
           'total': total.toWireMap(),
           'tax': tax.toWireMap(),
           'user_id': userId,
           'correlation_id': correlationId,
         },
       );
}

class InvoicePaidEvent extends IntegrationEvent {
  InvoicePaidEvent({
    required int invoiceId,
    required int companyId,
    required int branchId,
    required double amount,
    String? correlationId,
  }) : super(
         name: 'InvoicePaidEvent',
         payload: {
           'aggregate_type': 'sales_document',
           'aggregate_id': invoiceId.toString(),
           'invoice_id': invoiceId,
           'company_id': companyId,
           'branch_id': branchId,
           'amount': amount,
           'correlation_id': correlationId,
         },
       );
}

class TaxCalculatedEvent extends IntegrationEvent {
  TaxCalculatedEvent({
    required String documentType,
    required int documentId,
    required int companyId,
    required int branchId,
    required MoneyValue taxableBase,
    required MoneyValue tax,
    String? correlationId,
  }) : super(
         name: 'TaxCalculatedEvent',
         payload: {
           'aggregate_type': 'tax_calculation',
           'aggregate_id': '$documentType:$documentId',
           'document_type': documentType,
           'document_id': documentId,
           'company_id': companyId,
           'branch_id': branchId,
           'taxable_base': taxableBase.toWireMap(),
           'tax': tax.toWireMap(),
           'correlation_id': correlationId,
         },
       );
}
