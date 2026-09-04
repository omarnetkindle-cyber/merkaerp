import '../../core/company/company_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../db_helper.dart';
import '../domain/trial_balance.dart';

abstract class AccountingReportRepository {
  Future<TrialBalance> trialBalance();
}

class SqliteAccountingReportRepository implements AccountingReportRepository {
  SqliteAccountingReportRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
    DatabaseHelper? db,
    Future<Currency> Function(int companyId)? resolveCurrency,
  }) : _gateway = gateway,
       _resolveCurrency =
           resolveCurrency ??
           ((companyId) async {
             final database = await (db ?? DatabaseHelper.instance).database;
             return MoneyCurrencyResolver.resolve(
               database,
               companyId: companyId,
             );
           }),
       _tenantGateway = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );

  final DatabaseGateway _gateway;
  final Future<Currency> Function(int companyId) _resolveCurrency;
  final TenantDatabaseGateway _tenantGateway;

  @override
  Future<TrialBalance> trialBalance() async {
    final companyId = await _tenantGateway.companyId;
    final currency = await _resolveCurrency(companyId);
    final rows = await _gateway.rawQuery(
      '''
      SELECT
        c.id,
        c.codigo,
        c.nombre,
        c.tipo,
        c.naturaleza,
        COALESCE(SUM(l.debito), 0) AS debito,
        COALESCE(SUM(l.credito), 0) AS credito,
        CASE
          WHEN c.naturaleza = 'debito'
          THEN COALESCE(SUM(l.debito), 0) - COALESCE(SUM(l.credito), 0)
          ELSE COALESCE(SUM(l.credito), 0) - COALESCE(SUM(l.debito), 0)
        END AS saldo
      FROM cuentas_contables c
      LEFT JOIN asiento_lineas l ON l.cuenta_id = c.id AND l.company_id = ?
      WHERE c.activa = 1
      GROUP BY c.id
      ORDER BY c.codigo ASC
      ''',
      [companyId],
    );
    return TrialBalance(
      accounts: rows
          .map((row) => TrialBalanceAccount.fromMap(row, currency: currency))
          .toList(),
    );
  }
}
