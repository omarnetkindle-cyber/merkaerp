import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../db_helper.dart';
import '../domain/crm_opportunity.dart';

abstract class CrmOpportunityRepository {
  Future<List<CrmOpportunity>> findAll();
  Future<List<CrmOpportunity>> findByAccount(int accountId);
  Future<CrmOpportunity?> findById(String id);
  Future<String> save(CrmOpportunity opportunity);
  Future<void> update(CrmOpportunity opportunity);
}

class SqliteCrmOpportunityRepository implements CrmOpportunityRepository {
  SqliteCrmOpportunityRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
    Future<Currency> Function(int companyId)? resolveCurrency,
  }) : _gateway = gateway,
       _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       ),
       _resolveCurrency = resolveCurrency;

  final DatabaseGateway _gateway;
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
  Future<List<CrmOpportunity>> findAll() async {
    final rows = await _tenant.query(
      'crm_opportunities',
      query: const TenantQuery(orderBy: 'next_follow_up_at ASC'),
    );
    final currency = await _currency();
    return rows
        .map((row) => CrmOpportunity.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<List<CrmOpportunity>> findByAccount(int accountId) async {
    final rows = await _tenant.query(
      'crm_opportunities',
      query: TenantQuery(
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'created_at DESC',
      ),
    );
    final currency = await _currency();
    return rows
        .map((row) => CrmOpportunity.fromMap(row, currency: currency))
        .toList();
  }

  @override
  Future<CrmOpportunity?> findById(String id) async {
    final rows = await _tenant.query(
      'crm_opportunities',
      query: TenantQuery(where: 'id = ?', whereArgs: [id], limit: 1),
    );
    if (rows.isEmpty) return null;
    return CrmOpportunity.fromMap(rows.first, currency: await _currency());
  }

  @override
  Future<String> save(CrmOpportunity opportunity) async {
    final values = opportunity.toPersistenceMap()..remove('company_id');
    await _tenant.insert('crm_opportunities', values);
    return opportunity.id;
  }

  @override
  Future<void> update(CrmOpportunity opportunity) async {
    final values = opportunity.toPersistenceMap()..remove('company_id');
    values.remove('id');
    final companyId = await _tenant.companyId;
    final updated = await _gateway.update(
      'crm_opportunities',
      values,
      where: 'id = ? AND company_id = ?',
      whereArgs: [opportunity.id, companyId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated == 0) {
      throw StateError('CRM opportunity not found in active company');
    }
  }
}
