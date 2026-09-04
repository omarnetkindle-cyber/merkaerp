enum ProcurementStage {
  requisition,
  approval,
  purchaseOrder,
  receipt,
  supplierInvoice,
  payable,
  payment,
  returnDocument,
  closed,
}

enum WorkflowStepStatus { completed, current, pending, blocked }

class ProcurementSnapshot {
  const ProcurementSnapshot({
    this.requested = false,
    this.approved = false,
    this.ordered = false,
    this.received = false,
    this.invoiced = false,
    this.payableCreated = false,
    this.paid = false,
    this.returned = false,
    this.closed = false,
    this.requiresApproval = true,
  });

  final bool requested;
  final bool approved;
  final bool ordered;
  final bool received;
  final bool invoiced;
  final bool payableCreated;
  final bool paid;
  final bool returned;
  final bool closed;
  final bool requiresApproval;
}

class ProcurementWorkflowStep {
  const ProcurementWorkflowStep({
    required this.stage,
    required this.label,
    required this.status,
    required this.description,
  });

  final ProcurementStage stage;
  final String label;
  final WorkflowStepStatus status;
  final String description;

  Map<String, Object?> toMap() => {
    'stage': stage.name,
    'label': label,
    'status': status.name,
    'description': description,
  };
}

class ProcurementWorkflowService {
  const ProcurementWorkflowService();

  List<ProcurementWorkflowStep> build(ProcurementSnapshot snapshot) {
    final completed = <ProcurementStage>{
      if (snapshot.requested) ProcurementStage.requisition,
      if (!snapshot.requiresApproval || snapshot.approved)
        ProcurementStage.approval,
      if (snapshot.ordered) ProcurementStage.purchaseOrder,
      if (snapshot.received) ProcurementStage.receipt,
      if (snapshot.invoiced) ProcurementStage.supplierInvoice,
      if (snapshot.payableCreated) ProcurementStage.payable,
      if (snapshot.paid) ProcurementStage.payment,
      if (snapshot.returned) ProcurementStage.returnDocument,
      if (snapshot.closed) ProcurementStage.closed,
    };

    final stages = [
      ProcurementStage.requisition,
      if (snapshot.requiresApproval) ProcurementStage.approval,
      ProcurementStage.purchaseOrder,
      ProcurementStage.receipt,
      ProcurementStage.supplierInvoice,
      ProcurementStage.payable,
      ProcurementStage.payment,
      if (snapshot.returned) ProcurementStage.returnDocument,
      ProcurementStage.closed,
    ];

    final current = stages.firstWhere(
      (stage) => !completed.contains(stage),
      orElse: () => ProcurementStage.closed,
    );

    return stages
        .map(
          (stage) => ProcurementWorkflowStep(
            stage: stage,
            label: _label(stage),
            status: _status(stage, completed, current, snapshot),
            description: _description(stage),
          ),
        )
        .toList();
  }

  WorkflowStepStatus _status(
    ProcurementStage stage,
    Set<ProcurementStage> completed,
    ProcurementStage current,
    ProcurementSnapshot snapshot,
  ) {
    if (completed.contains(stage)) return WorkflowStepStatus.completed;
    if (stage == ProcurementStage.payment && !snapshot.payableCreated) {
      return WorkflowStepStatus.blocked;
    }
    if (stage == current) return WorkflowStepStatus.current;
    return WorkflowStepStatus.pending;
  }

  String _label(ProcurementStage stage) {
    switch (stage) {
      case ProcurementStage.requisition:
        return 'Solicitud';
      case ProcurementStage.approval:
        return 'Aprobacion';
      case ProcurementStage.purchaseOrder:
        return 'Orden de compra';
      case ProcurementStage.receipt:
        return 'Recepcion';
      case ProcurementStage.supplierInvoice:
        return 'Factura proveedor';
      case ProcurementStage.payable:
        return 'Cuenta por pagar';
      case ProcurementStage.payment:
        return 'Pago';
      case ProcurementStage.returnDocument:
        return 'Devolucion';
      case ProcurementStage.closed:
        return 'Cierre';
    }
  }

  String _description(ProcurementStage stage) {
    switch (stage) {
      case ProcurementStage.requisition:
        return 'Necesidad interna y productos solicitados.';
      case ProcurementStage.approval:
        return 'Validacion de presupuesto, proveedor y autorizacion.';
      case ProcurementStage.purchaseOrder:
        return 'Compromiso formal con proveedor.';
      case ProcurementStage.receipt:
        return 'Entrada fisica al inventario o bodega.';
      case ProcurementStage.supplierInvoice:
        return 'Documento fiscal recibido del proveedor.';
      case ProcurementStage.payable:
        return 'Obligacion reconocida en cuentas por pagar.';
      case ProcurementStage.payment:
        return 'Salida de caja o banco y cruce de saldo.';
      case ProcurementStage.returnDocument:
        return 'Reversion parcial o total de recepcion/factura.';
      case ProcurementStage.closed:
        return 'Documento revisado, contabilizado y bloqueado.';
    }
  }
}
