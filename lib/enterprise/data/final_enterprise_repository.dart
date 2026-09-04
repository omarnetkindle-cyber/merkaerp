import 'dart:convert';

import '../../core/branch/branch_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../db_helper.dart';

abstract class FinalEnterpriseRepository {
  Future<int> insertScoped(String table, Map<String, Object?> values);

  Future<int> updateScoped(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  });

  Future<List<Map<String, dynamic>>> queryScoped(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  });

  Future<List<Map<String, dynamic>>> rawScoped(
    String sql,
    List<Object?> arguments,
  );

  Future<void> audit({
    required String action,
    required String entity,
    required String userId,
    int? entityId,
    Map<String, Object?> payload,
  });

  Future<BranchScope> scope();

  Future<Currency> currency();
}

class SqliteFinalEnterpriseRepository implements FinalEnterpriseRepository {
  SqliteFinalEnterpriseRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    BranchScopeProvider? scopeProvider,
    DatabaseHelper? db,
  }) : _gateway = gateway,
       _scopeProvider = scopeProvider ?? BranchContextService.instance,
       _db = db ?? DatabaseHelper.instance;

  final DatabaseGateway _gateway;
  final BranchScopeProvider _scopeProvider;
  final DatabaseHelper _db;

  @override
  Future<BranchScope> scope() => _scopeProvider.current();

  @override
  Future<Currency> currency() async {
    final currentScope = await scope();
    return MoneyCurrencyResolver.resolve(
      await _db.database,
      companyId: currentScope.companyId,
    );
  }

  @override
  Future<int> insertScoped(String table, Map<String, Object?> values) async {
    final current = await scope();
    return _gateway.insert(table, {
      'company_id': current.companyId,
      'branch_id': current.branchId,
      'warehouse_id': current.warehouseId,
      'cost_center_id': current.costCenterId,
      ...values,
    });
  }

  @override
  Future<int> updateScoped(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final current = await scope();
    return _gateway.update(
      table,
      values,
      where: 'company_id = ? AND branch_id = ? AND $where',
      whereArgs: [current.companyId, current.branchId, ...whereArgs],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> queryScoped(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final current = await scope();
    final scopedWhere = where == null
        ? 'company_id = ? AND branch_id = ?'
        : 'company_id = ? AND branch_id = ? AND $where';
    return _gateway.query(
      table,
      where: scopedWhere,
      whereArgs: [current.companyId, current.branchId, ...?whereArgs],
      orderBy: orderBy,
      limit: limit,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> rawScoped(
    String sql,
    List<Object?> arguments,
  ) async {
    final current = await scope();
    return _gateway.rawQuery(sql, [
      current.companyId,
      current.branchId,
      ...arguments,
    ]);
  }

  @override
  Future<void> audit({
    required String action,
    required String entity,
    required String userId,
    int? entityId,
    Map<String, Object?> payload = const {},
  }) async {
    await insertScoped('enterprise_audit_log', {
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'user_id': userId,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _db.registrarEventoAuditoria(
      accion: action,
      entidad: entity,
      entidadId: entityId,
      detalle: jsonEncode(payload),
    );
  }
}
