import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import '../../services/licencia_service.dart';
import '../data/merka_sync_http_push_client.dart';
import 'merka_sale_sync_outbox.dart';
import 'merka_sync_push_service.dart';

class MerkaSyncConfiguredPushResult {
  const MerkaSyncConfiguredPushResult._({
    required this.attempted,
    required this.pushResult,
    this.skipReason,
  });

  factory MerkaSyncConfiguredPushResult.skipped(String reason) {
    return MerkaSyncConfiguredPushResult._(
      attempted: false,
      pushResult: const MerkaSyncPushResult(
        pushed: 0,
        failed: 0,
        terminalErrors: 0,
      ),
      skipReason: reason,
    );
  }

  factory MerkaSyncConfiguredPushResult.attempted(
    MerkaSyncPushResult pushResult,
  ) {
    return MerkaSyncConfiguredPushResult._(
      attempted: true,
      pushResult: pushResult,
    );
  }

  final bool attempted;
  final String? skipReason;
  final MerkaSyncPushResult pushResult;
}

class MerkaSyncConfiguredPushRunner {
  MerkaSyncConfiguredPushRunner({
    Future<DatabaseExecutor> Function()? databaseProvider,
    Future<String?> Function()? authTokenProvider,
    MerkaSyncJsonPoster Function(String serverBaseUrl)? posterFactory,
    DateTime Function()? now,
  }) : _databaseProvider =
           databaseProvider ?? (() async => DatabaseHelper.instance.database),
       _authTokenProvider =
           authTokenProvider ??
           (() async {
             final license = await LicenciaService.instance.obtenerLicencia();
             return license?.offlineToken;
           }),
       _posterFactory =
           posterFactory ??
           ((serverBaseUrl) =>
               DioMerkaSyncJsonPoster(serverBaseUrl: serverBaseUrl)),
       _now = now;

  final Future<DatabaseExecutor> Function() _databaseProvider;
  final Future<String?> Function() _authTokenProvider;
  final MerkaSyncJsonPoster Function(String serverBaseUrl) _posterFactory;
  final DateTime Function()? _now;

  Future<MerkaSyncConfiguredPushResult> pushPending({int limit = 50}) async {
    final db = await _databaseProvider();
    await MerkaSyncLocalSchema.ensure(db);

    final endpoint = await _readConfig(db, 'merka_sync_server_endpoint');
    if (endpoint == null) {
      return MerkaSyncConfiguredPushResult.skipped(
        'No hay merka_sync_server_endpoint configurado.',
      );
    }

    final authToken = (await _authTokenProvider())?.trim();
    if (authToken == null || authToken.isEmpty) {
      return MerkaSyncConfiguredPushResult.skipped(
        'No hay token de licencia disponible para sincronizar.',
      );
    }

    final client = MerkaSyncHttpPushClient(
      poster: _posterFactory(endpoint),
      authTokenProvider: () async => authToken,
    );
    final pushResult = await MerkaSyncOutboxPushService(
      client: client,
      now: _now,
    ).pushPending(db: db, limit: limit);

    return MerkaSyncConfiguredPushResult.attempted(pushResult);
  }

  Future<String?> _readConfig(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.single['valor']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
