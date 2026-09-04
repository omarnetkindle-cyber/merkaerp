import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../db_helper.dart';
import '../domain/crm_opportunity_item.dart';

abstract class CrmOpportunityItemRepository {
  Future<List<CrmOpportunityItem>> findByOpportunity(String opportunityId);
  Future<int> save(CrmOpportunityItem item);
  Future<void> delete(int id);
}

class SqliteCrmOpportunityItemRepository
    implements CrmOpportunityItemRepository {
  SqliteCrmOpportunityItemRepository({
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
  Future<List<CrmOpportunityItem>> findByOpportunity(
    String opportunityId,
  ) async {
    final rows = await _tenant.query(
      'crm_opportunity_items',
      query: TenantQuery(
        where: 'opportunity_id = ?',
        whereArgs: [opportunityId],
        orderBy: 'id ASC',
      ),
    );
    final currency = await _currency();
    return rows
        .map((row) => CrmOpportunityItem.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<int> save(CrmOpportunityItem item) async {
    final values = item.toPersistenceMap()..remove('company_id');
    if (item.id == null) return _tenant.insert('crm_opportunity_items', values);
    values.remove('id');
    return _tenant.update(
      'crm_opportunity_items',
      values,
      query: TenantQuery(where: 'id = ?', whereArgs: [item.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> delete(int id) async {
    await _tenant.delete(
      'crm_opportunity_items',
      query: TenantQuery(where: 'id = ?', whereArgs: [id]),
    );
  }
}
