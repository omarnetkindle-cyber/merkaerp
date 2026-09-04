import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/crm_contact.dart';

abstract class CrmContactRepository {
  Future<List<CrmContact>> findByAccount(int accountId);
  Future<CrmContact?> findById(int id);
  Future<int> save(CrmContact contact);
  Future<void> delete(int id);
}

class SqliteCrmContactRepository implements CrmContactRepository {
  SqliteCrmContactRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );

  final TenantDatabaseGateway _tenant;

  @override
  Future<List<CrmContact>> findByAccount(int accountId) async {
    final rows = await _tenant.query(
      'crm_contacts',
      query: TenantQuery(
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'last_name ASC, first_name ASC',
      ),
    );
    return rows.map(CrmContact.fromMap).toList();
  }

  @override
  Future<CrmContact?> findById(int id) async {
    final rows = await _tenant.query(
      'crm_contacts',
      query: TenantQuery(where: 'id = ?', whereArgs: [id], limit: 1),
    );
    return rows.isEmpty ? null : CrmContact.fromMap(rows.first);
  }

  @override
  Future<int> save(CrmContact contact) async {
    final values = contact.toPersistenceMap()..remove('company_id');
    if (contact.id == null) {
      return _tenant.insert('crm_contacts', values);
    }
    values.remove('id');
    return _tenant.update(
      'crm_contacts',
      values,
      query: TenantQuery(where: 'id = ?', whereArgs: [contact.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> delete(int id) async {
    await _tenant.delete(
      'crm_contacts',
      query: TenantQuery(where: 'id = ?', whereArgs: [id]),
    );
  }
}
