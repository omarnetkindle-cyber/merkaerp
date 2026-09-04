import 'package:sqflite/sqflite.dart';

import '../core/cache/cache_manager.dart';
import '../db_helper.dart';

final class AgentRepairRequestException implements Exception {
  const AgentRepairRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentRepairService {
  AgentRepairService({
    Future<Database> Function()? databaseProvider,
    Future<void> Function()? clearCache,
    Future<void> Function()? cleanExpiredCache,
    Map<String, dynamic> Function()? cacheStats,
    DateTime Function()? clock,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _clearCache = clearCache ?? (() => CacheManager.instance.clear()),
       _cleanExpiredCache =
           cleanExpiredCache ?? (() => CacheManager.instance.cleanExpired()),
       _cacheStats = cacheStats ?? (() => CacheManager.instance.getStats()),
       _clock = clock ?? DateTime.now;

  static final AgentRepairService instance = AgentRepairService();

  static const Set<String> supportedRepairs = {
    'reindex_database',
    'optimize_database',
    'clear_cache',
  };

  final Future<Database> Function() _databaseProvider;
  final Future<void> Function() _clearCache;
  final Future<void> Function() _cleanExpiredCache;
  final Map<String, dynamic> Function() _cacheStats;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> rebuildIndexes(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'request_id'});
    return _reindexAndOptimize('reconstruir_indices');
  }

  Future<Map<String, dynamic>> clearCaches(Map<String, dynamic> params) async {
    _validateParameterKeys(params, const {'request_id', 'scope'});
    final scope = params['scope']?.toString().trim() ?? 'all_regenerable';
    if (scope != 'all_regenerable' && scope != 'expired') {
      throw const AgentRepairRequestException(
        'UNSUPPORTED_CACHE_SCOPE',
        'scope debe ser expired o all_regenerable',
      );
    }

    final before = _safeCacheStats();
    if (scope == 'expired') {
      await _cleanExpiredCache();
    } else {
      await _clearCache();
    }
    final after = _safeCacheStats();

    return {
      'format': 'MERKAERP_AGENT_REPAIR_1',
      'repair_code': 'clear_cache',
      'scope': scope,
      'completed_at': _clock().toUtc().toIso8601String(),
      'cache_before': before,
      'cache_after': after,
      'business_rows_modified': false,
    };
  }

  Future<Map<String, dynamic>> runSafeRepair(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'code', 'repair_code', 'request_id'});
    final code = (params['repair_code'] ?? params['code'])?.toString().trim();
    if (code == null || code.isEmpty) {
      throw const AgentRepairRequestException(
        'SAFE_REPAIR_CODE_REQUIRED',
        'Se requiere repair_code registrado localmente',
      );
    }
    if (!supportedRepairs.contains(code)) {
      throw AgentRepairRequestException(
        'UNSUPPORTED_SAFE_REPAIR',
        'Reparacion segura no registrada: $code',
      );
    }

    return switch (code) {
      'reindex_database' => await _reindexAndOptimize(code),
      'optimize_database' => await _optimizeDatabase(code),
      'clear_cache' => await clearCaches(const {}),
      _ => throw StateError('Reparacion local no registrada'),
    };
  }

  Future<Map<String, dynamic>> _reindexAndOptimize(String code) async {
    final db = await _databaseProvider();
    await db.execute('REINDEX');
    await db.execute('ANALYZE');
    await db.execute('PRAGMA optimize');
    return {
      'format': 'MERKAERP_AGENT_REPAIR_1',
      'repair_code': code,
      'completed_at': _clock().toUtc().toIso8601String(),
      'steps': const ['REINDEX', 'ANALYZE', 'PRAGMA optimize'],
      'business_rows_modified': false,
    };
  }

  Future<Map<String, dynamic>> _optimizeDatabase(String code) async {
    final db = await _databaseProvider();
    await db.execute('ANALYZE');
    await db.execute('PRAGMA optimize');
    return {
      'format': 'MERKAERP_AGENT_REPAIR_1',
      'repair_code': code,
      'completed_at': _clock().toUtc().toIso8601String(),
      'steps': const ['ANALYZE', 'PRAGMA optimize'],
      'business_rows_modified': false,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentRepairRequestException(
        'UNSUPPORTED_REPAIR_PARAMETER',
        'Parametro de reparacion no permitido: ${unsupported.first}',
      );
    }
  }

  Map<String, dynamic> _safeCacheStats() {
    try {
      return _cacheStats();
    } catch (_) {
      return const {'available': false};
    }
  }
}
