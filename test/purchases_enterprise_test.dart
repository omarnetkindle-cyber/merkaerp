import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/branch/branch_context.dart';
import 'package:merka_erp/core/events/domain_event.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/application/purchase_command_handlers.dart';
import 'package:merka_erp/purchases/application/purchase_query_handlers.dart';
import 'package:merka_erp/purchases/application/purchase_tax_service.dart';
import 'package:merka_erp/purchases/data/purchase_document_repository.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/purchases/domain/purchase_document.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';

import 'support/test_money.dart';

class _Scope implements BranchScopeProvider {
  const _Scope();

  @override
  Future<BranchScope> current({bool force = false}) async {
    return const BranchScope(
      companyId: 7,
      companyName: 'Demo',
      branchId: 2,
      branchName: 'Principal',
      warehouseId: 3,
      costCenterId: 4,
    );
  }
}

class _TaxService extends PurchaseTaxService {
  @override
  Future<List<PurchaseDocumentLine>> applyDynamicTaxes({
    required List<PurchaseDocumentLine> lines,
    required String country,
    double retentionRate = 0,
  }) async {
    return lines
        .map(
          (line) => PurchaseDocumentLine(
            productId: line.productId,
            productName: line.productName,
            quantity: line.quantity,
            unitCost: line.unitCost,
            receivedQuantity: line.receivedQuantity,
            taxCode: 'IVA_19',
            taxRate: country == 'Colombia' ? 19 : 0,
            retentionRate: retentionRate,
            warehouseId: line.warehouseId,
          ),
        )
        .toList();
  }
}

class _Documents implements PurchaseDocumentRepository {
  final documents = <int, PurchaseDocument>{};
  final audit = <String>[];
  final balances = <int, MoneyValue>{};
  int nextId = 1;

  @override
  Future<void> appendAudit({
    required int documentId,
    required String action,
    required String userId,
    required Map<String, Object?> payload,
  }) async {
    audit.add('$action:$documentId:$userId');
  }

  @override
  Future<PurchaseDocument?> findById(int id) async => documents[id];

  @override
  Future<int> save(PurchaseDocument document) async {
    final id = nextId++;
    documents[id] = _withId(document, id);
    return id;
  }

  @override
  Future<List<PurchaseDocument>> search(PurchaseDocumentQuery query) async {
    return documents.values
        .where((item) => item.companyId == query.companyId)
        .where(
          (item) => query.branchId == null || item.branchId == query.branchId,
        )
        .where(
          (item) =>
              query.warehouseId == null ||
              item.warehouseId == query.warehouseId,
        )
        .where((item) => query.state == null || item.state == query.state)
        .where((item) => query.type == null || item.type == query.type)
        .where(
          (item) =>
              query.supplierId == null || item.supplierId == query.supplierId,
        )
        .take(query.limit)
        .toList();
  }

  @override
  Future<void> update(PurchaseDocument document) async {
    documents[document.id!] = document;
  }

  @override
  Future<void> upsertSupplierBalance({
    required int companyId,
    required int branchId,
    required int supplierId,
    required String supplierName,
    required MoneyValue delta,
  }) async {
    balances[supplierId] = (balances[supplierId] ?? zeroTestMoney) + delta;
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
}

class _Products implements ProductRepository {
  @override
  Future<void> delete(int id) async {}

  @override
  Future<List<Product>> findAll() async => const [];

  @override
  Future<Product?> findById(int id) async => null;

  @override
  Future<int> save(Product product) async => 1;

  @override
  Future<void> updateStock(int id, double stock) async {}
}

class _Sales implements SaleRepository {
  @override
  Future<void> cancel(int saleId) async {}

  @override
  Future<int> createHeader(Map<String, dynamic> values) async => 1;

  @override
  Future<List<Sale>> findActive() async => const [];

  @override
  Future<List<Sale>> findAll() async => const [];

  @override
  Future<List<SaleLine>> findDetails(int saleId) async => const [];

  @override
  Future<MoneyValue> totalSales() async => zeroTestMoney;
}

class _Purchases implements PurchaseRepository {
  @override
  Future<void> cancel(int purchaseId) async {}

  @override
  Future<int> createHeader(Map<String, dynamic> values) async => 1;

  @override
  Future<List<Purchase>> findActive() async => const [];

  @override
  Future<List<Purchase>> findAll() async => const [];

  @override
  Future<List<PurchaseLine>> findDetails(int purchaseId) async => const [];

  @override
  Future<MoneyValue> totalPurchases() async => zeroTestMoney;
}

void main() {
  test(
    'PurchaseDocument enforces approvals, partial receipt, posting and reversal',
    () {
      final document = PurchaseDocument(
        companyId: 1,
        branchId: 1,
        warehouseId: 1,
        costCenterId: 1,
        type: PurchaseDocumentType.purchaseOrder,
        state: PurchaseDocumentState.draft,
        supplierId: 3,
        supplierName: 'Proveedor',
        issueDate: DateTime(2026, 5, 27),
        dueDate: DateTime(2026, 6, 26),
        country: 'Colombia',
        budgetCode: 'OPS',
        budgetAvailable: testMoney('5000'),
        approvals: const [
          ApprovalStep(level: 1, approverRole: 'operador', slaHours: 12),
          ApprovalStep(level: 2, approverRole: 'contador', slaHours: 24),
        ],
        lines: [
          PurchaseDocumentLine(
            productId: 8,
            productName: 'Insumo',
            quantity: 10,
            unitCost: testMoney('100'),
            taxCode: 'IVA_19',
            taxRate: 19,
            retentionRate: 2.5,
          ),
        ],
      );

      final pending = document.submitForApproval();
      final firstApproval = pending.approve('op');
      final approved = firstApproval.approve('cont');
      final partial = approved.receive({8: 4});
      final received = partial.receive({8: 6});
      final posted = received.post();

      expect(firstApproval.state, PurchaseDocumentState.pendingApproval);
      expect(approved.state, PurchaseDocumentState.approved);
      expect(partial.state, PurchaseDocumentState.partiallyReceived);
      expect(received.state, PurchaseDocumentState.received);
      expect(posted.state, PurchaseDocumentState.posted);
      expect(posted.total, testMoney('1165'));
      expect(() => posted.cancel(), throwsStateError);
    },
  );

  test(
    'PurchaseCommandHandlers integrate events, audit, supplier balance and analytics',
    () async {
      final repository = _Documents();
      final events = InMemoryDomainEventBus();
      final commands = PurchaseCommandHandlers(
        repository: repository,
        events: events,
        scope: const _Scope(),
        taxService: _TaxService(),
      );
      final queries = PurchaseQueryHandlers(
        repository: repository,
        scope: const _Scope(),
      );

      final created = await commands.create(
        CreatePurchaseDocumentCommand(
          type: PurchaseDocumentType.purchaseOrder,
          supplierId: 11,
          supplierName: 'Proveedor enterprise',
          userId: 'u1',
          role: 'administrador',
          retentionRate: 2,
          budgetCode: 'OPS',
          budgetAvailable: testMoney('2000000'),
          lines: [
            PurchaseDocumentLine(
              productId: 5,
              productName: 'Materia prima',
              quantity: 2,
              unitCost: testMoney('600000'),
            ),
          ],
        ),
      );
      await commands.approve(
        ApprovePurchaseDocumentCommand(
          documentId: created.document.id!,
          userId: 'u1',
          role: 'administrador',
        ),
      );
      final approved = await commands.approve(
        ApprovePurchaseDocumentCommand(
          documentId: created.document.id!,
          userId: 'u2',
          role: 'administrador',
        ),
      );
      final fullyApproved = await commands.approve(
        ApprovePurchaseDocumentCommand(
          documentId: created.document.id!,
          userId: 'u3',
          role: 'administrador',
        ),
      );
      final received = await commands.receive(
        ReceivePurchaseDocumentCommand(
          documentId: created.document.id!,
          quantities: const {5: 2},
          userId: 'u2',
          role: 'administrador',
        ),
      );
      final posted = await commands.post(
        PostPurchaseDocumentCommand(
          documentId: created.document.id!,
          userId: 'u3',
          role: 'administrador',
        ),
      );
      final analytics = await queries.analytics();

      expect(approved.document.state, PurchaseDocumentState.pendingApproval);
      expect(fullyApproved.document.state, PurchaseDocumentState.approved);
      expect(received.document.state, PurchaseDocumentState.received);
      expect(posted.document.state, PurchaseDocumentState.posted);
      expect(repository.balances[11], posted.document.total);
      expect(repository.audit, contains('purchases.post:1:u3'));
      expect(
        events.events.map((event) => event.name),
        contains('PurchaseApprovedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('GoodsReceivedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('SupplierInvoicePostedEvent'),
      );
      expect(
        (analytics['spend'] as Map<String, Object?>)['minor_units'],
        posted.document.total.minorUnits,
      );
    },
  );

  test('ApiDispatcher exposes enterprise purchase endpoints', () async {
    final repository = _Documents();
    final events = InMemoryDomainEventBus();
    final commands = PurchaseCommandHandlers(
      repository: repository,
      events: events,
      scope: const _Scope(),
      taxService: _TaxService(),
    );
    final queries = PurchaseQueryHandlers(
      repository: repository,
      scope: const _Scope(),
    );
    final dispatcher = ApiDispatcher(
      products: _Products(),
      sales: _Sales(),
      purchases: _Purchases(),
      purchaseCommands: commands,
      purchaseQueries: queries,
      currencyResolver: () async => testCop,
    );

    final create = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents',
        role: 'administrador',
        userId: 'api-user',
        body: {
          'type': 'purchaseOrder',
          'supplier_id': 44,
          'supplier': 'Proveedor API',
          'budget_available': 2000000,
          'items': [
            {
              'product_id': 9,
              'product': 'Insumo API',
              'quantity': 1,
              'unit_cost': 1200000,
            },
          ],
        },
      ),
    );
    await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents/approve',
        role: 'administrador',
        userId: 'api-user',
        body: {'document_id': 1},
      ),
    );
    final approve = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents/approve',
        role: 'administrador',
        userId: 'api-user-2',
        body: {'document_id': 1},
      ),
    );
    final approveFinal = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents/approve',
        role: 'administrador',
        userId: 'api-user-3',
        body: {'document_id': 1},
      ),
    );
    final receive = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents/receive',
        role: 'administrador',
        userId: 'api-user',
        body: {
          'document_id': 1,
          'quantities': {'9': 1},
        },
      ),
    );
    final post = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/purchases/documents/post',
        role: 'administrador',
        userId: 'api-user',
        body: {'document_id': 1},
      ),
    );

    expect(create.statusCode, 201);
    expect(approve.ok, isTrue);
    expect(approveFinal.ok, isTrue);
    expect(receive.ok, isTrue);
    expect(post.ok, isTrue);
    expect((post.data as Map<String, Object?>)['state'], 'posted');
    expect(
      events.events.map((event) => event.name),
      contains('SupplierBalanceUpdatedEvent'),
    );
  });
}
