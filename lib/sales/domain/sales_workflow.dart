enum SalesStage {
  quote,
  order,
  delivery,
  invoice,
  receivable,
  collection,
  creditNote,
  closed,
}

enum SalesWorkflowStatus { completed, current, pending, blocked }

class SalesSnapshot {
  const SalesSnapshot({
    this.quoted = false,
    this.ordered = false,
    this.delivered = false,
    this.invoiced = false,
    this.receivableCreated = false,
    this.collected = false,
    this.creditNoteIssued = false,
    this.closed = false,
    this.creditSale = false,
  });

  final bool quoted;
  final bool ordered;
  final bool delivered;
  final bool invoiced;
  final bool receivableCreated;
  final bool collected;
  final bool creditNoteIssued;
  final bool closed;
  final bool creditSale;
}

class SalesWorkflowStep {
  const SalesWorkflowStep({
    required this.stage,
    required this.label,
    required this.status,
    required this.description,
  });

  final SalesStage stage;
  final String label;
  final SalesWorkflowStatus status;
  final String description;

  Map<String, Object?> toMap() => {
    'stage': stage.name,
    'label': label,
    'status': status.name,
    'description': description,
  };
}

class SalesWorkflowService {
  const SalesWorkflowService();

  List<SalesWorkflowStep> build(SalesSnapshot snapshot) {
    final stages = [
      SalesStage.quote,
      SalesStage.order,
      SalesStage.delivery,
      SalesStage.invoice,
      if (snapshot.creditSale) SalesStage.receivable,
      SalesStage.collection,
      if (snapshot.creditNoteIssued) SalesStage.creditNote,
      SalesStage.closed,
    ];
    final completed = <SalesStage>{
      if (snapshot.quoted) SalesStage.quote,
      if (snapshot.ordered) SalesStage.order,
      if (snapshot.delivered) SalesStage.delivery,
      if (snapshot.invoiced) SalesStage.invoice,
      if (!snapshot.creditSale || snapshot.receivableCreated)
        SalesStage.receivable,
      if (snapshot.collected) SalesStage.collection,
      if (snapshot.creditNoteIssued) SalesStage.creditNote,
      if (snapshot.closed) SalesStage.closed,
    };
    final current = stages.firstWhere(
      (stage) => !completed.contains(stage),
      orElse: () => SalesStage.closed,
    );

    return stages
        .map(
          (stage) => SalesWorkflowStep(
            stage: stage,
            label: _label(stage),
            status: _status(stage, completed, current, snapshot),
            description: _description(stage),
          ),
        )
        .toList();
  }

  SalesWorkflowStatus _status(
    SalesStage stage,
    Set<SalesStage> completed,
    SalesStage current,
    SalesSnapshot snapshot,
  ) {
    if (completed.contains(stage)) return SalesWorkflowStatus.completed;
    if (stage == SalesStage.collection &&
        snapshot.creditSale &&
        !snapshot.receivableCreated) {
      return SalesWorkflowStatus.blocked;
    }
    if (stage == current) return SalesWorkflowStatus.current;
    return SalesWorkflowStatus.pending;
  }

  String _label(SalesStage stage) {
    switch (stage) {
      case SalesStage.quote:
        return 'Cotizacion';
      case SalesStage.order:
        return 'Pedido';
      case SalesStage.delivery:
        return 'Remision';
      case SalesStage.invoice:
        return 'Factura';
      case SalesStage.receivable:
        return 'Cuenta por cobrar';
      case SalesStage.collection:
        return 'Recaudo';
      case SalesStage.creditNote:
        return 'Nota credito';
      case SalesStage.closed:
        return 'Cierre';
    }
  }

  String _description(SalesStage stage) {
    switch (stage) {
      case SalesStage.quote:
        return 'Oferta comercial sin impacto contable.';
      case SalesStage.order:
        return 'Compromiso comercial y reserva operativa.';
      case SalesStage.delivery:
        return 'Salida fisica o remision al cliente.';
      case SalesStage.invoice:
        return 'Documento de venta con impuestos y asiento.';
      case SalesStage.receivable:
        return 'Cartera creada para ventas a credito.';
      case SalesStage.collection:
        return 'Ingreso a caja o banco y cruce de cartera.';
      case SalesStage.creditNote:
        return 'Reversion comercial, fiscal y contable.';
      case SalesStage.closed:
        return 'Documento revisado y bloqueado para auditoria.';
    }
  }
}
