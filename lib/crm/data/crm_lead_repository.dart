import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../db_helper.dart';
import '../domain/crm_lead.dart';

abstract class CrmLeadRepository {
  Future<List<CrmLead>> findAll();
  Future<CrmLead?> findById(int id);
  Future<int> save(CrmLead lead);
}

class SqliteCrmLeadRepository implements CrmLeadRepository {
  SqliteCrmLeadRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
    Future<Currency> Function(int companyId)? resolveCurrency,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       ),
       _resolveCurrency = resolveCurrency;

  final TenantDatabaseGateway _tenant;
  final Future<Currency> Function(int companyId)? _resolveCurrency;

  Future<Currency> _currency() async {
    final companyId = await _tenant.companyId;
    return (_resolveCurrency ??
        ((id) async => MoneyCurrencyResolver.resolve(
          await DatabaseHelper.instance.database,
          companyId: id,
        )))(companyId);
  }

  @override
  Future<List<CrmLead>> findAll() async {
    final rows = await _tenant.query(
      'crm_leads',
      query: const TenantQuery(orderBy: 'created_at DESC'),
    );
    final currency = await _currency();
    return rows.map((row) => CrmLead.fromMap(row, currency: currency)).toList();
  }

  @override
  Future<CrmLead?> findById(int id) async {
    final rows = await _tenant.query(
      'crm_leads',
      query: TenantQuery(where: 'id = ?', whereArgs: [id], limit: 1),
    );
    if (rows.isEmpty) return null;
    return CrmLead.fromMap(rows.first, currency: await _currency());
  }

  @override
  Future<int> save(CrmLead lead) async {
    final values = lead.toPersistenceMap()..remove('company_id');
    if (lead.id == null) {
      return _tenant.insert('crm_leads', values);
    }
    values.remove('id');
    return _tenant.update(
      'crm_leads',
      values,
      query: TenantQuery(where: 'id = ?', whereArgs: [lead.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
