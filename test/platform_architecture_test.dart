import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/branch/branch_context.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/licensing/application/license_policy_service.dart';
import 'package:merka_erp/licensing/domain/license_models.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/rules/application/rule_engine.dart';
import 'package:merka_erp/rules/domain/business_rule.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';
import 'package:merka_erp/sync/application/conflict_resolver.dart';
import 'package:merka_erp/sync/application/sync_orchestrator.dart';
import 'package:merka_erp/sync/domain/sync_models.dart';
import 'package:merka_erp/telemetry/application/telemetry_service.dart';
import 'package:merka_erp/workflows/application/workflow_engine.dart';
import 'package:merka_erp/workflows/domain/workflow_models.dart';

import 'support/test_money.dart';

class _SyncRepo implements SyncEventRepository {
  final outbox = <SyncEnvelope>[];
  final inbox = <SyncEnvelope>[];
  final conflicts = <SyncConflict>[];

  @override
  Future<void> enqueueOutbox(SyncEnvelope event) async => outbox.add(event);

  @override
  Future<SyncEnvelope?> findLocalAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    final matches = outbox.where(
      (event) =>
          event.aggregateType == aggregateType &&
          event.aggregateId == aggregateId,
    );
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<bool> hasInboxEvent(String idempotencyKey) async {
    return inbox.any((event) => event.idempotencyKey == idempotencyKey);
  }

  @override
  Future<void> markOutboxPushed(String eventId) async {
    final index = outbox.indexWhere((event) => event.id == eventId);
    if (index >= 0) {
      outbox[index] = outbox[index].copyWith(status: SyncEventStatus.pushed);
    }
  }

  @override
  Future<List<SyncEnvelope>> pendingOutbox({int limit = 100}) async {
    return outbox
        .where((event) => event.status == SyncEventStatus.pending)
        .take(limit)
        .toList();
  }

  @override
  Future<void> recordConflict(SyncConflict conflict) async {
    conflicts.add(conflict);
  }

  @override
  Future<SyncStatusSnapshot> status() async {
    return SyncStatusSnapshot(
      pendingOutbox: outbox
          .where((event) => event.status == SyncEventStatus.pending)
          .length,
      pendingInbox: 0,
      conflicts: conflicts.length,
      lastPushAt: null,
      lastPullAt: null,
      online: false,
    );
  }

  @override
  Future<void> storeInbox(SyncEnvelope event) async => inbox.add(event);
}

class _BranchProvider implements BranchScopeProvider {
  const _BranchProvider();

  @override
  Future<BranchScope> current({bool force = false}) async {
    return const BranchScope(
      companyId: 1,
      companyName: 'Demo',
      branchId: 2,
      branchName: 'Norte',
      warehouseId: 3,
      costCenterId: 4,
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
  group('Plataforma distribuida', () {
    test('sync push marca eventos como enviados', () async {
      final repo = _SyncRepo();
      final orchestrator = SyncOrchestrator(repository: repo);
      await orchestrator.enqueue(_event(id: '1'));

      final result = await orchestrator.push();

      expect(result.sent, 1);
      expect(repo.outbox.single.status, SyncEventStatus.pushed);
    });

    test('sync pull registra conflicto concurrente manual', () async {
      final repo = _SyncRepo();
      final orchestrator = SyncOrchestrator(
        repository: repo,
        resolver: const SyncConflictResolver(
          defaultStrategy: ConflictResolutionStrategy.manual,
        ),
      );
      await repo.enqueueOutbox(
        _event(id: 'local', clock: const SyncVectorClock({'branch-a': 1})),
      );

      final result = await orchestrator.pull([
        _event(
          id: 'remote',
          idempotencyKey: 'remote-key',
          clock: const SyncVectorClock({'branch-b': 1}),
        ),
      ]);

      expect(result.conflicts, 1);
      expect(repo.conflicts.single.remote.id, 'remote');
    });

    test('rule engine dispara acciones configurables', () {
      const rule = BusinessRule(
        id: 'purchase-high-value',
        name: 'Compra alta',
        conditions: [
          RuleCondition(
            field: 'total',
            operator: RuleOperator.greaterOrEqual,
            value: 5000000,
          ),
        ],
        actions: [
          RuleAction(type: 'require_approval', parameters: {'role': 'gerente'}),
        ],
      );

      final actions = const RuleEngine().matchingActions(
        const [rule],
        {'total': 6000000},
      );

      expect(actions.single.type, 'require_approval');
    });

    test('workflow aprueba compra de alto valor por pasos', () {
      const engine = WorkflowEngine();
      final instance = engine.start(
        definition: WorkflowTemplateCatalog.purchaseApproval,
        documentId: 'CP-1',
        context: {'total': 6000000},
      );
      final managerApproved = engine.decide(
        definition: WorkflowTemplateCatalog.purchaseApproval,
        instance: instance,
        decision: WorkflowDecision.approve,
        actor: 'gerente',
      );
      final financeApproved = engine.decide(
        definition: WorkflowTemplateCatalog.purchaseApproval,
        instance: managerApproved,
        decision: WorkflowDecision.approve,
        actor: 'contador',
      );

      expect(instance.status, WorkflowInstanceStatus.running);
      expect(financeApproved.status, WorkflowInstanceStatus.approved);
    });

    test('licencia bloquea exceso de sucursales', () {
      final evaluation = const LicensePolicyService().evaluate(
        TenantLicense(
          tenantId: 'tenant',
          plan: const SaaSPlan(
            id: 'basic',
            name: 'Basic',
            maxCompanies: 1,
            maxBranches: 1,
            maxDevices: 2,
            enabledModules: {'sales'},
          ),
          status: LicenseStatus.active,
          expiresAt: DateTime.now().add(const Duration(days: 10)),
          activeDevices: 1,
          activeBranches: 2,
        ),
      );

      expect(evaluation.allowed, isFalse);
      expect(evaluation.messages.single, contains('sucursales'));
    });

    test('telemetry expone health summary', () {
      final telemetry = TelemetryService();
      telemetry.log(name: 'sync.retry');

      final summary = telemetry.healthSummary();

      expect(summary['events_buffered'], 1);
      expect(summary['checks'], isA<List>());
    });

    test(
      'api expone scope, sync, licencia, telemetry, workflows y reglas',
      () async {
        final dispatcher = ApiDispatcher(
          products: _Products(),
          sales: _Sales(),
          purchases: _Purchases(),
          branchScope: const _BranchProvider(),
          syncStatus: () async => SyncStatusSnapshot.offlineFirstReady(),
        );

        final scope = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.get,
            path: '/api/v1/platform/scope',
            role: 'administrador',
          ),
        );
        final sync = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.get,
            path: '/api/v1/sync/status',
            role: 'administrador',
          ),
        );
        final license = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.get,
            path: '/api/v1/licensing/status',
            role: 'administrador',
          ),
        );
        final telemetry = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.get,
            path: '/api/v1/telemetry/health',
            role: 'administrador',
          ),
        );
        final workflows = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.get,
            path: '/api/v1/workflows/templates',
            role: 'administrador',
          ),
        );
        final rules = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.post,
            path: '/api/v1/rules/evaluate',
            role: 'administrador',
            body: {
              'context': {'total': 10},
              'rules': [
                {
                  'id': 'r1',
                  'name': 'Demo',
                  'conditions': [
                    {'field': 'total', 'operator': 'greaterThan', 'value': 5},
                  ],
                  'actions': [
                    {
                      'type': 'notify',
                      'parameters': {'channel': 'internal'},
                    },
                  ],
                },
              ],
            },
          ),
        );

        expect((scope.data as Map)['branch_id'], 2);
        expect((sync.data as Map)['healthy'], isTrue);
        expect((license.data as Map)['allowed'], isTrue);
        expect((telemetry.data as Map)['checks'], isA<List>());
        expect(workflows.data, isA<List>());
        expect(
          ((rules.data as Map)['matched_actions'] as List).single['type'],
          'notify',
        );
      },
    );
  });
}

SyncEnvelope _event({
  required String id,
  String idempotencyKey = 'key',
  SyncVectorClock clock = const SyncVectorClock({'branch-a': 1}),
}) {
  return SyncEnvelope(
    id: id,
    companyId: 1,
    branchId: 1,
    aggregateType: 'sale',
    aggregateId: '1',
    operation: SyncOperation.upsert,
    payload: const {'total': 100},
    occurredAt: DateTime(2026, 5, 26),
    idempotencyKey: idempotencyKey,
    vectorClock: clock,
  );
}
