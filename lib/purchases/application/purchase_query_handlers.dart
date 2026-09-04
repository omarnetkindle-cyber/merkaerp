import '../../core/branch/branch_context.dart';
import '../../core/currency/money_value.dart';
import '../data/purchase_document_repository.dart';
import '../domain/purchase_document.dart';

class PurchaseQueryHandlers {
  PurchaseQueryHandlers({
    required PurchaseDocumentRepository repository,
    BranchScopeProvider? scope,
  }) : _repository = repository,
       _scope = scope ?? BranchContextService.instance;

  final PurchaseDocumentRepository _repository;
  final BranchScopeProvider _scope;

  Future<List<Map<String, Object?>>> documents({
    PurchaseDocumentState? state,
    PurchaseDocumentType? type,
    int? supplierId,
    int limit = 100,
  }) async {
    final scope = await _scope.current();
    final rows = await _repository.search(
      PurchaseDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        warehouseId: scope.warehouseId,
        supplierId: supplierId,
        state: state,
        type: type,
        limit: limit,
      ),
    );
    return rows.map((document) => document.toMap()).toList();
  }

  Future<Map<String, Object?>> analytics() async {
    final scope = await _scope.current();
    final posted = await _repository.search(
      PurchaseDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        state: PurchaseDocumentState.posted,
        limit: 1000,
      ),
    );
    final pending = await _repository.search(
      PurchaseDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        state: PurchaseDocumentState.pendingApproval,
        limit: 1000,
      ),
    );
    final received = await _repository.search(
      PurchaseDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        state: PurchaseDocumentState.received,
        limit: 1000,
      ),
    );
    final spend = _sum(posted, (item) => item.total);
    final taxes = _sum(posted, (item) => item.taxTotal);
    final retentions = _sum(posted, (item) => item.retentionTotal);
    final payableForecast = _sum([
      ...posted,
      ...received,
    ], (item) => item.total);
    return {
      'company_id': scope.companyId,
      'branch_id': scope.branchId,
      'warehouse_id': scope.warehouseId,
      'posted_documents': posted.length,
      'pending_approvals': pending.length,
      'received_not_posted': received.length,
      'spend': spend?.toWireMap(),
      'taxes': taxes?.toWireMap(),
      'retentions': retentions?.toWireMap(),
      'payable_forecast': payableForecast?.toWireMap(),
      'average_purchase': spend == null
          ? null
          : (spend / posted.length).toWireMap(),
    };
  }

  MoneyValue? _sum(
    List<PurchaseDocument> documents,
    MoneyValue Function(PurchaseDocument document) selector,
  ) {
    if (documents.isEmpty) return null;
    final first = selector(documents.first);
    final zero = MoneyValue(minorUnits: 0, currency: first.currency);
    return documents.fold<MoneyValue>(
      zero,
      (sum, document) => sum + selector(document),
    );
  }
}
