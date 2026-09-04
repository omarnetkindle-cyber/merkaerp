import '../../core/currency/money_value.dart';
import '../../core/events/domain_event.dart';

enum PurchaseDocumentType {
  requisition,
  rfq,
  purchaseOrder,
  goodsReceipt,
  supplierInvoice,
  debitNote,
  returnDocument,
}

enum PurchaseDocumentState {
  draft,
  pendingApproval,
  approved,
  partiallyReceived,
  received,
  posted,
  cancelled,
  reversed,
}

class PurchaseTaxLine {
  const PurchaseTaxLine({
    required this.code,
    required this.rate,
    required this.taxableBase,
    required this.tax,
    required this.retention,
  });

  final String code;
  final double rate;
  final MoneyValue taxableBase;
  final MoneyValue tax;
  final MoneyValue retention;

  Map<String, Object?> toMap() => {
    'code': code,
    'rate': rate,
    'taxable_base': taxableBase.toSql(),
    'tax': tax.toSql(),
    'retention': retention.toSql(),
  };
}

class PurchaseDocumentLine {
  const PurchaseDocumentLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.receivedQuantity = 0,
    this.taxCode = 'EXEMPT',
    this.taxRate = 0,
    this.retentionRate = 0,
    this.warehouseId = 1,
  });

  final int productId;
  final String productName;
  final double quantity;
  final MoneyValue unitCost;
  final double receivedQuantity;
  final String taxCode;
  final double taxRate;
  final double retentionRate;
  final int warehouseId;

  MoneyValue get subtotal => unitCost.multiplyDecimal(quantity.toString());
  double get pendingQuantity => quantity - receivedQuantity;
  MoneyValue get taxTotal => subtotal.percent(taxRate.toString());
  MoneyValue get retentionTotal => subtotal.percent(retentionRate.toString());
  MoneyValue get total => subtotal + taxTotal - retentionTotal;

  PurchaseDocumentLine receive(double quantityToReceive) {
    if (quantityToReceive <= 0) {
      throw StateError('La cantidad recibida debe ser mayor a cero.');
    }
    if (quantityToReceive > pendingQuantity + 0.0001) {
      throw StateError('La recepcion excede la cantidad pendiente.');
    }
    return PurchaseDocumentLine(
      productId: productId,
      productName: productName,
      quantity: quantity,
      unitCost: unitCost,
      receivedQuantity: receivedQuantity + quantityToReceive,
      taxCode: taxCode,
      taxRate: taxRate,
      retentionRate: retentionRate,
      warehouseId: warehouseId,
    );
  }

  PurchaseDocumentLine reversed() {
    return PurchaseDocumentLine(
      productId: productId,
      productName: productName,
      quantity: -quantity,
      unitCost: unitCost,
      receivedQuantity: -receivedQuantity,
      taxCode: taxCode,
      taxRate: taxRate,
      retentionRate: retentionRate,
      warehouseId: warehouseId,
    );
  }

  Map<String, Object?> toMap() => {
    'product_id': productId,
    'product': productName,
    'quantity': quantity,
    'unit_cost': unitCost,
    'received_quantity': receivedQuantity,
    'pending_quantity': pendingQuantity,
    'tax_code': taxCode,
    'tax_rate': taxRate,
    'retention_rate': retentionRate,
    'tax_total': taxTotal,
    'retention_total': retentionTotal,
    'subtotal': subtotal,
    'total': total,
    'warehouse_id': warehouseId,
  };
}

class ApprovalStep {
  const ApprovalStep({
    required this.level,
    required this.approverRole,
    required this.slaHours,
    this.approvedBy,
    this.approvedAt,
    this.escalatedTo,
  });

  final int level;
  final String approverRole;
  final int slaHours;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? escalatedTo;

  bool get completed => approvedBy != null;

  bool expired(DateTime requestedAt, DateTime now) {
    return !completed && now.difference(requestedAt).inHours >= slaHours;
  }

  ApprovalStep approve(String userId) {
    return ApprovalStep(
      level: level,
      approverRole: approverRole,
      slaHours: slaHours,
      approvedBy: userId,
      approvedAt: DateTime.now(),
      escalatedTo: escalatedTo,
    );
  }

  ApprovalStep escalate(String role) {
    return ApprovalStep(
      level: level,
      approverRole: approverRole,
      slaHours: slaHours,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
      escalatedTo: role,
    );
  }

  Map<String, Object?> toMap() => {
    'level': level,
    'approver_role': approverRole,
    'sla_hours': slaHours,
    'approved_by': approvedBy,
    'approved_at': approvedAt?.toIso8601String(),
    'escalated_to': escalatedTo,
    'completed': completed,
  };
}

class PurchaseDocument {
  const PurchaseDocument({
    this.id,
    required this.companyId,
    required this.branchId,
    required this.warehouseId,
    required this.costCenterId,
    required this.type,
    required this.state,
    required this.supplierId,
    required this.supplierName,
    required this.issueDate,
    required this.dueDate,
    required this.country,
    required this.lines,
    this.approvals = const [],
    this.budgetCode,
    required this.budgetAvailable,
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
  final PurchaseDocumentType type;
  final PurchaseDocumentState state;
  final int supplierId;
  final String supplierName;
  final DateTime issueDate;
  final DateTime dueDate;
  final String country;
  final List<PurchaseDocumentLine> lines;
  final List<ApprovalStep> approvals;
  final String? budgetCode;
  final MoneyValue budgetAvailable;
  final String? approvedBy;
  final DateTime? postedAt;
  final int? reversedDocumentId;
  final String? correlationId;

  MoneyValue get subtotal => _sum((line) => line.subtotal);
  MoneyValue get taxTotal => _sum((line) => line.taxTotal);
  MoneyValue get retentionTotal => _sum((line) => line.retentionTotal);
  MoneyValue get total => subtotal + taxTotal - retentionTotal;

  MoneyValue _sum(MoneyValue Function(PurchaseDocumentLine line) selector) {
    if (lines.isEmpty) {
      throw StateError('Un documento de compra requiere al menos una linea.');
    }
    final zero = MoneyValue(
      minorUnits: 0,
      currency: lines.first.unitCost.currency,
    );
    return lines.fold(zero, (sum, line) => sum + selector(line));
  }

  double get receivedRatio {
    final quantity = lines.fold<double>(
      0,
      (sum, line) => sum + line.quantity.abs(),
    );
    if (quantity == 0) return 0;
    return lines.fold<double>(
          0,
          (sum, line) => sum + line.receivedQuantity.abs(),
        ) /
        quantity;
  }

  bool get immutable =>
      state == PurchaseDocumentState.posted ||
      state == PurchaseDocumentState.reversed;

  bool get fullyApproved =>
      approvals.isEmpty || approvals.every((s) => s.completed);

  List<PurchaseTaxLine> get taxLines => lines
      .map(
        (line) => PurchaseTaxLine(
          code: line.taxCode,
          rate: line.taxRate,
          taxableBase: line.subtotal,
          tax: line.taxTotal,
          retention: line.retentionTotal,
        ),
      )
      .toList();

  PurchaseDocument submitForApproval() {
    _ensureTransition(PurchaseDocumentState.pendingApproval);
    _validateBudget();
    return _copy(state: PurchaseDocumentState.pendingApproval);
  }

  PurchaseDocument approve(String userId) {
    if (state != PurchaseDocumentState.pendingApproval &&
        state != PurchaseDocumentState.draft) {
      _ensureTransition(PurchaseDocumentState.approved);
    }
    final nextApprovals = approvals.isEmpty
        ? approvals
        : _approveNextStep(userId);
    final approved =
        nextApprovals.isEmpty || nextApprovals.every((s) => s.completed);
    return _copy(
      state: approved ? PurchaseDocumentState.approved : state,
      approvals: nextApprovals,
      approvedBy: approved ? userId : approvedBy,
    );
  }

  PurchaseDocument receive(Map<int, double> quantities) {
    if (state != PurchaseDocumentState.approved &&
        state != PurchaseDocumentState.partiallyReceived) {
      throw StateError('Solo compras aprobadas pueden recibirse.');
    }
    final receivedLines = lines.map((line) {
      final quantity = quantities[line.productId] ?? 0;
      return quantity == 0 ? line : line.receive(quantity);
    }).toList();
    final updated = _copy(lines: receivedLines);
    final nextState = updated.receivedRatio >= 0.999
        ? PurchaseDocumentState.received
        : PurchaseDocumentState.partiallyReceived;
    return updated._copy(state: nextState);
  }

  PurchaseDocument post() {
    _ensureTransition(PurchaseDocumentState.posted);
    return _copy(state: PurchaseDocumentState.posted, postedAt: DateTime.now());
  }

  PurchaseDocument cancel() {
    _ensureTransition(PurchaseDocumentState.cancelled);
    return _copy(state: PurchaseDocumentState.cancelled);
  }

  PurchaseDocument reverse({required int reversalDocumentId}) {
    _ensureTransition(PurchaseDocumentState.reversed);
    return _copy(
      state: PurchaseDocumentState.reversed,
      reversedDocumentId: reversalDocumentId,
    );
  }

  PurchaseDocument escalateApprovals(DateTime now) {
    return _copy(
      approvals: approvals
          .map(
            (step) => step.expired(issueDate, now)
                ? step.escalate('administrador')
                : step,
          )
          .toList(),
    );
  }

  List<DomainEvent> approvalEvents({String? userId}) => [
    IntegrationEvent(
      name: 'PurchaseApprovedEvent',
      payload: {
        'aggregate_type': 'purchase_document',
        'aggregate_id': (id ?? 0).toString(),
        'purchase_id': id ?? 0,
        'company_id': companyId,
        'branch_id': branchId,
        'warehouse_id': warehouseId,
        'cost_center_id': costCenterId,
        'total': total.toWireMap(),
        'approved_by': userId ?? approvedBy,
        'correlation_id': correlationId,
      },
    ),
  ];

  List<DomainEvent> receiptEvents(Map<int, double> quantities) => [
    GoodsReceivedEvent(
      purchaseId: id ?? 0,
      companyId: companyId,
      branchId: branchId,
      warehouseId: warehouseId,
      quantities: quantities,
      correlationId: correlationId,
    ),
  ];

  List<DomainEvent> postedEvents() => [
    SupplierInvoicePostedEvent(
      purchaseId: id ?? 0,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      total: total,
      tax: taxTotal,
      retention: retentionTotal,
      correlationId: correlationId,
    ),
    SupplierBalanceUpdatedEvent(
      supplierId: supplierId,
      companyId: companyId,
      branchId: branchId,
      amount: total,
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
    'supplier_id': supplierId,
    'supplier': supplierName,
    'issue_date': issueDate.toIso8601String(),
    'due_date': dueDate.toIso8601String(),
    'country': country,
    'budget_code': budgetCode,
    'budget_available': budgetAvailable.toSql(),
    'subtotal': subtotal.toSql(),
    'tax_total': taxTotal.toSql(),
    'retention_total': retentionTotal.toSql(),
    'total': total.toSql(),
    'approved_by': approvedBy,
    'posted_at': postedAt?.toIso8601String(),
    'reversed_document_id': reversedDocumentId,
    'correlation_id': correlationId,
    'received_ratio': receivedRatio,
    'approvals': approvals.map((step) => step.toMap()).toList(),
    'tax_lines': taxLines.map((tax) => tax.toMap()).toList(),
    'lines': lines.map((line) => line.toMap()).toList(),
  };

  void validate() {
    if (supplierName.trim().isEmpty) {
      throw StateError('El proveedor es obligatorio.');
    }
    if (lines.isEmpty) throw StateError('La compra requiere lineas.');
    if (lines.any(
      (line) => line.quantity == 0 || line.unitCost.minorUnits < 0,
    )) {
      throw StateError(
        'Las lineas de compra deben tener cantidades y costos validos.',
      );
    }
    _validateBudget();
  }

  void assertEditable() {
    if (immutable) {
      throw StateError(
        'Las compras posted/reversed son inmutables; use reversos.',
      );
    }
  }

  List<ApprovalStep> _approveNextStep(String userId) {
    var approved = false;
    return approvals.map((step) {
      if (!approved && !step.completed) {
        approved = true;
        return step.approve(userId);
      }
      return step;
    }).toList();
  }

  void _validateBudget() {
    if (budgetCode != null &&
        budgetAvailable.minorUnits > 0 &&
        total > budgetAvailable) {
      throw StateError('Presupuesto insuficiente para $budgetCode.');
    }
  }

  void _ensureTransition(PurchaseDocumentState next) {
    final allowed = switch (state) {
      PurchaseDocumentState.draft => {
        PurchaseDocumentState.pendingApproval,
        PurchaseDocumentState.approved,
        PurchaseDocumentState.cancelled,
      },
      PurchaseDocumentState.pendingApproval => {
        PurchaseDocumentState.approved,
        PurchaseDocumentState.cancelled,
      },
      PurchaseDocumentState.approved => {
        PurchaseDocumentState.partiallyReceived,
        PurchaseDocumentState.received,
        PurchaseDocumentState.cancelled,
      },
      PurchaseDocumentState.partiallyReceived => {
        PurchaseDocumentState.received,
        PurchaseDocumentState.cancelled,
      },
      PurchaseDocumentState.received => {PurchaseDocumentState.posted},
      PurchaseDocumentState.posted => {PurchaseDocumentState.reversed},
      PurchaseDocumentState.cancelled => <PurchaseDocumentState>{},
      PurchaseDocumentState.reversed => <PurchaseDocumentState>{},
    };
    if (!allowed.contains(next)) {
      throw StateError(
        'Transicion de compra no permitida: ${state.name} -> ${next.name}.',
      );
    }
  }

  PurchaseDocument _copy({
    int? id,
    PurchaseDocumentState? state,
    List<PurchaseDocumentLine>? lines,
    List<ApprovalStep>? approvals,
    String? approvedBy,
    DateTime? postedAt,
    int? reversedDocumentId,
  }) {
    return PurchaseDocument(
      id: id ?? this.id,
      companyId: companyId,
      branchId: branchId,
      warehouseId: warehouseId,
      costCenterId: costCenterId,
      type: type,
      state: state ?? this.state,
      supplierId: supplierId,
      supplierName: supplierName,
      issueDate: issueDate,
      dueDate: dueDate,
      country: country,
      lines: lines ?? this.lines,
      approvals: approvals ?? this.approvals,
      budgetCode: budgetCode,
      budgetAvailable: budgetAvailable,
      approvedBy: approvedBy ?? this.approvedBy,
      postedAt: postedAt ?? this.postedAt,
      reversedDocumentId: reversedDocumentId ?? this.reversedDocumentId,
      correlationId: correlationId,
    );
  }
}

class GoodsReceivedEvent extends IntegrationEvent {
  GoodsReceivedEvent({
    required int purchaseId,
    required int companyId,
    required int branchId,
    required int warehouseId,
    required Map<int, double> quantities,
    String? correlationId,
  }) : super(
         name: 'GoodsReceivedEvent',
         payload: {
           'aggregate_type': 'purchase_document',
           'aggregate_id': purchaseId.toString(),
           'purchase_id': purchaseId,
           'company_id': companyId,
           'branch_id': branchId,
           'warehouse_id': warehouseId,
           'quantities': quantities.map(
             (key, value) => MapEntry('$key', value),
           ),
           'correlation_id': correlationId,
         },
       );
}

class SupplierInvoicePostedEvent extends IntegrationEvent {
  SupplierInvoicePostedEvent({
    required int purchaseId,
    required int companyId,
    required int branchId,
    required int supplierId,
    required MoneyValue total,
    required MoneyValue tax,
    required MoneyValue retention,
    String? correlationId,
  }) : super(
         name: 'SupplierInvoicePostedEvent',
         payload: {
           'aggregate_type': 'purchase_document',
           'aggregate_id': purchaseId.toString(),
           'purchase_id': purchaseId,
           'company_id': companyId,
           'branch_id': branchId,
           'supplier_id': supplierId,
           'total': total.toWireMap(),
           'tax': tax.toWireMap(),
           'retention': retention.toWireMap(),
           'correlation_id': correlationId,
         },
       );
}

class PurchaseReversedEvent extends IntegrationEvent {
  PurchaseReversedEvent({
    required int purchaseId,
    required int reversalDocumentId,
    required int companyId,
    required int branchId,
    required String reason,
    String? correlationId,
  }) : super(
         name: 'PurchaseReversedEvent',
         payload: {
           'aggregate_type': 'purchase_document',
           'aggregate_id': purchaseId.toString(),
           'purchase_id': purchaseId,
           'reversal_document_id': reversalDocumentId,
           'company_id': companyId,
           'branch_id': branchId,
           'reason': reason,
           'correlation_id': correlationId,
         },
       );
}

class SupplierBalanceUpdatedEvent extends IntegrationEvent {
  SupplierBalanceUpdatedEvent({
    required int supplierId,
    required int companyId,
    required int branchId,
    required MoneyValue amount,
    String? correlationId,
  }) : super(
         name: 'SupplierBalanceUpdatedEvent',
         payload: {
           'aggregate_type': 'supplier_balance',
           'aggregate_id': supplierId.toString(),
           'supplier_id': supplierId,
           'company_id': companyId,
           'branch_id': branchId,
           'amount': amount.toWireMap(),
           'correlation_id': correlationId,
         },
       );
}
