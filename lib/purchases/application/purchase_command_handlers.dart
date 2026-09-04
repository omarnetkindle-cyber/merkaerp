import '../../accounting/application/accounting_posting_service.dart';
import '../../accounting/domain/journal_entry.dart';
import '../../core/branch/branch_context.dart';
import '../../core/currency/money_value.dart';
import '../../core/events/domain_event.dart';
import '../../core/security/action_permission.dart';
import '../../inventory/application/stock_ledger_service.dart';
import '../../inventory/domain/stock_ledger.dart';
import '../../sync/application/sync_orchestrator.dart';
import '../../sync/domain/sync_models.dart';
import '../../telemetry/application/telemetry_service.dart';
import '../data/purchase_document_repository.dart';
import '../domain/purchase_document.dart';
import 'purchase_tax_service.dart';

class CreatePurchaseDocumentCommand {
  const CreatePurchaseDocumentCommand({
    required this.type,
    required this.supplierId,
    required this.supplierName,
    required this.lines,
    required this.userId,
    this.role,
    this.issueDate,
    this.dueDate,
    this.country = 'Colombia',
    this.budgetCode,
    required this.budgetAvailable,
    this.retentionRate = 0,
    this.correlationId,
  });

  final PurchaseDocumentType type;
  final int supplierId;
  final String supplierName;
  final List<PurchaseDocumentLine> lines;
  final String userId;
  final String? role;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String country;
  final String? budgetCode;
  final MoneyValue budgetAvailable;
  final double retentionRate;
  final String? correlationId;
}

class ApprovePurchaseDocumentCommand {
  const ApprovePurchaseDocumentCommand({
    required this.documentId,
    required this.userId,
    this.role,
  });

  final int documentId;
  final String userId;
  final String? role;
}

class ReceivePurchaseDocumentCommand {
  const ReceivePurchaseDocumentCommand({
    required this.documentId,
    required this.quantities,
    required this.userId,
    this.role,
  });

  final int documentId;
  final Map<int, double> quantities;
  final String userId;
  final String? role;
}

class PostPurchaseDocumentCommand {
  const PostPurchaseDocumentCommand({
    required this.documentId,
    required this.userId,
    this.role,
  });

  final int documentId;
  final String userId;
  final String? role;
}

class ReversePurchaseDocumentCommand {
  const ReversePurchaseDocumentCommand({
    required this.documentId,
    required this.reason,
    required this.userId,
    this.role,
  });

  final int documentId;
  final String reason;
  final String userId;
  final String? role;
}

class PurchaseCommandResult {
  const PurchaseCommandResult(this.document);

  final PurchaseDocument document;

  Map<String, Object?> toMap() => document.toMap();
}

class PurchaseCommandHandlers {
  PurchaseCommandHandlers({
    required PurchaseDocumentRepository repository,
    required DomainEventPublisher events,
    BranchScopeProvider? scope,
    PermissionService? permissions,
    TelemetryService? telemetry,
    PurchaseTaxService? taxService,
    StockLedgerService? stockLedger,
    AccountingPostingService? accounting,
    SyncOrchestrator? sync,
  }) : _repository = repository,
       _events = events,
       _scope = scope ?? BranchContextService.instance,
       _permissions = permissions ?? PermissionService.instance,
       _telemetry = telemetry ?? TelemetryService(),
       _taxService = taxService ?? PurchaseTaxService(),
       _stockLedger = stockLedger,
       _accounting = accounting,
       _sync = sync;

  final PurchaseDocumentRepository _repository;
  final DomainEventPublisher _events;
  final BranchScopeProvider _scope;
  final PermissionService _permissions;
  final TelemetryService _telemetry;
  final PurchaseTaxService _taxService;
  final StockLedgerService? _stockLedger;
  final AccountingPostingService? _accounting;
  final SyncOrchestrator? _sync;

  Future<PurchaseCommandResult> create(
    CreatePurchaseDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.create);
    final scope = await _scope.current();
    final issueDate = command.issueDate ?? DateTime.now();
    final taxedLines = await _taxService.applyDynamicTaxes(
      lines: command.lines,
      country: command.country,
      retentionRate: command.retentionRate,
    );
    final document = PurchaseDocument(
      companyId: scope.companyId,
      branchId: scope.branchId,
      warehouseId: scope.warehouseId,
      costCenterId: scope.costCenterId,
      type: command.type,
      state: PurchaseDocumentState.draft,
      supplierId: command.supplierId,
      supplierName: command.supplierName,
      issueDate: issueDate,
      dueDate: command.dueDate ?? issueDate.add(const Duration(days: 30)),
      country: command.country,
      budgetCode: command.budgetCode,
      budgetAvailable: command.budgetAvailable,
      correlationId: command.correlationId,
      approvals: _approvalPolicy(command),
      lines: taxedLines,
    )..validate();
    final id = await _repository.save(document);
    final saved = _withId(document, id);
    await _repository.appendAudit(
      documentId: id,
      action: 'purchases.create',
      userId: command.userId,
      payload: saved.toMap(),
    );
    await _enqueueSync(saved, SyncOperation.create);
    _telemetry.log(
      name: 'purchases.document.created',
      attributes: {
        'document_id': id,
        'total': saved.total.toMajorUnitsString(),
      },
    );
    return PurchaseCommandResult(saved);
  }

  Future<PurchaseCommandResult> approve(
    ApprovePurchaseDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.approve);
    final existing = await _required(command.documentId);
    final submitted = existing.state == PurchaseDocumentState.draft
        ? existing.submitForApproval()
        : existing;
    final approved = submitted.approve(command.userId);
    await _repository.update(approved);
    if (approved.state == PurchaseDocumentState.approved) {
      for (final event in approved.approvalEvents(userId: command.userId)) {
        await _events.publish(event);
      }
    }
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'purchases.approve',
      userId: command.userId,
      payload: approved.toMap(),
    );
    await _enqueueSync(approved, SyncOperation.update);
    _telemetry.log(
      name: 'purchases.document.approved',
      attributes: {
        'document_id': command.documentId,
        'state': approved.state.name,
      },
    );
    return PurchaseCommandResult(approved);
  }

  Future<PurchaseCommandResult> receive(
    ReceivePurchaseDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.receive);
    final existing = await _required(command.documentId);
    final received = existing.receive(command.quantities);
    await _repository.update(received);
    final stockLedger = _stockLedger;
    if (stockLedger != null) {
      for (final line in received.lines) {
        final receivedNow = command.quantities[line.productId] ?? 0;
        if (receivedNow > 0) {
          await stockLedger.receiveLot(
            StockLot(
              id: 'PO-${received.id}-${line.productId}-${DateTime.now().microsecondsSinceEpoch}',
              productId: line.productId,
              quantity: receivedNow,
              unitCost: line.unitCost,
              receivedAt: DateTime.now(),
            ),
          );
        }
      }
    }
    for (final event in received.receiptEvents(command.quantities)) {
      await _events.publish(event);
    }
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'purchases.receive',
      userId: command.userId,
      payload: received.toMap(),
    );
    await _enqueueSync(received, SyncOperation.update);
    _telemetry.log(
      name: 'purchases.goods.received',
      attributes: {
        'document_id': command.documentId,
        'received_ratio': received.receivedRatio,
      },
    );
    return PurchaseCommandResult(received);
  }

  Future<PurchaseCommandResult> post(
    PostPurchaseDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.post);
    final existing = await _required(command.documentId);
    final posted = existing.post();
    await _repository.update(posted);
    await _repository.upsertSupplierBalance(
      companyId: posted.companyId,
      branchId: posted.branchId,
      supplierId: posted.supplierId,
      supplierName: posted.supplierName,
      delta: posted.total,
    );
    final accounting = _accounting;
    if (accounting != null) {
      await accounting.post(_journalFor(posted));
    }
    for (final event in posted.postedEvents()) {
      await _events.publish(event);
    }
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'purchases.post',
      userId: command.userId,
      payload: posted.toMap(),
    );
    await _enqueueSync(posted, SyncOperation.update);
    _telemetry.log(
      name: 'purchases.invoice.posted',
      attributes: {
        'document_id': command.documentId,
        'total': posted.total.toMajorUnitsString(),
      },
    );
    return PurchaseCommandResult(posted);
  }

  Future<PurchaseCommandResult> reverse(
    ReversePurchaseDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.reverse);
    final existing = await _required(command.documentId);
    if (existing.state != PurchaseDocumentState.posted) {
      throw StateError('Solo compras posted pueden reversarse.');
    }
    final reversal = PurchaseDocument(
      companyId: existing.companyId,
      branchId: existing.branchId,
      warehouseId: existing.warehouseId,
      costCenterId: existing.costCenterId,
      type: PurchaseDocumentType.returnDocument,
      state: PurchaseDocumentState.posted,
      supplierId: existing.supplierId,
      supplierName: existing.supplierName,
      issueDate: DateTime.now(),
      dueDate: DateTime.now(),
      country: existing.country,
      budgetAvailable: existing.budgetAvailable,
      lines: existing.lines.map((line) => line.reversed()).toList(),
      reversedDocumentId: existing.id,
      correlationId: existing.correlationId,
    );
    final reversalId = await _repository.save(reversal);
    final reversed = existing.reverse(reversalDocumentId: reversalId);
    await _repository.update(reversed);
    await _repository.upsertSupplierBalance(
      companyId: reversed.companyId,
      branchId: reversed.branchId,
      supplierId: reversed.supplierId,
      supplierName: reversed.supplierName,
      delta: -reversed.total,
    );
    await _events.publish(
      PurchaseReversedEvent(
        purchaseId: reversed.id ?? command.documentId,
        reversalDocumentId: reversalId,
        companyId: reversed.companyId,
        branchId: reversed.branchId,
        reason: command.reason,
        correlationId: reversed.correlationId,
      ),
    );
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'purchases.reverse',
      userId: command.userId,
      payload: {'reason': command.reason, 'reversal_document_id': reversalId},
    );
    await _enqueueSync(reversed, SyncOperation.update);
    _telemetry.log(
      name: 'purchases.document.reversed',
      attributes: {
        'document_id': command.documentId,
        'reversal_document_id': reversalId,
      },
    );
    return PurchaseCommandResult(reversed);
  }

  List<ApprovalStep> _approvalPolicy(CreatePurchaseDocumentCommand command) {
    final amount = command.lines.fold<MoneyValue>(
      MoneyValue(
        minorUnits: 0,
        currency: command.lines.first.unitCost.currency,
      ),
      (sum, line) => sum + line.subtotal,
    );
    if (amount.minorUnits <= 100000000) {
      return const [
        ApprovalStep(level: 1, approverRole: 'operador', slaHours: 24),
      ];
    }
    return const [
      ApprovalStep(level: 1, approverRole: 'operador', slaHours: 12),
      ApprovalStep(level: 2, approverRole: 'contador', slaHours: 24),
      ApprovalStep(level: 3, approverRole: 'administrador', slaHours: 48),
    ];
  }

  JournalEntry _journalFor(PurchaseDocument document) {
    final dimension = AccountingDimensionValue(
      companyId: document.companyId,
      branchId: document.branchId,
      warehouseId: document.warehouseId,
      costCenterId: document.costCenterId,
      thirdParty: document.supplierName,
    );
    return JournalEntry(
      id: 'PUR-${document.id}',
      consecutive: 'PUR-${document.id}',
      date: document.postedAt ?? DateTime.now(),
      concept: 'Factura proveedor #${document.id}',
      reference: 'PUR-${document.id}',
      origin: 'purchases',
      correlationId: document.correlationId,
      lines: [
        JournalLine(
          accountCode: '1435',
          description: 'Inventario recibido',
          debit: document.subtotal,
          credit: MoneyValue(
            minorUnits: 0,
            currency: document.subtotal.currency,
          ),
          dimension: dimension,
        ),
        if (document.taxTotal.minorUnits > 0)
          JournalLine(
            accountCode: '1355',
            description: 'Impuesto descontable',
            debit: document.taxTotal,
            credit: MoneyValue(
              minorUnits: 0,
              currency: document.taxTotal.currency,
            ),
            dimension: dimension,
          ),
        if (document.retentionTotal.minorUnits > 0)
          JournalLine(
            accountCode: '2365',
            description: 'Retenciones practicadas',
            debit: MoneyValue(
              minorUnits: 0,
              currency: document.retentionTotal.currency,
            ),
            credit: document.retentionTotal,
            dimension: dimension,
          ),
        JournalLine(
          accountCode: '2205',
          description: 'Proveedor ${document.supplierName}',
          debit: MoneyValue(minorUnits: 0, currency: document.total.currency),
          credit: document.total,
          dimension: dimension,
        ),
      ],
    );
  }

  Future<PurchaseDocument> _required(int id) async {
    final document = await _repository.findById(id);
    if (document == null) {
      throw StateError('Documento de compra no encontrado.');
    }
    return document;
  }

  PurchaseDocument _withId(PurchaseDocument document, int id) {
    return PurchaseDocument(
      id: id,
      companyId: document.companyId,
      branchId: document.branchId,
      warehouseId: document.warehouseId,
      costCenterId: document.costCenterId,
      type: document.type,
      state: document.state,
      supplierId: document.supplierId,
      supplierName: document.supplierName,
      issueDate: document.issueDate,
      dueDate: document.dueDate,
      country: document.country,
      lines: document.lines,
      approvals: document.approvals,
      budgetCode: document.budgetCode,
      budgetAvailable: document.budgetAvailable,
      approvedBy: document.approvedBy,
      postedAt: document.postedAt,
      reversedDocumentId: document.reversedDocumentId,
      correlationId: document.correlationId,
    );
  }

  void _assertPermission(String role, AppAction action) {
    if (!_permissions.can(role: role, moduleId: 'purchases', action: action)) {
      throw StateError('Permiso insuficiente para purchases.${action.name}.');
    }
  }

  Future<void> _enqueueSync(
    PurchaseDocument document,
    SyncOperation operation,
  ) async {
    final sync = _sync;
    if (sync == null || document.id == null) return;
    await sync.enqueue(
      SyncEnvelope(
        id: 'purchases-${document.id}-${DateTime.now().microsecondsSinceEpoch}',
        companyId: document.companyId,
        branchId: document.branchId,
        aggregateType: 'purchase_document',
        aggregateId: document.id.toString(),
        operation: operation,
        payload: document.toMap(),
        occurredAt: DateTime.now(),
        idempotencyKey:
            'purchases:${document.id}:${operation.name}:${document.state.name}',
        vectorClock: SyncVectorClock({'branch-${document.branchId}': 1}),
      ),
    );
  }
}
