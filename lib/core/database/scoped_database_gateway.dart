import 'package:sqflite/sqflite.dart';

import '../branch/branch_context.dart';
import 'database_gateway.dart';
import 'tenant_database_gateway.dart';

class ScopeQuery {
  const ScopeQuery({
    this.where,
    this.whereArgs = const [],
    this.orderBy,
    this.limit,
    this.offset,
    this.byBranch = true,
    this.byWarehouse = false,
    this.byCostCenter = false,
  });

  final String? where;
  final List<Object?> whereArgs;
  final String? orderBy;
  final int? limit;
  final int? offset;
  final bool byBranch;
  final bool byWarehouse;
  final bool byCostCenter;
}

class ScopedDatabaseGateway {
  ScopedDatabaseGateway({
    required DatabaseGateway gateway,
    required BranchScopeProvider scopeProvider,
  }) : _gateway = gateway,
       _scopeProvider = scopeProvider;

  final DatabaseGateway _gateway;
  final BranchScopeProvider _scopeProvider;

  Future<BranchScope> get scope => _scopeProvider.current();

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    ScopeQuery query = const ScopeQuery(),
  }) async {
    final scoped = await _scopedWhere(query);
    return _gateway.query(
      table,
      columns: columns,
      where: scoped.where,
      whereArgs: scoped.args,
      orderBy: query.orderBy,
      limit: query.limit,
      offset: query.offset,
    );
  }

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool includeBranch = true,
    bool includeWarehouse = false,
    bool includeCostCenter = false,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final current = await scope;
    return _gateway.insert(table, {
      ...values,
      'company_id': current.companyId,
      if (includeBranch) 'branch_id': current.branchId,
      if (includeWarehouse) 'warehouse_id': current.warehouseId,
      if (includeCostCenter) 'cost_center_id': current.costCenterId,
    }, conflictAlgorithm: conflictAlgorithm);
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    required ScopeQuery query,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final scoped = await _scopedWhere(query);
    return _gateway.update(
      table,
      values,
      where: scoped.where,
      whereArgs: scoped.args,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  Future<int> delete(String table, {required ScopeQuery query}) async {
    final scoped = await _scopedWhere(query);
    return _gateway.delete(table, where: scoped.where, whereArgs: scoped.args);
  }

  Future<_ScopedWhere> _scopedWhere(ScopeQuery query) async {
    final current = await scope;
    final parts = <String>['company_id = ?'];
    final args = <Object?>[current.companyId];

    if (query.byBranch) {
      parts.add('branch_id = ?');
      args.add(current.branchId);
    }
    if (query.byWarehouse) {
      parts.add('warehouse_id = ?');
      args.add(current.warehouseId);
    }
    if (query.byCostCenter) {
      parts.add('cost_center_id = ?');
      args.add(current.costCenterId);
    }
    if (query.where != null && query.where!.trim().isNotEmpty) {
      parts.add('(${query.where})');
      args.addAll(query.whereArgs);
    }

    return _ScopedWhere(parts.join(' AND '), args);
  }
}

class BranchAwareTenantDatabaseGateway extends TenantDatabaseGateway {
  BranchAwareTenantDatabaseGateway({
    required super.gateway,
    required super.companyContext,
    required this.branchScope,
  });

  final BranchScopeProvider branchScope;

  Future<int> get branchId async => (await branchScope.current()).branchId;
}

class _ScopedWhere {
  const _ScopedWhere(this.where, this.args);

  final String where;
  final List<Object?> args;
}
