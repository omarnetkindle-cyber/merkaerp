import '../../accounting/application/accounting_report_service.dart';
import '../../core/branch/branch_context.dart';
import '../../core/events/event_dispatcher.dart';
import '../../core/events/event_store.dart';
import '../../core/database/data_health_service.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../core/release/release_readiness.dart';
import '../../cqrs/application/dashboard_projection.dart';
import '../../db_helper.dart';
import '../../enterprise/application/final_enterprise_command_handlers.dart';
import '../../enterprise/application/final_enterprise_projections.dart';
import '../../enterprise/application/final_enterprise_query_handlers.dart';
import '../../enterprise/data/final_enterprise_repository.dart';
import '../../inventory/data/product_repository.dart';
import '../../inventory/application/inventory_control_service.dart';
import '../../inventory/domain/inventory_summary.dart';
import '../../purchases/application/create_purchase_use_case.dart';
import '../../purchases/application/purchase_command_handlers.dart';
import '../../purchases/application/purchase_projections.dart';
import '../../purchases/application/purchase_query_handlers.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../purchases/data/purchase_document_repository.dart';
import '../../purchases/domain/purchase_document.dart';
import '../../purchases/domain/procurement_workflow.dart';
import '../../rules/application/rule_engine.dart';
import '../../rules/domain/business_rule.dart';
import '../../sales/application/create_sale_use_case.dart';
import '../../sales/application/sales_command_handlers.dart';
import '../../sales/application/sales_projections.dart';
import '../../sales/application/sales_query_handlers.dart';
import '../../sales/data/sale_repository.dart';
import '../../sales/data/sales_document_repository.dart';
import '../../sales/domain/sales_workflow.dart';
import '../../sales/domain/sales_document.dart';
import '../../sync/domain/sync_models.dart';
import '../../telemetry/application/telemetry_service.dart';
import '../../workflows/application/workflow_engine.dart';
import '../../licensing/application/license_policy_service.dart';
import '../events/domain_event.dart';
import '../security/action_permission.dart';
import '../security/enterprise_security_policy.dart';
import 'api_contract.dart';
import 'pagination.dart';

typedef CreateSaleHandler =
    Future<CreateSaleResult> Function(CreateSaleRequest request);
typedef CreatePurchaseHandler =
    Future<CreatePurchaseResult> Function(CreatePurchaseRequest request);
typedef CompanyListHandler = Future<List<Map<String, Object?>>> Function();
typedef TaxReportHandler =
    Future<Map<String, MoneyValue>> Function({
      required int anio,
      required int mes,
    });
typedef ApiCurrencyResolver = Future<Currency> Function();

class ApiRequest {
  const ApiRequest({
    required this.method,
    required this.path,
    required this.role,
    this.body = const {},
    this.query = const {},
    this.userId = 'local',
    this.requestId,
  });

  final ApiMethod method;
  final String path;
  final String role;
  final Map<String, dynamic> body;
  final Map<String, String> query;
  final String userId;
  final String? requestId;
}

class ApiResponse {
  const ApiResponse._({
    required this.statusCode,
    this.data,
    this.error,
    this.meta = const {},
  });

  final int statusCode;
  final Object? data;
  final String? error;
  final Map<String, Object?> meta;

  bool get ok => statusCode >= 200 && statusCode < 300;

  factory ApiResponse.ok(
    Object? data, {
    int statusCode = 200,
    Map<String, Object?> meta = const {},
  }) {
    return ApiResponse._(statusCode: statusCode, data: data, meta: meta);
  }

  factory ApiResponse.error(int statusCode, String message) {
    return ApiResponse._(statusCode: statusCode, error: message);
  }
}

class ApiDispatcher {
  ApiDispatcher({
    required ProductRepository products,
    required SaleRepository sales,
    required PurchaseRepository purchases,
    PermissionService? permissions,
    AccountingReportService? accountingReports,
    CreateSaleHandler? createSale,
    CreatePurchaseHandler? createPurchase,
    ReleaseReadinessService releaseReadiness = const ReleaseReadinessService(),
    DataHealthService? dataHealth,
    InventoryControlService inventoryControl = const InventoryControlService(),
    ProcurementWorkflowService procurementWorkflow =
        const ProcurementWorkflowService(),
    SalesWorkflowService salesWorkflow = const SalesWorkflowService(),
    EnterpriseSecurityPolicyService? securityPolicy,
    BranchScopeProvider? branchScope,
    Future<SyncStatusSnapshot> Function()? syncStatus,
    LicensePolicyService licensing = const LicensePolicyService(),
    TelemetryService? telemetry,
    RuleEngine ruleEngine = const RuleEngine(),
    EventStore? eventStore,
    EventDispatcher? eventDispatcher,
    DashboardReadModelProjection? dashboardProjection,
    SalesCommandHandlers? salesCommands,
    SalesQueryHandlers? salesQueries,
    PurchaseCommandHandlers? purchaseCommands,
    PurchaseQueryHandlers? purchaseQueries,
    FinalEnterpriseCommandHandlers? finalEnterpriseCommands,
    FinalEnterpriseQueryHandlers? finalEnterpriseQueries,
    CompanyListHandler? companies,
    TaxReportHandler? taxReport,
    ApiCurrencyResolver? currencyResolver,
    DomainEventPublisher events = const NoopDomainEventPublisher(),
  }) : _products = products,
       _sales = sales,
       _purchases = purchases,
       _accountingReports = accountingReports ?? AccountingReportService(),
       _permissions = permissions ?? PermissionService.instance,
       _createSale = createSale ?? CreateSaleUseCase().execute,
       _createPurchase = createPurchase ?? CreatePurchaseUseCase().execute,
       _releaseReadiness = releaseReadiness,
       _dataHealth = dataHealth ?? DataHealthService(),
       _inventoryControl = inventoryControl,
       _procurementWorkflow = procurementWorkflow,
       _salesWorkflow = salesWorkflow,
       _securityPolicy = securityPolicy ?? EnterpriseSecurityPolicyService(),
       _branchScope = branchScope ?? BranchContextService.instance,
       _syncStatus =
           syncStatus ?? (() async => SyncStatusSnapshot.offlineFirstReady()),
       _licensing = licensing,
       _telemetry = telemetry ?? TelemetryService(),
       _ruleEngine = ruleEngine,
       _eventStore = eventStore ?? SqliteEventStore(),
       _dashboardProjection =
           dashboardProjection ?? DashboardReadModelProjection(),
       _salesCommands =
           salesCommands ??
           SalesCommandHandlers(
             repository: SqliteSalesDocumentRepository(),
             events: events,
             telemetry: telemetry,
           ),
       _salesQueries =
           salesQueries ??
           SalesQueryHandlers(repository: SqliteSalesDocumentRepository()),
       _purchaseCommands =
           purchaseCommands ??
           PurchaseCommandHandlers(
             repository: SqlitePurchaseDocumentRepository(),
             events: events,
             telemetry: telemetry,
           ),
       _purchaseQueries =
           purchaseQueries ??
           PurchaseQueryHandlers(
             repository: SqlitePurchaseDocumentRepository(),
           ),
       _finalEnterpriseCommands =
           finalEnterpriseCommands ??
           FinalEnterpriseCommandHandlers(
             repository: SqliteFinalEnterpriseRepository(),
             events: events,
             telemetry: telemetry,
           ),
       _finalEnterpriseQueries =
           finalEnterpriseQueries ??
           FinalEnterpriseQueryHandlers(
             repository: SqliteFinalEnterpriseRepository(),
           ),
       _companies = companies ?? _defaultCompanies,
       _taxReport = taxReport ?? DatabaseHelper.instance.obtenerReporteFiscal,
       _currencyResolver = currencyResolver ?? _defaultCurrencyResolver,
       _eventDispatcher =
           eventDispatcher ??
           EventDispatcher(
             projections: [
               dashboardProjection ?? DashboardReadModelProjection(),
               SalesAnalyticsProjection(),
               PurchaseAnalyticsProjection(),
               FinalEnterpriseProjection(),
             ],
           ),
       _events = events;

  final ProductRepository _products;
  final SaleRepository _sales;
  final PurchaseRepository _purchases;
  final AccountingReportService _accountingReports;
  final PermissionService _permissions;
  final CreateSaleHandler _createSale;
  final CreatePurchaseHandler _createPurchase;
  final ReleaseReadinessService _releaseReadiness;
  final DataHealthService _dataHealth;
  final InventoryControlService _inventoryControl;
  final ProcurementWorkflowService _procurementWorkflow;
  final SalesWorkflowService _salesWorkflow;
  final EnterpriseSecurityPolicyService _securityPolicy;
  final BranchScopeProvider _branchScope;
  final Future<SyncStatusSnapshot> Function() _syncStatus;
  final LicensePolicyService _licensing;
  final TelemetryService _telemetry;
  final RuleEngine _ruleEngine;
  final EventStore _eventStore;
  final EventDispatcher _eventDispatcher;
  final DashboardReadModelProjection _dashboardProjection;
  final SalesCommandHandlers _salesCommands;
  final SalesQueryHandlers _salesQueries;
  final PurchaseCommandHandlers _purchaseCommands;
  final PurchaseQueryHandlers _purchaseQueries;
  final FinalEnterpriseCommandHandlers _finalEnterpriseCommands;
  final FinalEnterpriseQueryHandlers _finalEnterpriseQueries;
  final CompanyListHandler _companies;
  final TaxReportHandler _taxReport;
  final ApiCurrencyResolver _currencyResolver;
  final DomainEventPublisher _events;

  static Future<List<Map<String, Object?>>> _defaultCompanies() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'companies',
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return rows
        .map((row) => row.map((key, value) => MapEntry(key, value)))
        .toList();
  }

  static Future<Currency> _defaultCurrencyResolver() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  Future<ApiResponse> dispatch(ApiRequest request) async {
    final endpoint = ApiContract.match(request.method, request.path);
    if (endpoint == null) {
      return ApiResponse.error(404, 'Endpoint no encontrado.');
    }

    if (!_permissions.can(
      role: request.role,
      moduleId: endpoint.module,
      action: endpoint.action,
    )) {
      return ApiResponse.error(403, 'Permiso insuficiente.');
    }

    try {
      switch ((request.method, request.path)) {
        case (ApiMethod.get, '/api/v1/companies'):
          return _paged(await _companies(), request.query);
        case (ApiMethod.get, '/api/v1/products'):
          return _paged(
            (await _products.findAll()).map((item) => item.toMap()).toList(),
            request.query,
          );
        case (ApiMethod.get, '/api/v1/sales'):
          return _paged(
            (await _sales.findAll()).map((item) => item.toMap()).toList(),
            request.query,
          );
        case (ApiMethod.post, '/api/v1/sales'):
          final result = await _createSale(
            await _saleRequestFromBody(request.body),
          );
          await _events.publish(
            IntegrationEvent(
              name: 'sales.created',
              payload: {
                'sale_id': result.saleId,
                'total': result.total,
                'user_id': request.userId,
                'request_id': request.requestId,
              },
            ),
          );
          return ApiResponse.ok(_saleResultToMap(result), statusCode: 201);
        case (ApiMethod.get, '/api/v1/sales/documents'):
          return _paged(
            await _salesQueries.documents(
              state: _salesState(request.query['state']),
              type: _salesType(request.query['type']),
              customerId: _nullableInt(request.query['customer_id']),
              limit: _int(request.query['limit'], fallback: 100),
            ),
            request.query,
          );
        case (ApiMethod.post, '/api/v1/sales/documents'):
          final result = await _salesCommands.create(
            await _createSalesDocumentCommand(request),
          );
          return ApiResponse.ok(result.toMap(), statusCode: 201);
        case (ApiMethod.post, '/api/v1/sales/documents/post'):
          final result = await _salesCommands.post(
            PostSalesDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.post, '/api/v1/sales/documents/reverse'):
          final result = await _salesCommands.reverse(
            ReverseSalesDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              reason: request.body['reason']?.toString() ?? 'Reverso operativo',
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.get, '/api/v1/sales/analytics'):
          return ApiResponse.ok(await _salesQueries.analytics());
        case (ApiMethod.get, '/api/v1/purchases'):
          return _paged(
            (await _purchases.findAll()).map((item) => item.toMap()).toList(),
            request.query,
          );
        case (ApiMethod.post, '/api/v1/purchases'):
          final result = await _createPurchase(
            await _purchaseRequestFromBody(request.body),
          );
          await _events.publish(
            IntegrationEvent(
              name: 'purchases.created',
              payload: {
                'purchase_id': result.purchaseId,
                'total': result.total,
                'user_id': request.userId,
                'request_id': request.requestId,
              },
            ),
          );
          return ApiResponse.ok(_purchaseResultToMap(result), statusCode: 201);
        case (ApiMethod.get, '/api/v1/purchases/documents'):
          return _paged(
            await _purchaseQueries.documents(
              state: _purchaseState(request.query['state']),
              type: _purchaseType(request.query['type']),
              supplierId: _nullableInt(request.query['supplier_id']),
              limit: _int(request.query['limit'], fallback: 100),
            ),
            request.query,
          );
        case (ApiMethod.post, '/api/v1/purchases/documents'):
          final result = await _purchaseCommands.create(
            await _createPurchaseDocumentCommand(request),
          );
          return ApiResponse.ok(result.toMap(), statusCode: 201);
        case (ApiMethod.post, '/api/v1/purchases/documents/approve'):
          final result = await _purchaseCommands.approve(
            ApprovePurchaseDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.post, '/api/v1/purchases/documents/receive'):
          final result = await _purchaseCommands.receive(
            ReceivePurchaseDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              quantities: _quantityMap(request.body['quantities']),
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.post, '/api/v1/purchases/documents/post'):
          final result = await _purchaseCommands.post(
            PostPurchaseDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.post, '/api/v1/purchases/documents/reverse'):
          final result = await _purchaseCommands.reverse(
            ReversePurchaseDocumentCommand(
              documentId: _int(request.body['document_id'], fallback: 0),
              reason: request.body['reason']?.toString() ?? 'Reverso operativo',
              userId: request.userId,
              role: request.role,
            ),
          );
          return ApiResponse.ok(result.toMap());
        case (ApiMethod.get, '/api/v1/purchases/analytics'):
          return ApiResponse.ok(await _purchaseQueries.analytics());
        case (ApiMethod.get, '/api/v1/reports/summary'):
          return ApiResponse.ok(await _summary());
        case (ApiMethod.get, '/api/v1/reports/tax'):
          final now = DateTime.now();
          final year = _int(request.query['year'], fallback: now.year);
          final month = _int(request.query['month'], fallback: now.month);
          final totals = await _taxReport(anio: year, mes: month);
          final wireTotals = totals.map(
            (key, value) => MapEntry(key, value.toWireMap()),
          );
          return ApiResponse.ok({
            'period': {'year': year, 'month': month},
            'totals': wireTotals,
            'tax_payable': totals['iva_por_pagar']?.toWireMap(),
          });
        case (ApiMethod.get, '/api/v1/accounting/trial-balance'):
          return ApiResponse.ok(
            (await _accountingReports.trialBalance()).toMap(),
          );
        case (ApiMethod.get, '/api/v1/ar/ledger'):
          return _paged(
            await _finalEnterpriseQueries.arLedger(
              customerId: _nullableInt(request.query['customer_id']),
            ),
            request.query,
          );
        case (ApiMethod.get, '/api/v1/ar/aging'):
          return ApiResponse.ok(await _finalEnterpriseQueries.arAging());
        case (ApiMethod.post, '/api/v1/ar/collect'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.collectReceivable(
              request.body,
              role: request.role,
              userId: request.userId,
              correlationId: request.requestId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/ar/payment-promises'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.promisePayment(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/ar/credit-limit'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.overrideCreditLimit(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
          );
        case (ApiMethod.get, '/api/v1/ap/ledger'):
          return _paged(
            await _finalEnterpriseQueries.apLedger(
              supplierId: _nullableInt(request.query['supplier_id']),
            ),
            request.query,
          );
        case (ApiMethod.get, '/api/v1/ap/aging'):
          return ApiResponse.ok(await _finalEnterpriseQueries.apAging());
        case (ApiMethod.post, '/api/v1/ap/schedule-payment'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.schedulePayable(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/ap/pay'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.payPayable(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.get, '/api/v1/treasury/dashboard'):
          return ApiResponse.ok(
            await _finalEnterpriseQueries.treasuryDashboard(),
          );
        case (ApiMethod.post, '/api/v1/treasury/bank-accounts'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.createBankAccount(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/treasury/transfers'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.createTreasuryTransfer(
              request.body,
              role: request.role,
              userId: request.userId,
              correlationId: request.requestId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/bank/statements/import'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.importBankStatement(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/bank/reconcile'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.reconcileBank(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
          );
        case (ApiMethod.get, '/api/v1/bank/unmatched'):
          return _paged(
            await _finalEnterpriseQueries.unmatchedBankOperations(),
            request.query,
          );
        case (ApiMethod.post, '/api/v1/tax/rules'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.configureTaxRule(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/tax/calculate'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.calculateTax(
              request.body,
              role: request.role,
              userId: request.userId,
              correlationId: request.requestId,
            ),
          );
        case (ApiMethod.get, '/api/v1/assets/register'):
          return _paged(await _finalEnterpriseQueries.assets(), request.query);
        case (ApiMethod.post, '/api/v1/assets/register'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.registerAsset(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/assets/depreciate'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.depreciateAsset(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
          );
        case (ApiMethod.get, '/api/v1/crm/pipeline'):
          return ApiResponse.ok(await _finalEnterpriseQueries.crmPipeline());
        case (ApiMethod.post, '/api/v1/crm/opportunities'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.createCrmOpportunity(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/reports/definitions'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.defineReport(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
            statusCode: 201,
          );
        case (ApiMethod.post, '/api/v1/reports/generate'):
          return ApiResponse.ok(
            await _finalEnterpriseCommands.generateReport(
              request.body,
              role: request.role,
              userId: request.userId,
            ),
          );
        case (ApiMethod.get, '/api/v1/reports/materialized'):
          return _paged(
            await _finalEnterpriseQueries.materializedReports(),
            request.query,
          );
        case (ApiMethod.get, '/api/v1/system/readiness'):
          return ApiResponse.ok(_releaseReadiness.localRuntimeReport().toMap());
        case (ApiMethod.get, '/api/v1/system/data-health'):
          return ApiResponse.ok((await _dataHealth.audit()).toMap());
        case (ApiMethod.get, '/api/v1/security/permissions'):
          return ApiResponse.ok(_securityPolicy.toMap());
        case (ApiMethod.get, '/api/v1/procurement/workflow'):
          return ApiResponse.ok(
            _procurementWorkflow
                .build(_procurementSnapshotFromQuery(request.query))
                .map((step) => step.toMap())
                .toList(),
          );
        case (ApiMethod.get, '/api/v1/sales/workflow'):
          return ApiResponse.ok(
            _salesWorkflow
                .build(_salesSnapshotFromQuery(request.query))
                .map((step) => step.toMap())
                .toList(),
          );
        case (ApiMethod.get, '/api/v1/inventory/replenishment'):
          return ApiResponse.ok(
            _inventoryControl.analyze(await _products.findAll()).toMap(),
          );
        case (ApiMethod.get, '/api/v1/platform/scope'):
          return ApiResponse.ok((await _branchScope.current()).toMap());
        case (ApiMethod.get, '/api/v1/sync/status'):
          return ApiResponse.ok((await _syncStatus()).toMap());
        case (ApiMethod.get, '/api/v1/licensing/status'):
          return ApiResponse.ok(_licensing.localTrial().toMap());
        case (ApiMethod.get, '/api/v1/telemetry/health'):
          return ApiResponse.ok(_telemetry.healthSummary());
        case (ApiMethod.get, '/api/v1/workflows/templates'):
          return ApiResponse.ok(WorkflowTemplateCatalog.toMap());
        case (ApiMethod.post, '/api/v1/rules/evaluate'):
          return ApiResponse.ok(_evaluateRules(request.body));
        case (ApiMethod.get, '/api/v1/events'):
          return ApiResponse.ok(
            (await _eventStore.load(
              afterSequence: _int(request.query['after'], fallback: 0),
              limit: _int(request.query['limit'], fallback: 200),
            )).map((event) => event.toMap()).toList(),
          );
        case (ApiMethod.post, '/api/v1/events/replay'):
          return ApiResponse.ok(
            (await _eventDispatcher.dispatchPending(
              limit: _int(request.body['limit'], fallback: 100),
            )).toMap(),
          );
        case (ApiMethod.get, '/api/v1/cqrs/executive-dashboard'):
          final scope = await _branchScope.current();
          return ApiResponse.ok(
            (await _dashboardProjection.read(
              companyId: scope.companyId,
              branchId: scope.branchId,
            )).toMap(),
          );
        default:
          return ApiResponse.error(
            405,
            'Operacion API no soportada por el dispatcher.',
          );
      }
    } catch (error) {
      return ApiResponse.error(400, error.toString());
    }
  }

  ApiResponse _paged(
    List<Map<String, Object?>> items,
    Map<String, String> query,
  ) {
    final page = PageRequest.fromQuery(query);
    return ApiResponse.ok(
      page.apply(items),
      meta: {'pagination': page.meta(items.length)},
    );
  }

  Future<Map<String, Object?>> _summary() async {
    final products = await _products.findAll();
    final currency = products.isEmpty
        ? await _currencyResolver()
        : products.first.cost.currency;
    final inventory = products.isEmpty
        ? InventorySummary.empty(currency)
        : InventorySummary.fromProducts(products);
    final salesTotal = await _sales.totalSales();
    final purchasesTotal = await _purchases.totalPurchases();
    return {
      'inventory': {
        'products': inventory.productCount,
        'low_stock': inventory.lowStockCount,
        'cost_value': _moneyWire(inventory.costValue),
        'sale_value': _moneyWire(inventory.saleValue),
      },
      'sales_total': _moneyWire(salesTotal),
      'purchases_total': _moneyWire(purchasesTotal),
    };
  }

  Future<CreateSaleRequest> _saleRequestFromBody(
    Map<String, dynamic> body,
  ) async {
    final currency = await _currencyResolver();
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    return CreateSaleRequest(
      items: _list(
        body['items'],
      ).map((item) => _saleItem(_map(item), currency)).toList(),
      paymentMethodId: _int(body['payment_method_id'], fallback: 1),
      paymentMethodName: body['payment_method']?.toString() ?? 'EFECTIVO',
      clientId: _nullableInt(body['client_id']),
      clientName: body['client']?.toString() ?? 'Cliente general',
      date: _date(body['date']),
      efectivo: _apiMoney(body['cash'], currency, fallback: zero),
      transferencia: _apiMoney(body['bank'], currency, fallback: zero),
      credito: _apiMoney(body['credit'], currency, fallback: zero),
      retefuente: _apiMoney(body['retefuente'], currency, fallback: zero),
      reteiva: _apiMoney(body['reteiva'], currency, fallback: zero),
      reteica: _apiMoney(body['reteica'], currency, fallback: zero),
    );
  }

  Future<CreatePurchaseRequest> _purchaseRequestFromBody(
    Map<String, dynamic> body,
  ) async {
    final currency = await _currencyResolver();
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    return CreatePurchaseRequest(
      supplierId: _int(body['supplier_id'], fallback: 0),
      supplierName: body['supplier']?.toString() ?? 'Sin proveedor',
      invoiceNumber: body['invoice_number']?.toString() ?? '',
      observation: body['observation']?.toString() ?? '',
      paymentMethodId: _int(body['payment_method_id'], fallback: 1),
      paymentMethodName: body['payment_method']?.toString() ?? 'EFECTIVO',
      taxRate: _double(body['tax_rate']),
      manualCash: _apiMoney(body['cash'], currency, fallback: zero),
      manualBank: _apiMoney(body['bank'], currency, fallback: zero),
      manualCredit: _apiMoney(body['credit'], currency, fallback: zero),
      retefuente: _apiMoney(body['retefuente'], currency, fallback: zero),
      reteiva: _apiMoney(body['reteiva'], currency, fallback: zero),
      reteica: _apiMoney(body['reteica'], currency, fallback: zero),
      items: _list(
        body['items'],
      ).map((item) => _purchaseItem(_map(item), currency)).toList(),
      date: _date(body['date']),
    );
  }

  Future<CreatePurchaseDocumentCommand> _createPurchaseDocumentCommand(
    ApiRequest request,
  ) async {
    final body = request.body;
    final currency = await _currencyResolver();
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    return CreatePurchaseDocumentCommand(
      type:
          _purchaseType(body['type']?.toString()) ??
          PurchaseDocumentType.purchaseOrder,
      supplierId: _int(body['supplier_id'], fallback: 0),
      supplierName: body['supplier']?.toString() ?? 'Sin proveedor',
      issueDate: _date(body['issue_date'] ?? body['date']),
      dueDate: _date(body['due_date']),
      country: body['country']?.toString() ?? 'Colombia',
      budgetCode: body['budget_code']?.toString(),
      budgetAvailable: _apiMoney(
        body['budget_available'],
        currency,
        fallback: zero,
      ),
      retentionRate: _double(body['retention_rate']),
      userId: request.userId,
      role: request.role,
      correlationId: request.requestId,
      lines: _list(
        body['lines'] ?? body['items'],
      ).map((item) => _purchaseDocumentLine(_map(item), currency)).toList(),
    );
  }

  PurchaseDocumentLine _purchaseDocumentLine(
    Map<String, dynamic> item,
    Currency currency,
  ) {
    return PurchaseDocumentLine(
      productId: _int(item['product_id'] ?? item['producto_id'], fallback: 0),
      productName: (item['product'] ?? item['producto'] ?? '').toString(),
      quantity: _double(item['quantity'] ?? item['cantidad']),
      unitCost: _apiMoney(item['unit_cost'] ?? item['costo'], currency),
      receivedQuantity: _double(item['received_quantity']),
      taxCode: item['tax_code']?.toString() ?? 'EXEMPT',
      taxRate: _double(item['tax_rate'] ?? item['impuesto_pct']),
      retentionRate: _double(item['retention_rate']),
      warehouseId: _int(item['warehouse_id'], fallback: 1),
    );
  }

  Future<CreateSalesDocumentCommand> _createSalesDocumentCommand(
    ApiRequest request,
  ) async {
    final body = request.body;
    final currency = await _currencyResolver();
    return CreateSalesDocumentCommand(
      type: _salesType(body['type']?.toString()) ?? SalesDocumentType.invoice,
      customerId: _nullableInt(body['customer_id']),
      customerName: body['customer']?.toString() ?? 'Cliente general',
      paymentMethod: body['payment_method']?.toString() ?? 'EFECTIVO',
      creditDays: _int(body['credit_days'], fallback: 0),
      issueDate: _date(body['issue_date'] ?? body['date']),
      userId: request.userId,
      role: request.role,
      correlationId: request.requestId,
      lines: _list(
        body['lines'] ?? body['items'],
      ).map((item) => _salesDocumentLine(_map(item), currency)).toList(),
    );
  }

  SalesDocumentLine _salesDocumentLine(
    Map<String, dynamic> item,
    Currency currency,
  ) {
    final quantity = _double(item['quantity'] ?? item['cantidad']);
    final unitPrice = _apiMoney(item['unit_price'] ?? item['precio'], currency);
    final discount = _apiMoney(
      item['discount'] ?? item['descuento'],
      currency,
      fallback: MoneyValue(minorUnits: 0, currency: currency),
    );
    final taxRate = _double(item['tax_rate'] ?? item['impuesto_pct']);
    final calculatedSubtotal =
        unitPrice.multiplyDecimal(quantity.toString()) - discount;
    final explicitSubtotal = item['subtotal'];
    final subtotal = explicitSubtotal == null
        ? calculatedSubtotal
        : _apiMoney(explicitSubtotal, currency);
    final explicitTax = item['tax_total'] ?? item['impuesto_total'];
    final taxTotal = explicitTax == null
        ? subtotal.percent(taxRate.toString())
        : _apiMoney(explicitTax, currency);
    return SalesDocumentLine(
      productId: _int(item['product_id'] ?? item['producto_id'], fallback: 0),
      productName: (item['product'] ?? item['producto'] ?? '').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      discount: discount,
      taxRate: taxRate,
      taxTotal: taxTotal,
      warehouseId: _int(item['warehouse_id'], fallback: 1),
    );
  }

  SaleItemInput _saleItem(Map<String, dynamic> item, Currency currency) {
    return SaleItemInput(
      productId: _int(item['product_id'] ?? item['producto_id'], fallback: 0),
      productName: (item['product'] ?? item['producto'] ?? '').toString(),
      quantity: _double(item['quantity'] ?? item['cantidad']),
      unitPrice: _apiMoney(item['unit_price'] ?? item['precio'], currency),
      unitCost: _apiMoney(item['unit_cost'] ?? item['costo'], currency),
      subtotal: _apiMoney(item['subtotal'], currency),
      taxRate: _double(item['tax_rate'] ?? item['impuesto_pct']),
      taxTotal: _apiMoney(
        item['tax_total'] ?? item['impuesto_total'],
        currency,
      ),
    );
  }

  PurchaseItemInput _purchaseItem(
    Map<String, dynamic> item,
    Currency currency,
  ) {
    return PurchaseItemInput(
      productId: _int(item['product_id'] ?? item['producto_id'], fallback: 0),
      productName: (item['product'] ?? item['producto'] ?? '').toString(),
      quantity: _double(item['quantity'] ?? item['cantidad']),
      unitCost: _apiMoney(item['unit_cost'] ?? item['costo'], currency),
      subtotal: _apiMoney(item['subtotal'], currency),
      taxAmount: _apiMoney(
        item['tax_amount'] ?? item['tax_total'] ?? item['impuesto_total'],
        currency,
      ),
    );
  }

  Map<String, Object?> _saleResultToMap(CreateSaleResult result) => {
    'sale_id': result.saleId,
    'subtotal': _moneyWire(result.subtotal),
    'tax': _moneyWire(result.tax),
    'total': _moneyWire(result.total),
    'cost_of_sale': _moneyWire(result.costOfSale),
  };

  Map<String, Object?> _purchaseResultToMap(CreatePurchaseResult result) => {
    'purchase_id': result.purchaseId,
    'subtotal': _moneyWire(result.subtotal),
    'tax': _moneyWire(result.tax),
    'total': _moneyWire(result.total),
    'payment': {
      'cash': _moneyWire(result.payment.cash),
      'bank': _moneyWire(result.payment.bank),
      'credit': _moneyWire(result.payment.credit),
    },
  };

  ProcurementSnapshot _procurementSnapshotFromQuery(Map<String, String> query) {
    return ProcurementSnapshot(
      requested: _bool(query['requested']),
      approved: _bool(query['approved']),
      ordered: _bool(query['ordered']),
      received: _bool(query['received']),
      invoiced: _bool(query['invoiced']),
      payableCreated: _bool(query['payable_created']),
      paid: _bool(query['paid']),
      returned: _bool(query['returned']),
      closed: _bool(query['closed']),
      requiresApproval: !_bool(query['skip_approval']),
    );
  }

  SalesSnapshot _salesSnapshotFromQuery(Map<String, String> query) {
    return SalesSnapshot(
      quoted: _bool(query['quoted']),
      ordered: _bool(query['ordered']),
      delivered: _bool(query['delivered']),
      invoiced: _bool(query['invoiced']),
      receivableCreated: _bool(query['receivable_created']),
      collected: _bool(query['collected']),
      creditNoteIssued: _bool(query['credit_note']),
      closed: _bool(query['closed']),
      creditSale: _bool(query['credit_sale']),
    );
  }

  Map<String, Object?> _evaluateRules(Map<String, dynamic> body) {
    final rules = _list(
      body['rules'],
    ).map((item) => _ruleFromMap(_map(item))).toList();
    final context = _map(body['context']);
    final results = _ruleEngine.evaluate(rules, context);
    return {
      'matched_actions': results
          .where((result) => result.matched)
          .expand((result) => result.actions)
          .map((action) => action.toMap())
          .toList(),
      'results': results.map((result) => result.toMap()).toList(),
    };
  }

  BusinessRule _ruleFromMap(Map<String, dynamic> map) {
    return BusinessRule(
      id: map['id']?.toString() ?? 'rule',
      name: map['name']?.toString() ?? 'Regla',
      priority: _int(map['priority'], fallback: 100),
      enabled: !_bool(map['disabled']),
      conditions: _list(
        map['conditions'],
      ).map((item) => _conditionFromMap(_map(item))).toList(),
      actions: _list(map['actions'])
          .map(
            (item) => RuleAction(
              type: _map(item)['type']?.toString() ?? 'noop',
              parameters:
                  (_map(item)['parameters'] as Map?)?.map(
                    (key, value) => MapEntry(key.toString(), value),
                  ) ??
                  const {},
            ),
          )
          .toList(),
    );
  }

  RuleCondition _conditionFromMap(Map<String, dynamic> map) {
    final operator = RuleOperator.values.firstWhere(
      (item) => item.name == map['operator']?.toString(),
      orElse: () => RuleOperator.equals,
    );
    return RuleCondition(
      field: map['field']?.toString() ?? '',
      operator: operator,
      value: map['value'],
      secondValue: map['second_value'],
    );
  }

  List<Object?> _list(Object? value) {
    if (value is List) return value;
    return const [];
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw Exception('Se esperaba un objeto JSON.');
  }

  int _int(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  MoneyValue _apiMoney(
    Object? value,
    Currency currency, {
    MoneyValue? fallback,
  }) {
    if (value == null) {
      return fallback ?? MoneyValue(minorUnits: 0, currency: currency);
    }
    if (value is Map) {
      final map = _map(value);
      final code = map['currency']?.toString();
      final scale = _nullableInt(map['scale']);
      if (code != currency.code || scale != currency.decimalPlaces) {
        throw StateError(
          'La moneda/escala del payload no coincide con la empresa.',
        );
      }
      return MoneyValue(
        minorUnits: _int(map['minor_units'], fallback: 0),
        currency: currency,
      );
    }
    return MoneyValue.fromMajorUnits(
      value.toString().replaceAll(',', '.'),
      currency: currency,
    );
  }

  Map<String, Object> _moneyWire(MoneyValue value) => {
    'minor_units': value.minorUnits,
    'currency': value.currencyCode,
    'scale': value.decimalPlaces,
  };

  DateTime? _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  bool _bool(Object? value) {
    final text = value?.toString().toLowerCase().trim();
    return text == '1' || text == 'true' || text == 'yes' || text == 'si';
  }

  Map<int, double> _quantityMap(Object? value) {
    final map = _map(value);
    return map.map(
      (key, value) => MapEntry(int.tryParse(key) ?? 0, _double(value)),
    )..removeWhere((key, value) => key == 0 || value <= 0);
  }

  SalesDocumentState? _salesState(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    for (final item in SalesDocumentState.values) {
      if (item.name == text) return item;
    }
    return null;
  }

  SalesDocumentType? _salesType(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    for (final item in SalesDocumentType.values) {
      if (item.name == text) return item;
    }
    return null;
  }

  PurchaseDocumentState? _purchaseState(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    for (final item in PurchaseDocumentState.values) {
      if (item.name == text) return item;
    }
    return null;
  }

  PurchaseDocumentType? _purchaseType(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    for (final item in PurchaseDocumentType.values) {
      if (item.name == text) return item;
    }
    return null;
  }
}
