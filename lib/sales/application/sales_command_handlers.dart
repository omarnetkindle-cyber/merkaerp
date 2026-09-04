import '../../core/branch/branch_context.dart';
import '../../core/events/domain_event.dart';
import '../../core/security/action_permission.dart';
import '../../sync/application/sync_orchestrator.dart';
import '../../sync/domain/sync_models.dart';
import '../../sync/domain/sync_tenant_scope.dart';
import '../../telemetry/application/telemetry_service.dart';
import '../data/sales_document_repository.dart';
import '../domain/sales_document.dart';

class CreateSalesDocumentCommand {
  const CreateSalesDocumentCommand({
    required this.type,
    required this.customerName,
    required this.lines,
    required this.paymentMethod,
    required this.userId,
    this.role,
    this.customerId,
    this.issueDate,
    this.creditDays = 0,
    this.correlationId,
  });

  final SalesDocumentType type;
  final int? customerId;
  final String customerName;
  final List<SalesDocumentLine> lines;
  final String paymentMethod;
  final String userId;
  final String? role;
  final DateTime? issueDate;
  final int creditDays;
  final String? correlationId;
}

class PostSalesDocumentCommand {
  const PostSalesDocumentCommand({
    required this.documentId,
    required this.userId,
    this.role,
  });

  final int documentId;
  final String userId;
  final String? role;
}

class ReverseSalesDocumentCommand {
  const ReverseSalesDocumentCommand({
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

class SalesCommandResult {
  const SalesCommandResult({required this.document});

  final SalesDocument document;

  Map<String, Object?> toMap() => document.toMap();
}

class SalesCommandHandlers {
  SalesCommandHandlers({
    required SalesDocumentRepository repository,
    required DomainEventPublisher events,
    BranchScopeProvider? scope,
    PermissionService? permissions,
    TelemetryService? telemetry,
    SyncOrchestrator? sync,
  }) : _repository = repository,
       _events = events,
       _scope = scope ?? BranchContextService.instance,
       _permissions = permissions ?? PermissionService.instance,
       _telemetry = telemetry ?? TelemetryService(),
       _sync = sync;

  final SalesDocumentRepository _repository;
  final DomainEventPublisher _events;
  final BranchScopeProvider _scope;
  final PermissionService _permissions;
  final TelemetryService _telemetry;
  final SyncOrchestrator? _sync;

  Future<SalesCommandResult> create(CreateSalesDocumentCommand command) async {
    _assertPermission(command.role ?? command.userId, AppAction.create);
    final scope = await _scope.current();
    final issueDate = command.issueDate ?? DateTime.now();
    final document = SalesDocument(
      companyId: scope.companyId,
      branchId: scope.branchId,
      warehouseId: scope.warehouseId,
      costCenterId: scope.costCenterId,
      type: command.type,
      state: SalesDocumentState.draft,
      customerId: command.customerId,
      customerName: command.customerName,
      issueDate: issueDate,
      paymentTerm: SalesPaymentTerm(
        method: command.paymentMethod,
        dueDate: issueDate.add(Duration(days: command.creditDays)),
        creditDays: command.creditDays,
      ),
      lines: command.lines,
      correlationId: command.correlationId,
    )..validate();

    final id = await _repository.save(document);
    final saved = SalesDocument(
      id: id,
      companyId: document.companyId,
      branchId: document.branchId,
      warehouseId: document.warehouseId,
      costCenterId: document.costCenterId,
      type: document.type,
      state: document.state,
      customerId: document.customerId,
      customerName: document.customerName,
      issueDate: document.issueDate,
      paymentTerm: document.paymentTerm,
      lines: document.lines,
      correlationId: document.correlationId,
    );
    await _repository.appendAudit(
      documentId: id,
      action: 'sales.create',
      userId: command.userId,
      payload: saved.toMap(),
    );
    await _enqueueSync(saved, SyncOperation.create);
    _telemetry.log(
      name: 'sales.document.created',
      attributes: {'document_id': id, 'total': saved.total},
    );
    return SalesCommandResult(document: saved);
  }

  Future<SalesCommandResult> post(PostSalesDocumentCommand command) async {
    _assertPermission(command.role ?? command.userId, AppAction.post);
    final existing = await _required(command.documentId);
    final approved = existing.state == SalesDocumentState.approved
        ? existing
        : existing.markPending().approve(command.userId);
    final posted = approved.post();
    await _repository.updateState(posted);
    for (final event in posted.postedEvents(userId: command.userId)) {
      await _events.publish(event);
    }
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'sales.post',
      userId: command.userId,
      payload: posted.toMap(),
    );
    await _enqueueSync(posted, SyncOperation.update);
    _telemetry.log(
      name: 'sales.document.posted',
      attributes: {'document_id': command.documentId, 'total': posted.total},
    );
    return SalesCommandResult(document: posted);
  }

  Future<SalesCommandResult> reverse(
    ReverseSalesDocumentCommand command,
  ) async {
    _assertPermission(command.role ?? command.userId, AppAction.reverse);
    final existing = await _required(command.documentId);
    if (existing.state != SalesDocumentState.posted) {
      throw StateError('Solo documentos posted pueden reversarse.');
    }
    final reversal = SalesDocument(
      companyId: existing.companyId,
      branchId: existing.branchId,
      warehouseId: existing.warehouseId,
      costCenterId: existing.costCenterId,
      type: SalesDocumentType.creditNote,
      state: SalesDocumentState.posted,
      customerId: existing.customerId,
      customerName: existing.customerName,
      issueDate: DateTime.now(),
      paymentTerm: existing.paymentTerm,
      lines: existing.lines
          .map(
            (line) => SalesDocumentLine(
              productId: line.productId,
              productName: line.productName,
              quantity: line.quantity,
              unitPrice: -line.unitPrice,
              discount: -line.discount,
              taxRate: line.taxRate,
              taxTotal: -line.taxTotal,
              warehouseId: line.warehouseId,
            ),
          )
          .toList(),
      reversedDocumentId: existing.id,
      correlationId: existing.correlationId,
    );
    final reversalId = await _repository.save(reversal);
    final reversed = existing.reverse(reversalDocumentId: reversalId);
    await _repository.updateState(reversed);
    await _events.publish(
      IntegrationEvent(
        name: 'sales.reversed',
        payload: {
          'aggregate_type': 'sales_document',
          'aggregate_id': existing.id.toString(),
          'sale_id': existing.id,
          'reversal_document_id': reversalId,
          'company_id': existing.companyId,
          'branch_id': existing.branchId,
          'reason': command.reason,
          'total': existing.total.toWireMap(),
          'tax': existing.taxTotal.toWireMap(),
        },
      ),
    );
    await _repository.appendAudit(
      documentId: command.documentId,
      action: 'sales.reverse',
      userId: command.userId,
      payload: {'reason': command.reason, 'reversal_document_id': reversalId},
    );
    await _enqueueSync(reversed, SyncOperation.update);
    _telemetry.log(
      name: 'sales.document.reversed',
      attributes: {
        'document_id': command.documentId,
        'reversal_document_id': reversalId,
      },
    );
    return SalesCommandResult(document: reversed);
  }

  Future<SalesDocument> _required(int id) async {
    final document = await _repository.findById(id);
    if (document == null) throw StateError('Documento de venta no encontrado.');
    return document;
  }

  void _assertPermission(String role, AppAction action) {
    if (!_permissions.can(role: role, moduleId: 'sales', action: action)) {
      throw StateError('Permiso insuficiente para sales.${action.name}.');
    }
  }

  Future<void> _enqueueSync(
    SalesDocument document,
    SyncOperation operation,
  ) async {
    final sync = _sync;
    if (sync == null || document.id == null) return;
    final scope = SyncTenantScope.commercial(
      companyId: document.companyId,
      branchId: document.branchId,
    );
    await sync.enqueue(
      SyncEnvelope(
        id: 'sales-${document.id}-${DateTime.now().microsecondsSinceEpoch}',
        companyId: scope.companyId ?? document.companyId,
        branchId: scope.branchId ?? document.branchId,
        tenantType: scope.tenantType,
        entidadId: scope.entidadId,
        usuarioId: scope.usuarioId,
        aggregateType: 'sales_document',
        aggregateId: document.id.toString(),
        operation: operation,
        payload: document.toMap(),
        occurredAt: DateTime.now(),
        idempotencyKey:
            'sales:${document.id}:${operation.name}:${document.state.name}',
        vectorClock: SyncVectorClock({'branch-${document.branchId}': 1}),
      ),
    );
  }
}
