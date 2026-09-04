import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/accounting/application/accounting_posting_service.dart';
import 'package:merka_erp/accounting/application/ledger_engine.dart';
import 'package:merka_erp/accounting/data/journal_entry_repository.dart';
import 'package:merka_erp/accounting/domain/journal_entry.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/branch/branch_context.dart';
import 'package:merka_erp/core/events/domain_event.dart';
import 'package:merka_erp/core/events/event_dispatcher.dart' as eda;
import 'package:merka_erp/core/events/event_store.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/cqrs/application/dashboard_projection.dart';
import 'package:merka_erp/cqrs/domain/read_models.dart';
import 'package:merka_erp/inventory/application/stock_ledger_service.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/data/stock_ledger_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/inventory/domain/stock_ledger.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';

import 'support/test_money.dart';

void main() {
  group('Consolidacion arquitectonica', () {
    test(
      'event bus persistente aplica scope, idempotencia y correlacion',
      () async {
        final store = _MemoryEventStore();
        final bus = eda.PersistentEventBus(
          eventStore: store,
          scopeProvider: const _ScopeProvider(),
        );

        await bus.publish(
          IntegrationEvent(
            name: 'sales.created',
            payload: const {
              'sale_id': 7,
              'total': 250000,
              'request_id': 'req-1',
              'correlation_id': 'corr-1',
            },
          ),
        );

        final saved = store.events.single;
        expect(saved.aggregateType, 'sales.created');
        expect(saved.aggregateId, '7');
        expect(saved.companyId, 10);
        expect(saved.branchId, 20);
        expect(saved.idempotencyKey, 'req-1');
        expect(saved.correlationId, 'corr-1');
      },
    );

    test('ledger contabiliza, reversa y conserva partida doble', () async {
      final engine = const LedgerEngine();
      final draft = _journalEntry();

      final posted = engine.post(draft);
      final reversal = engine.reverse(
        posted,
        reversalId: 'JE-2',
        reversalConsecutive: 'RC-0001',
        date: DateTime(2026, 5, 27),
      );
      final balance = engine.trialBalance([posted, reversal]);

      expect(posted.status, JournalEntryStatus.posted);
      expect(reversal.reversedEntryId, posted.id);
      expect(balance.balanced, isTrue);
      expect(balance.totalDebit, balance.totalCredit);
    });

    test('posting service persiste asientos y publica eventos', () async {
      final repo = _JournalRepo();
      final events = InMemoryDomainEventBus();
      final service = AccountingPostingService(
        repository: repo,
        scopeProvider: const _ScopeProvider(),
        events: events,
      );

      final posted = await service.post(_journalEntry());

      expect(repo.saved.single.id, posted.id);
      expect(events.events.single.name, 'accounting.journal_posted');
      expect(events.events.single.payload['company_id'], 10);
    });

    test('stock ledger consume FIFO y emite evento transaccional', () async {
      final repo = _StockRepo([
        StockLot(
          id: 'L1',
          productId: 1,
          quantity: 5,
          unitCost: testMoney('10'),
          receivedAt: DateTime(2026, 1, 1),
        ),
        StockLot(
          id: 'L2',
          productId: 1,
          quantity: 5,
          unitCost: testMoney('20'),
          receivedAt: DateTime(2026, 1, 2),
        ),
      ]);
      final events = InMemoryDomainEventBus();
      final service = StockLedgerService(
        repository: repo,
        scopeProvider: const _ScopeProvider(),
        events: events,
      );

      final result = await service.consume(
        productId: 1,
        quantity: 6,
        method: InventoryCostMethod.fifo,
        documentType: 'sale',
        documentId: 'FV-1',
      );

      expect(result.totalCost, testMoney('70'));
      expect(result.remainingOnHand, 4);
      expect(repo.lots.single.id, 'L2');
      expect(repo.lots.single.quantity, 4);
      expect(events.events.single.name, 'inventory.consumed');
    });

    test('api expone event store, replay y read model ejecutivo', () async {
      final store = _MemoryEventStore();
      await store.append(
        EventEnvelope.fromEvent(
          IntegrationEvent(
            name: 'sales.created',
            payload: const {'sale_id': 1, 'total': 500},
          ),
          scope: _scope,
          idempotencyKey: 'evt-1',
        ),
      );
      final dispatcher = ApiDispatcher(
        products: _Products(),
        sales: _Sales(),
        purchases: _Purchases(),
        branchScope: const _ScopeProvider(),
        eventStore: store,
        eventDispatcher: _ReplayDispatcher(),
        dashboardProjection: _DashboardProjection(),
      );

      final events = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/events',
          role: 'administrador',
        ),
      );
      final replay = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/events/replay',
          role: 'administrador',
          body: {'limit': 25},
        ),
      );
      final dashboard = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/cqrs/executive-dashboard',
          role: 'administrador',
        ),
      );

      expect((events.data as List).single['idempotency_key'], 'evt-1');
      expect((replay.data as Map)['dispatched'], 25);
      expect(
        (dashboard.data as Map)['summary']['sales_total']['minor_units'],
        50000,
      );
    });
  });
}

const _scope = BranchScope(
  companyId: 10,
  companyName: 'Merka',
  branchId: 20,
  branchName: 'Principal',
  warehouseId: 30,
  costCenterId: 40,
);

class _ScopeProvider implements BranchScopeProvider {
  const _ScopeProvider();

  @override
  Future<BranchScope> current({bool force = false}) async => _scope;
}

class _MemoryEventStore implements EventStore {
  final events = <EventEnvelope>[];

  @override
  Future<EventEnvelope> append(EventEnvelope event) async {
    final existing = events.where(
      (item) => item.idempotencyKey == event.idempotencyKey,
    );
    if (existing.isNotEmpty) return existing.first;
    final saved = event.withSequence(events.length + 1);
    events.add(saved);
    return saved;
  }

  @override
  Future<List<EventEnvelope>> load({
    int afterSequence = 0,
    int limit = 200,
  }) async {
    return events
        .where((event) => (event.sequence ?? 0) > afterSequence)
        .take(limit)
        .toList();
  }

  @override
  Future<List<EventEnvelope>> loadAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    return events
        .where(
          (event) =>
              event.aggregateType == aggregateType &&
              event.aggregateId == aggregateId,
        )
        .toList();
  }
}

class _ReplayDispatcher extends eda.EventDispatcher {
  _ReplayDispatcher() : super(projections: const []);

  @override
  Future<eda.EventDispatchResult> dispatchPending({int limit = 100}) async {
    return eda.EventDispatchResult(
      dispatched: limit,
      failed: 0,
      deadLettered: 0,
    );
  }
}

class _DashboardProjection extends DashboardReadModelProjection {
  @override
  Future<void> apply(EventEnvelope event) async {}

  @override
  Future<ExecutiveDashboardReadModel> read({
    required int companyId,
    required int branchId,
  }) async {
    return ExecutiveDashboardReadModel(
      companyId: companyId,
      branchId: branchId,
      metrics: [
        KpiMetric(
          key: 'sales_total',
          value: testMoney('500.00'),
          updatedAt: DateTime(2026, 5, 27),
        ),
      ],
    );
  }
}

class _JournalRepo implements JournalEntryRepository {
  final saved = <JournalEntry>[];

  @override
  Future<List<JournalEntry>> findPosted({
    required int companyId,
    required int branchId,
    DateTime? from,
    DateTime? to,
  }) async {
    return saved;
  }

  @override
  Future<void> savePosted(
    JournalEntry entry, {
    required BranchScope scope,
  }) async {
    saved.add(entry);
  }
}

class _StockRepo implements StockLedgerRepository {
  _StockRepo(this.lots);

  List<StockLot> lots;
  final reservations = <InventoryReservation>[];

  @override
  Future<StockLedger> load({
    required int productId,
    required BranchScope scope,
  }) async {
    return StockLedger(
      productId: productId,
      lots: lots,
      reservations: reservations,
    );
  }

  @override
  Future<void> releaseReservation(
    String reservationId, {
    required BranchScope scope,
  }) async {
    reservations.removeWhere((item) => item.id == reservationId);
  }

  @override
  Future<void> replaceLots(
    List<StockLot> lots, {
    required int productId,
    required BranchScope scope,
  }) async {
    this.lots = lots;
  }

  @override
  Future<void> saveLot(StockLot lot, {required BranchScope scope}) async {
    lots.add(lot);
  }

  @override
  Future<void> saveReservation(
    InventoryReservation reservation, {
    required BranchScope scope,
  }) async {
    reservations.add(reservation);
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

JournalEntry _journalEntry() {
  return JournalEntry(
    id: 'JE-1',
    consecutive: 'CC-0001',
    date: DateTime(2026, 5, 27),
    concept: 'Venta empresarial',
    reference: 'FV-1',
    origin: 'sales',
    correlationId: 'corr-1',
    lines: [
      JournalLine(
        accountCode: '110505',
        description: 'Caja',
        debit: testMoney('1190.00'),
        credit: zeroTestMoney,
      ),
      JournalLine(
        accountCode: '413505',
        description: 'Ingresos',
        debit: zeroTestMoney,
        credit: testMoney('1000.00'),
      ),
      JournalLine(
        accountCode: '240805',
        description: 'IVA generado',
        debit: zeroTestMoney,
        credit: testMoney('190.00'),
      ),
    ],
  );
}
