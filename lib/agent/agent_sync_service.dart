import '../services/sync_service.dart';

final class AgentSyncRequestException implements Exception {
  const AgentSyncRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentSyncExecutionException implements Exception {
  const AgentSyncExecutionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentSyncService {
  AgentSyncService({
    Future<void> Function()? refreshSession,
    Future<void> Function()? syncRunner,
    SyncStatus Function()? statusProvider,
    DateTime? Function()? lastSyncProvider,
    DateTime Function()? clock,
  }) : _refreshSession =
           refreshSession ??
           (() => SyncService.instance.refreshLicenseSession()),
       _syncRunner = syncRunner ?? (() => SyncService.instance.sync()),
       _statusProvider = statusProvider ?? (() => SyncService.instance.status),
       _lastSyncProvider =
           lastSyncProvider ?? (() => SyncService.instance.lastSyncTimestamp),
       _clock = clock ?? DateTime.now;

  static final AgentSyncService instance = AgentSyncService();

  final Future<void> Function() _refreshSession;
  final Future<void> Function() _syncRunner;
  final SyncStatus Function() _statusProvider;
  final DateTime? Function() _lastSyncProvider;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> forceSync(Map<String, dynamic> params) async {
    _validateParameterKeys(params, const {'request_id'});

    await _refreshSession();
    await _syncRunner();

    final status = _statusProvider();
    if (status == SyncStatus.error || status == SyncStatus.offline) {
      throw AgentSyncExecutionException(
        'SYNC_NOT_COMPLETED',
        'La sincronizacion no pudo completarse: ${status.name}',
      );
    }

    return {
      'format': 'MERKAERP_AGENT_SYNC_1',
      'forced_at': _clock().toUtc().toIso8601String(),
      'status': status.name,
      'last_sync_at': _lastSyncProvider()?.toUtc().toIso8601String(),
      'remote_payload_applied': false,
      'idempotent_queue': true,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentSyncRequestException(
        'UNSUPPORTED_SYNC_PARAMETER',
        'Parametro de sincronizacion no permitido: ${unsupported.first}',
      );
    }
  }
}
