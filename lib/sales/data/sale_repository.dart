import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../domain/sale.dart';

abstract class SaleRepository {
  Future<List<Sale>> findAll();

  Future<List<Sale>> findActive();

  Future<List<SaleLine>> findDetails(int saleId);

  Future<MoneyValue> totalSales();

  Future<int> createHeader(Map<String, dynamic> values);

  Future<void> cancel(int saleId);
}

class SqliteSaleRepository implements SaleRepository {
  SqliteSaleRepository({
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
  Future<void> cancel(int saleId) async {
    await _db.anularVenta(saleId);
  }

  @override
  Future<int> createHeader(Map<String, dynamic> values) async {
    await _validateFeature(FeatureKey.pos);
    return await _tenantGateway.insert('ventas', values);
  }

  @override
  Future<List<Sale>> findActive() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _tenantGateway.query(
      'ventas',
      query: const TenantQuery(
        where: "COALESCE(estado, 'emitida') != 'anulada'",
        orderBy: 'fecha DESC',
      ),
    );
    return rows.map((row) => Sale.fromMap(row, currency: currency)).toList();
  }

  @override
  Future<List<Sale>> findAll() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _tenantGateway.query(
      'ventas',
      query: const TenantQuery(orderBy: 'fecha DESC'),
    );
    return rows.map((row) => Sale.fromMap(row, currency: currency)).toList();
  }

  @override
  Future<List<SaleLine>> findDetails(int saleId) async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _gateway.rawQuery(
      '''
      SELECT
        vd.*,
        p.unidad_base,
        p.codigo_barras
      FROM ventas_detalle vd
      INNER JOIN ventas v ON v.id = vd.venta_id
      LEFT JOIN productos p ON p.id = vd.producto_id
      WHERE vd.venta_id = ? AND v.company_id = ?
      ORDER BY vd.id ASC
      ''',
      [saleId, companyId],
    );
    return rows
        .map((row) => SaleLine.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<MoneyValue> totalSales() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _gateway.rawQuery(
      "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND COALESCE(estado, 'emitida') != 'anulada'",
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
