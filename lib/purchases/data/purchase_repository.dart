import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../domain/purchase.dart';

abstract class PurchaseRepository {
  Future<List<Purchase>> findAll();

  Future<List<Purchase>> findActive();

  Future<List<PurchaseLine>> findDetails(int purchaseId);

  Future<MoneyValue> totalPurchases();

  Future<int> createHeader(Map<String, dynamic> values);

  Future<void> cancel(int purchaseId);
}

class SqlitePurchaseRepository implements PurchaseRepository {
  SqlitePurchaseRepository({
    DatabaseHelper? db,
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
    Future<void> Function(String featureKey)? validateFeature,
    Future<Currency> Function(int companyId)? resolveCurrency,
  }) : _db = db ?? DatabaseHelper.instance,
       _gateway = gateway,
       _tenantGateway = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       ),
       _validateFeature =
           validateFeature ?? DatabaseHelper.instance.validarFeatureHabilitada,
       _resolveCurrency =
           resolveCurrency ??
           ((companyId) async {
             final database = await (db ?? DatabaseHelper.instance).database;
             return MoneyCurrencyResolver.resolve(
               database,
               companyId: companyId,
             );
           });

  final DatabaseHelper _db;
  final DatabaseGateway _gateway;
  final TenantDatabaseGateway _tenantGateway;
  final Future<void> Function(String featureKey) _validateFeature;
  final Future<Currency> Function(int companyId) _resolveCurrency;

  @override
  Future<void> cancel(int purchaseId) async {
    await _db.eliminarCompra(purchaseId);
  }

  @override
  Future<int> createHeader(Map<String, dynamic> values) async {
    await _validateFeature(FeatureKey.purchases);
    return await _tenantGateway.insert('compras', values);
  }

  @override
  Future<List<Purchase>> findActive() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _tenantGateway.query(
      'compras',
      query: const TenantQuery(
        where: "COALESCE(estado, 'pagada') != 'anulada'",
        orderBy: 'fecha DESC',
      ),
    );
    return rows
        .map((row) => Purchase.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<List<Purchase>> findAll() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _tenantGateway.query(
      'compras',
      query: const TenantQuery(orderBy: 'fecha DESC'),
    );
    return rows
        .map((row) => Purchase.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<List<PurchaseLine>> findDetails(int purchaseId) async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _gateway.rawQuery(
      '''
      SELECT
        cd.*,
        p.unidad_base,
        p.codigo_barras
      FROM compras_detalle cd
      INNER JOIN compras c ON c.id = cd.compra_id
      LEFT JOIN productos p ON p.id = cd.producto_id
      WHERE cd.compra_id = ? AND c.company_id = ?
      ORDER BY cd.id ASC
      ''',
      [purchaseId, companyId],
    );
    return rows
        .map((row) => PurchaseLine.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<MoneyValue> totalPurchases() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _gateway.rawQuery(
      "SELECT COALESCE(SUM(total), 0) AS total FROM compras WHERE company_id = ? AND COALESCE(estado, 'pagada') != 'anulada'",
      [companyId],
    );
    if (rows.isEmpty) return MoneyValue(minorUnits: 0, currency: currency);
    return MoneyValue.fromSql(
      rows.first['total'],
      currency: currency,
      nullableAsZero: true,
    );
  }
}
