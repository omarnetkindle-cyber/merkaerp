import 'package:sqflite/sqflite.dart';

import '../company/company_context.dart';
import 'database_gateway.dart';

class TenantQuery {
  const TenantQuery({
    this.where,
    this.whereArgs = const [],
    this.orderBy,
    this.limit,
    this.offset,
  });

  final String? where;
  final List<Object?> whereArgs;
  final String? orderBy;
  final int? limit;
  final int? offset;
}

class TenantDatabaseGateway {
  TenantDatabaseGateway({
    required DatabaseGateway gateway,
    required CompanyContextProvider companyContext,
  }) : _gateway = gateway,
       _companyContext = companyContext;

  final DatabaseGateway _gateway;
  final CompanyContextProvider _companyContext;

  Future<int> get companyId async =>
      (await _companyContext.current()).companyId;

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    TenantQuery query = const TenantQuery(),
  }) async {
    final scope = await _scopedWhere(query.where, query.whereArgs);
    return _gateway.query(
      table,
      columns: columns,
      where: scope.where,
      whereArgs: scope.args,
      orderBy: query.orderBy,
      limit: query.limit,
      offset: query.offset,
    );
  }

  Future<Map<String, dynamic>?> findById(String table, int id) async {
    final rows = await query(
      table,
      query: TenantQuery(where: 'id = ?', whereArgs: [id], limit: 1),
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    return _gateway.insert(table, {...values, 'company_id': await companyId});
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    required TenantQuery query,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final scope = await _scopedWhere(query.where, query.whereArgs);
    return _gateway.update(
      table,
      values,
      where: scope.where,
      whereArgs: scope.args,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  Future<int> delete(String table, {required TenantQuery query}) async {
    final scope = await _scopedWhere(query.where, query.whereArgs);
    return _gateway.delete(table, where: scope.where, whereArgs: scope.args);
  }

  Future<_ScopedWhere> _scopedWhere(
    String? where,
    List<Object?> whereArgs,
  ) async {
    final tenantId = await companyId;
    if (where == null || where.trim().isEmpty) {
      return _ScopedWhere('company_id = ?', [tenantId]);
    }
    return _ScopedWhere('company_id = ? AND ($where)', [
      tenantId,
      ...whereArgs,
    ]);
  }
}

class _ScopedWhere {
  const _ScopedWhere(this.where, this.args);

  final String where;
  final List<Object?> args;
}
