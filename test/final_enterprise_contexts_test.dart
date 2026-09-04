import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/branch/branch_context.dart';
import 'package:merka_erp/core/events/domain_event.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/enterprise/application/final_enterprise_command_handlers.dart';
import 'package:merka_erp/enterprise/application/final_enterprise_query_handlers.dart';
import 'package:merka_erp/enterprise/data/final_enterprise_repository.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';

import 'support/test_money.dart';

class _MemoryEnterpriseRepository implements FinalEnterpriseRepository {
  final tables = <String, List<Map<String, dynamic>>>{};
  final auditLog = <String>[];
  int _nextId = 1;

  @override
  Future<void> audit({
    required String action,
    required String entity,
    required String userId,
    int? entityId,
    Map<String, Object?> payload = const {},
  }) async {
    auditLog.add('$action:$entity:$userId');
  }

  @override
  Future<int> insertScoped(String table, Map<String, Object?> values) async {
    final row = {
      'id': values['id'] ?? _nextId++,
      'company_id': 7,
      'branch_id': 2,
      'warehouse_id': 3,
      'cost_center_id': 4,
      ...values,
    };
    tables.putIfAbsent(table, () => []).add(row);
    return row['id'] is int ? row['id'] as int : _nextId++;
  }

  @override
  Future<List<Map<String, dynamic>>> queryScoped(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    var rows = [...tables[table] ?? const <Map<String, dynamic>>[]];
    if (where != null && whereArgs != null) {
      rows = rows.where((row) => _matches(row, where, whereArgs)).toList();
    }
    return rows.take(limit ?? rows.length).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> rawScoped(
    String sql,
    List<Object?> arguments,
  ) async {
    return const [];
  }

  @override
  Future<BranchScope> scope() async {
    return const BranchScope(
      companyId: 7,
      companyName: 'Demo',
      branchId: 2,
      branchName: 'Principal',
      warehouseId: 3,
      costCenterId: 4,
    );
  }

  @override
  Future<Currency> currency() async => testCop;

  @override
  Future<int> updateScoped(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    var updated = 0;
    for (final row in tables[table] ?? <Map<String, dynamic>>[]) {
      if (_matches(row, where, whereArgs)) {
        row.addAll(values);
        updated++;
      }
    }
    return updated;
  }

  bool _matches(
    Map<String, dynamic> row,
    String where,
    List<Object?> whereArgs,
  ) {
    if (where.contains('customer_id = ?')) {
      return row['customer_id'] == whereArgs.first;
    }
    if (where.contains('supplier_id = ?')) {
      return row['supplier_id'] == whereArgs.first;
    }
    if (where.contains('statement_id = ?') && where.contains('status = ?')) {
      return row['statement_id'] == whereArgs[0] &&
          row['status'] == whereArgs[1];
    }
    if (where.contains('bank_account_id = ?') && where.contains('ABS(amount')) {
      return row['bank_account_id'] == whereArgs[0] &&
          (((row['amount'] as num?)?.toDouble() ?? 0) -
                      ((whereArgs[1] as num?)?.toDouble() ?? 0))
                  .abs() <
              0.01 &&
          row['reference'] == whereArgs[2] &&
          row['reconciled'] == 0;
    }
    if (where.contains('id = ?')) return row['id'] == whereArgs.first;
    if (where.contains('country = ?')) {
      return row['country'] == whereArgs[0] &&
          row['document_type'] == whereArgs[1] &&
          row['active'] == 1;
    }
    if (where.contains('status = ?')) return row['status'] == whereArgs.first;
    if (where.contains('definition_id')) return row['id'] == whereArgs.first;
    return true;
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
    'final enterprise contexts run end-to-end through API dispatcher',
    () async {
      final repository = _MemoryEnterpriseRepository();
      final events = InMemoryDomainEventBus();
      final commands = FinalEnterpriseCommandHandlers(
        repository: repository,
        events: events,
      );
      final queries = FinalEnterpriseQueryHandlers(repository: repository);
      final dispatcher = ApiDispatcher(
        products: _Products(),
        sales: _Sales(),
        purchases: _Purchases(),
        finalEnterpriseCommands: commands,
        finalEnterpriseQueries: queries,
        events: events,
      );

      final taxRule = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/tax/rules',
          role: 'administrador',
          body: {
            'code': 'VAT_DYNAMIC',
            'country': 'Colombia',
            'document_type': 'invoice',
            'rate': 19,
            'retention_rate': 2.5,
          },
        ),
      );
      final tax = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/tax/calculate',
          role: 'administrador',
          requestId: 'tax-corr',
          body: {
            'document_type': 'invoice',
            'document_id': 'INV-1',
            'country': 'Colombia',
            'taxable_base': 1000,
          },
        ),
      );
      final collect = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/ar/collect',
          role: 'administrador',
          body: {'customer_id': 10, 'customer': 'Cliente', 'amount': 300},
        ),
      );
      final schedule = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/ap/schedule-payment',
          role: 'administrador',
          body: {
            'supplier_id': 20,
            'supplier': 'Proveedor',
            'amount': 500,
            'due_date': '2026-06-30',
          },
        ),
      );
      final bankAccountA = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/treasury/bank-accounts',
          role: 'administrador',
          body: {'name': 'Banco A', 'balance': 1000},
        ),
      );
      final bankAccountB = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/treasury/bank-accounts',
          role: 'administrador',
          body: {'name': 'Banco B', 'balance': 0},
        ),
      );
      final accountA = (bankAccountA.data as Map)['bank_account_id'] as int;
      final accountB = (bankAccountB.data as Map)['bank_account_id'] as int;
      final transfer = await dispatcher.dispatch(
        ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/treasury/transfers',
          role: 'administrador',
          body: {
            'from_account_id': accountA,
            'to_account_id': accountB,
            'amount': 250,
            'approved': true,
          },
        ),
      );
      final transferId = (transfer.data as Map)['id'].toString();
      final statement = await dispatcher.dispatch(
        ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/bank/statements/import',
          role: 'administrador',
          body: {
            'bank_account_id': accountA,
            'lines': [
              {'reference': transferId, 'amount': 250},
            ],
          },
        ),
      );
      final reconcile = await dispatcher.dispatch(
        ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/bank/reconcile',
          role: 'administrador',
          body: {'statement_id': (statement.data as Map)['statement_id']},
        ),
      );
      final asset = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/assets/register',
          role: 'administrador',
          body: {
            'id': 'AS-1',
            'name': 'Equipo',
            'cost': 1200,
            'useful_life_months': 12,
          },
        ),
      );
      final depreciation = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/assets/depreciate',
          role: 'administrador',
          body: {'asset_id': 'AS-1', 'months': 2},
        ),
      );
      final crm = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/crm/opportunities',
          role: 'administrador',
          userId: 'seller',
          body: {
            'customer_id': 10,
            'customer': 'Cliente',
            'value': 7000,
            'stage': 'proposal',
          },
        ),
      );
      final definition = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/reports/definitions',
          role: 'administrador',
          body: {
            'id': 'RPT-TREASURY',
            'name': 'Tesoreria',
            'dataset': 'treasury',
            'formats': ['pdf', 'excel', 'json'],
          },
        ),
      );
      final report = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/reports/generate',
          role: 'administrador',
          body: {'definition_id': 'RPT-TREASURY'},
        ),
      );

      expect(taxRule.ok, isTrue);
      expect((tax.data as Map)['tax'], 19000);
      expect(collect.statusCode, 201);
      expect(schedule.statusCode, 201);
      expect(transfer.statusCode, 201);
      expect((reconcile.data as Map)['matched'], 1);
      expect((asset.data as Map)['book_value'], 120000);
      expect((depreciation.data as Map)['accumulated_depreciation'], 20000);
      expect(crm.statusCode, 201);
      expect(definition.statusCode, 201);
      expect((report.data as Map)['exports'], hasLength(3));
      expect(
        events.events.map((event) => event.name),
        contains('InvoicePaidEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('TreasuryTransferCreatedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('BankReconciledEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('AssetDepreciatedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('TaxCalculatedEvent'),
      );
      expect(
        events.events.map((event) => event.name),
        contains('ReportGeneratedEvent'),
      );
    },
  );
}
