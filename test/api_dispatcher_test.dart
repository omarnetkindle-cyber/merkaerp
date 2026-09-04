import 'package:merka_erp/commerce/application/payment_policy.dart';
import 'package:merka_erp/accounting/application/accounting_report_service.dart';
import 'package:merka_erp/accounting/data/accounting_report_repository.dart';
import 'package:merka_erp/accounting/domain/trial_balance.dart';
import 'package:merka_erp/core/api/api_contract.dart';
import 'package:merka_erp/core/api/api_dispatcher.dart';
import 'package:merka_erp/core/events/domain_event.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/inventory/data/product_repository.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/application/create_purchase_use_case.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/sales/application/create_sale_use_case.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
import 'package:merka_erp/sales/domain/sale.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_money.dart';

final _cop = Currency(code: 'COP', name: 'Peso colombiano', symbol: r'$');

MoneyValue _money(int minorUnits) =>
    MoneyValue(minorUnits: minorUnits, currency: _cop);

class _Products implements ProductRepository {
  _Products(this.items);

  final List<Product> items;

  @override
  Future<void> delete(int id) async {}

  @override
  Future<List<Product>> findAll() async => items;

  @override
  Future<Product?> findById(int id) async => null;

  @override
  Future<int> save(Product product) async => 1;

  @override
  Future<void> updateStock(int id, double stock) async {}
}

class _Sales implements SaleRepository {
  CreateSaleRequest? capturedCreateRequest;

  @override
  Future<void> cancel(int saleId) async {}

  @override
  Future<int> createHeader(Map<String, dynamic> values) async => 1;

  @override
  Future<List<Sale>> findActive() async => findAll();

  @override
  Future<List<Sale>> findAll() async => [
    Sale(
      id: 1,
      companyId: 7,
      product: 'Factura POS #1',
      quantity: 1,
      subtotal: _money(10000),
      taxRate: 0,
      taxTotal: _money(0),
      total: _money(10000),
      date: '2026-05-20T08:00:00',
      paymentMethodId: 1,
      client: 'Cliente general',
      status: 'emitida',
    ),
  ];

  @override
  Future<List<SaleLine>> findDetails(int saleId) async => const [];

  @override
  Future<MoneyValue> totalSales() async => _money(10000);
}

class _Purchases implements PurchaseRepository {
  @override
  Future<void> cancel(int purchaseId) async {}

  @override
  Future<int> createHeader(Map<String, dynamic> values) async => 1;

  @override
  Future<List<Purchase>> findActive() async => findAll();

  @override
  Future<List<Purchase>> findAll() async => [
    Purchase(
      id: 2,
      companyId: 7,
      supplier: 'Proveedor demo',
      subtotal: _money(20000),
      taxRate: 0,
      taxTotal: _money(0),
      total: _money(20000),
      cashPayment: _money(20000),
      bankPayment: _money(0),
      credit: _money(0),
      date: '2026-05-20T09:00:00',
      paymentMethodId: 1,
      status: 'pagada',
    ),
  ];

  @override
  Future<List<PurchaseLine>> findDetails(int purchaseId) async => const [];

  @override
  Future<MoneyValue> totalPurchases() async => _money(20000);
}

class _AccountingReports implements AccountingReportRepository {
  @override
  Future<TrialBalance> trialBalance() async {
    return TrialBalance(
      accounts: [
        TrialBalanceAccount(
          accountId: 1,
          code: '1105',
          name: 'Caja',
          type: 'activo',
          nature: 'debito',
          debit: _money(10000),
          credit: _money(0),
          balance: _money(10000),
        ),
        TrialBalanceAccount(
          accountId: 2,
          code: '4135',
          name: 'Ingresos',
          type: 'ingreso',
          nature: 'credito',
          debit: _money(0),
          credit: _money(10000),
          balance: _money(10000),
        ),
      ],
    );
  }
}

void main() {
  group('ApiDispatcher', () {
    test('expone resumen operativo con inventario, ventas y compras', () async {
      final dispatcher = ApiDispatcher(
        products: _Products([
          Product(
            name: 'Pan',
            unit: 'und',
            stock: 3,
            cost: testMoney('1000'),
            price: testMoney('1500'),
            taxRate: 0,
          ),
          Product(
            name: 'Cafe',
            unit: 'lb',
            stock: 8,
            cost: testMoney('10000'),
            price: testMoney('14000'),
            taxRate: 19,
          ),
        ]),
        sales: _Sales(),
        purchases: _Purchases(),
      );

      final response = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/reports/summary',
          role: 'administrador',
        ),
      );

      final data = response.data as Map<String, Object?>;
      final inventory = data['inventory'] as Map<String, Object?>;
      expect(response.ok, isTrue);
      expect(inventory['products'], 2);
      expect(inventory['low_stock'], 1);
      expect((data['sales_total'] as Map)['minor_units'], 10000);
      expect((data['purchases_total'] as Map)['minor_units'], 20000);
    });

    test('pagina listados y expone metadatos de paginacion', () async {
      final dispatcher = ApiDispatcher(
        products: _Products([
          Product(
            name: 'Pan',
            unit: 'und',
            stock: 3,
            cost: testMoney('1000'),
            price: testMoney('1500'),
            taxRate: 0,
          ),
          Product(
            name: 'Cafe',
            unit: 'lb',
            stock: 8,
            cost: testMoney('10000'),
            price: testMoney('14000'),
            taxRate: 19,
          ),
        ]),
        sales: _Sales(),
        purchases: _Purchases(),
      );

      final response = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/products',
          role: 'administrador',
          query: {'limit': '1', 'offset': '1'},
        ),
      );

      final data = response.data as List<Object?>;
      final pagination = response.meta['pagination'] as Map<String, int>;
      expect(data, hasLength(1));
      expect((data.single as Map<String, Object?>)['nombre'], 'Cafe');
      expect(pagination['limit'], 1);
      expect(pagination['offset'], 1);
      expect(pagination['total'], 2);
    });

    test('bloquea endpoints cuando el rol no tiene permiso', () async {
      final dispatcher = ApiDispatcher(
        products: _Products(const []),
        sales: _Sales(),
        purchases: _Purchases(),
      );

      final response = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/purchases',
          role: 'consulta',
        ),
      );

      expect(response.statusCode, 403);
      expect(response.error, contains('Permiso insuficiente'));
    });

    test('expone balance de comprobacion contable', () async {
      final dispatcher = ApiDispatcher(
        products: _Products(const []),
        sales: _Sales(),
        purchases: _Purchases(),
        accountingReports: AccountingReportService(
          repository: _AccountingReports(),
        ),
      );

      final response = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/accounting/trial-balance',
          role: 'contador',
        ),
      );

      final data = response.data as Map<String, Object?>;
      final summary = data['summary'] as Map<String, Object?>;
      final accounts = data['accounts'] as List<Object?>;
      expect(response.ok, isTrue);
      expect(accounts, hasLength(2));
      expect(summary['balanced'], isTrue);
      expect(summary['total_debit'], 10000);
      expect(summary['total_credit'], 10000);
    });

    test('crea venta desde cuerpo API con nombres externos', () async {
      CreateSaleRequest? captured;
      final events = InMemoryDomainEventBus();
      final dispatcher = ApiDispatcher(
        products: _Products(const []),
        sales: _Sales(),
        purchases: _Purchases(),
        events: events,
        currencyResolver: () async => _cop,
        createSale: (request) async {
          captured = request;
          return CreateSaleResult(
            saleId: 31,
            subtotal: _money(10000),
            tax: _money(1900),
            total: _money(11900),
            costOfSale: _money(6000),
          );
        },
      );

      final response = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.post,
          path: '/api/v1/sales',
          role: 'administrador',
          userId: 'user-1',
          requestId: 'req-1',
          body: {
            'payment_method_id': 1,
            'payment_method': 'EFECTIVO',
            'client': 'Cliente API',
            'items': [
              {
                'product_id': 3,
                'product': 'Producto API',
                'quantity': 2,
                'unit_price': 5000,
                'unit_cost': 3000,
                'subtotal': 10000,
                'tax_rate': 19,
                'tax_total': 1900,
              },
            ],
          },
        ),
      );

      final data = response.data as Map<String, Object?>;
      expect(response.statusCode, 201);
      expect(data['sale_id'], 31);
      expect(captured?.clientName, 'Cliente API');
      expect(captured?.items.single.productId, 3);
      expect(captured?.items.single.taxTotal.minorUnits, 190000);
      expect(events.events.single.name, 'sales.created');
      expect(events.events.single.payload['user_id'], 'user-1');
      expect(events.events.single.payload['request_id'], 'req-1');
    });

    test(
      'crea compra desde cuerpo API y serializa asignacion de pago',
      () async {
        CreatePurchaseRequest? captured;
        final events = InMemoryDomainEventBus();
        final dispatcher = ApiDispatcher(
          products: _Products(const []),
          sales: _Sales(),
          purchases: _Purchases(),
          events: events,
          currencyResolver: () async => _cop,
          createPurchase: (request) async {
            captured = request;
            return CreatePurchaseResult(
              purchaseId: 41,
              subtotal: _money(30000),
              tax: _money(0),
              total: _money(30000),
              payment: PaymentAllocation(
                cash: _money(10000),
                bank: _money(0),
                credit: _money(20000),
              ),
            );
          },
        );

        final response = await dispatcher.dispatch(
          const ApiRequest(
            method: ApiMethod.post,
            path: '/api/v1/purchases',
            role: 'administrador',
            body: {
              'supplier_id': 9,
              'supplier': 'Proveedor API',
              'invoice_number': 'FV-API',
              'payment_method_id': 4,
              'payment_method': 'PAGO MIXTO',
              'cash': 10000,
              'credit': 20000,
              'items': [
                {
                  'product_id': 5,
                  'product': 'Insumo API',
                  'quantity': 3,
                  'unit_cost': 10000,
                  'subtotal': 30000,
                },
              ],
            },
          ),
        );

        final data = response.data as Map<String, Object?>;
        final payment = data['payment'] as Map<String, Object?>;
        expect(response.statusCode, 201);
        expect(data['purchase_id'], 41);
        expect((payment['credit'] as Map)['minor_units'], 20000);
        expect(captured?.supplierName, 'Proveedor API');
        expect(captured?.items.single.productId, 5);
        expect(events.events.single.name, 'purchases.created');
        expect(events.events.single.payload['purchase_id'], 41);
      },
    );

    test('expone endpoints empresariales de readiness y seguridad', () async {
      final dispatcher = ApiDispatcher(
        products: _Products(const []),
        sales: _Sales(),
        purchases: _Purchases(),
      );

      final readiness = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/system/readiness',
          role: 'administrador',
        ),
      );
      final security = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/security/permissions',
          role: 'administrador',
        ),
      );

      expect(readiness.ok, isTrue);
      expect((readiness.data as Map)['checks'], isA<List>());
      expect(security.ok, isTrue);
      expect((security.data as Map)['sensitive_actions'], isA<List>());
    });

    test('expone flujos empresariales y reposicion de inventario', () async {
      final dispatcher = ApiDispatcher(
        products: _Products([
          Product(
            id: 1,
            name: 'Pan',
            unit: 'und',
            stock: 2,
            cost: testMoney('1000'),
            price: testMoney('1500'),
            taxRate: 0,
          ),
        ]),
        sales: _Sales(),
        purchases: _Purchases(),
      );

      final purchasesFlow = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/procurement/workflow',
          role: 'administrador',
          query: {'requested': 'true', 'approved': 'true'},
        ),
      );
      final salesFlow = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/sales/workflow',
          role: 'administrador',
          query: {'quoted': 'true', 'credit_sale': 'true'},
        ),
      );
      final replenishment = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/inventory/replenishment',
          role: 'administrador',
        ),
      );

      expect(purchasesFlow.ok, isTrue);
      expect((purchasesFlow.data as List).first['status'], 'completed');
      expect(salesFlow.ok, isTrue);
      expect((salesFlow.data as List).first['stage'], 'quote');
      expect(replenishment.ok, isTrue);
      final data = replenishment.data as Map<String, Object?>;
      expect(data['replenishment'], isA<List>());
    });

    test('expone empresas y reporte fiscal sin endpoints pendientes', () async {
      final dispatcher = ApiDispatcher(
        products: _Products(const []),
        sales: _Sales(),
        purchases: _Purchases(),
        companies: () async => const [
          {'id': 7, 'name': 'MerkaERP Demo', 'active': 1},
        ],
        taxReport: ({required anio, required mes}) async => {
          'ventas': _money(10000),
          'compras': _money(4000),
          'iva_generado': _money(1900),
          'iva_descontable': _money(760),
          'iva_por_pagar': _money(1140),
          'nomina': _money(0),
        },
      );

      final companies = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/companies',
          role: 'administrador',
        ),
      );
      final tax = await dispatcher.dispatch(
        const ApiRequest(
          method: ApiMethod.get,
          path: '/api/v1/reports/tax',
          role: 'administrador',
          query: {'year': '2026', 'month': '5'},
        ),
      );

      expect(companies.ok, isTrue);
      expect(companies.statusCode, isNot(501));
      expect((companies.data as List).single['name'], 'MerkaERP Demo');
      expect(tax.ok, isTrue);
      expect(tax.statusCode, isNot(501));
      expect(((tax.data as Map)['tax_payable'] as Map)['minor_units'], 1140);
      expect(((tax.data as Map)['period'] as Map)['year'], 2026);
    });
  });
}
