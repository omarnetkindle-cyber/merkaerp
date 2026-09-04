import '../../core/branch/branch_context.dart';
import '../../core/currency/money_value.dart';
import '../data/sales_document_repository.dart';
import '../domain/sales_document.dart';

class SalesQueryHandlers {
  SalesQueryHandlers({
    required SalesDocumentRepository repository,
    BranchScopeProvider? scope,
  }) : _repository = repository,
       _scope = scope ?? BranchContextService.instance;

  final SalesDocumentRepository _repository;
  final BranchScopeProvider _scope;

  Future<List<Map<String, Object?>>> documents({
    SalesDocumentState? state,
    SalesDocumentType? type,
    int? customerId,
    int limit = 100,
  }) async {
    final scope = await _scope.current();
    final rows = await _repository.search(
      SalesDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        warehouseId: scope.warehouseId,
        customerId: customerId,
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
      SalesDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        state: SalesDocumentState.posted,
        limit: 1000,
      ),
    );
    final pending = await _repository.search(
      SalesDocumentQuery(
        companyId: scope.companyId,
        branchId: scope.branchId,
        state: SalesDocumentState.pending,
        limit: 1000,
      ),
    );
    MoneyValue? revenue;
    MoneyValue? taxes;
    for (final item in posted) {
      revenue = revenue == null ? item.total : revenue + item.total;
      taxes = taxes == null ? item.taxTotal : taxes + item.taxTotal;
    }
    final credit = posted
        .where((item) => item.paymentTerm.isCredit)
        .fold<MoneyValue?>(null, (sum, item) {
          return sum == null ? item.total : sum + item.total;
        });
    return {
      'company_id': scope.companyId,
      'branch_id': scope.branchId,
      'warehouse_id': scope.warehouseId,
      'posted_documents': posted.length,
      'pending_documents': pending.length,
      'revenue': revenue?.toWireMap(),
      'taxes': taxes?.toWireMap(),
      'credit_exposure': credit?.toWireMap(),
      'average_ticket': posted.isEmpty
          ? null
          : (revenue! / posted.length).toWireMap(),
    };
  }
}
