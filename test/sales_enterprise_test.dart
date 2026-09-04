import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/branch/branch_context.dart';
import 'package:merka_erp/core/events/domain_event.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/sales/application/sales_command_handlers.dart';
import 'package:merka_erp/sales/application/sales_query_handlers.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/data/sales_document_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';
import 'package:merka_erp/sales/domain/sales_document.dart';

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

class _Documents implements SalesDocumentRepository {
  final documents = <int, SalesDocument>{};
  final audit = <String>[];
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
  Future<SalesDocument?> findById(int id) async => documents[id];

  @override
  Future<int> save(SalesDocument document) async {
    final id = nextId++;
    documents[id] = _withId(document, id);
    return id;
  }

  @override
  Future<List<SalesDocument>> search(SalesDocumentQuery query) async {
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
        .take(query.limit)
        .toList();
  }

  @override
  Future<void> updateState(SalesDocument document) async {
    documents[document.id!] = document;
  }

  SalesDocument _withId(SalesDocument document, int id) {
    return SalesDocument(
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
  test('SalesDocument enforce enterprise state machine and immutability', () {
    final document = SalesDocument(
      companyId: 1,
      branchId: 1,
      warehouseId: 1,
      costCenterId: 1,
      type: SalesDocumentType.invoice,
      state: SalesDocumentState.draft,
      customerName: 'Cliente',
      customerId: 1,
      issueDate: DateTime(2026, 5, 27),
      paymentTerm: SalesPaymentTerm(
        method: 'CREDITO',
        dueDate: DateTime(2026, 6, 26),
        creditDays: 30,
      ),
      lines: [
        SalesDocumentLine(
          productId: 1,
          productName: 'SKU',
          quantity: 2,
          unitPrice: testMoney('100.00'),
          discount: testMoney('10.00'),
          taxRate: 19,
          taxTotal: testMoney('36.10'),
        ),
      ],
    );

    final posted = document.markPending().approve('admin').post();

    expect(posted.state, SalesDocumentState.posted);
    expect(posted.total.minorUnits, 22610);
    expect(() => posted.cancel(), throwsStateError);
    expect(posted.immutable, isTrue);
  });

  test(
    'SalesCommandHandlers create, post, audit, events and analytics query',
    () async {
      final repository = _Documents();
      final events = InMemoryDomainEventBus();
      final commands = SalesCommandHandlers(
        repository: repository,
        events: events,
        scope: const _Scope(),
      );
      final queries = SalesQueryHandlers(
        repository: repository,
        scope: const _Scope(),
      );

      final created = await commands.create(
        CreateSalesDocumentCommand(
          type: SalesDocumentType.invoice,
          customerId: 9,
          customerName: 'Cliente empresarial',
          paymentMethod: 'CREDITO',
          creditDays: 15,
          userId: 'u1',
          role: 'administrador',
          lines: [
            SalesDocumentLine(
              productId: 4,
              productName: 'Producto',
              quantity: 3,
              unitPrice: testMoney('1000.00'),
              discount: zeroTestMoney,
              taxRate: 19,
              taxTotal: testMoney('570.00'),
            ),
          ],
        ),
      );
      final posted = await commands.post(
        PostSalesDocumentCommand(
          documentId: created.document.id!,
          userId: 'u1',
          role: 'administrador',
        ),
      );
      final analytics = await queries.analytics();

      expect(posted.document.state, SalesDocumentState.posted);
      expect(
        events.events.map((event) => event.name),
        contains('SalePostedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('TaxCalculatedEvent'),
      );
      expect(repository.audit, contains('sales.post:1:u1'));
      expect(
        (analytics['revenue'] as Map<String, Object?>)['minor_units'],
        357000,
      );
      expect(
        (analytics['credit_exposure'] as Map<String, Object?>)['minor_units'],
        357000,
      );
    },
  );

  test('ApiDispatcher exposes enterprise sales document endpoints', () async {
    final repository = _Documents();
    final events = InMemoryDomainEventBus();
    final commands = SalesCommandHandlers(
      repository: repository,
      events: events,
      scope: const _Scope(),
    );
    final queries = SalesQueryHandlers(
      repository: repository,
      scope: const _Scope(),
    );
    final dispatcher = ApiDispatcher(
      products: _Products(),
      sales: _Sales(),
      purchases: _Purchases(),
      salesCommands: commands,
      salesQueries: queries,
      currencyResolver: () async => testCop,
    );

    final create = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/sales/documents',
        role: 'administrador',
        userId: 'u-api',
        requestId: 'req-api',
        body: {
          'type': 'invoice',
          'customer_id': 15,
          'customer': 'Cliente API',
          'payment_method': 'EFECTIVO',
          'items': [
            {
              'product_id': 2,
              'product': 'Producto API',
              'quantity': 2,
              'unit_price': 5000,
              'tax_rate': 19,
            },
          ],
        },
      ),
    );
    final post = await dispatcher.dispatch(
      const ApiRequest(
        method: ApiMethod.post,
        path: '/api/v1/sales/documents/post',
        role: 'administrador',
        userId: 'u-api',
        body: {'document_id': 1},
      ),
    );

    expect(create.statusCode, 201);
    expect(post.ok, isTrue);
    expect((post.data as Map<String, Object?>)['state'], 'posted');
    expect(
      events.events.map((event) => event.name),
      contains('SalePostedEvent'),
    );
  });
}
