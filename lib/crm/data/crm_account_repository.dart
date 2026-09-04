import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/crm_account.dart';

abstract class CrmAccountRepository {
  Future<List<CrmAccount>> findAll();
  Future<CrmAccount?> findById(int id);
  Future<int> save(CrmAccount account);
  Future<void> delete(int id);
}

class SqliteCrmAccountRepository implements CrmAccountRepository {
  SqliteCrmAccountRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );

  final TenantDatabaseGateway _tenant;

  @override
  Future<List<CrmAccount>> findAll() async {
    final rows = await _tenant.query(
      'clientes',
      query: const TenantQuery(orderBy: 'nombre ASC'),
    );
    return rows.map(CrmAccount.fromMap).toList();
  }

  @override
  Future<CrmAccount?> findById(int id) async {
    final rows = await _tenant.query(
      'clientes',
      query: TenantQuery(where: 'id = ?', whereArgs: [id], limit: 1),
    );
    return rows.isEmpty ? null : CrmAccount.fromMap(rows.first);
  }

  @override
  Future<int> save(CrmAccount account) async {
    final values = account.toPersistenceMap()..remove('company_id');
    if (account.id == null) {
      return _tenant.insert('clientes', values);
    }
    values.remove('id');
    return _tenant.update(
      'clientes',
      values,
      query: TenantQuery(where: 'id = ?', whereArgs: [account.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> delete(int id) async {
    await _tenant.delete(
      'clientes',
      query: TenantQuery(where: 'id = ?', whereArgs: [id]),
    );
  }
}
