/// Legacy compatibility facade.
///
/// Older builds attempted to synchronize operational ERP rows through
/// `/api/v1/data/pull` and `/api/v1/data/push`. Those endpoints are not part of
/// the authenticated Control Center protocol and direct row replication cannot
/// preserve sales/inventory/accounting invariants. The facade is deliberately
/// fail-closed so an old caller cannot silently reactivate that transport.
@Deprecated('Use SyncService; direct PostgreSQL/REST row replication is retired.')
class PostgresService {
  static final PostgresService _instance = PostgresService._internal();
  factory PostgresService() => _instance;
  PostgresService._internal();

  Never _retired() => throw UnsupportedError(
        'PostgresService legacy fue retirado. Use SyncService autenticado y tenant-aware.',
      );

  Future<void> get connection async => _retired();

  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
  }) async =>
      _retired();

  Future<void> execute(String sql, {Map<String, dynamic>? params}) async =>
      _retired();

  Future<int> insert(String table, Map<String, dynamic> data) async =>
      _retired();

  Future<void> update(
    String table,
    Map<String, dynamic> data,
    String where,
    List<dynamic> whereArgs,
  ) async =>
      _retired();

  Future<void> delete(
    String table,
    String where,
    List<dynamic> whereArgs,
  ) async =>
      _retired();
}
