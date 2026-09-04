import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import '../../services/licencia_service.dart';
import '../data/merka_sync_http_pull_client.dart';
import 'merka_sale_sync_outbox.dart';
import 'merka_sync_pull_service.dart';
import 'merka_sync_tenant_resolver.dart';

class MerkaSyncConfiguredPullResult {
  const MerkaSyncConfiguredPullResult._({
    required this.attempted,
    required this.pullResult,
    this.skipReason,
  });

  factory MerkaSyncConfiguredPullResult.skipped(String reason) {
    return MerkaSyncConfiguredPullResult._(
      attempted: false,
      pullResult: const MerkaSyncPullResult(
        received: 0,
        duplicates: 0,
        cursor: '0',
        hasMore: false,
      ),
      skipReason: reason,
    );
  }

  factory MerkaSyncConfiguredPullResult.attempted(
    MerkaSyncPullResult pullResult,
  ) {
    return MerkaSyncConfiguredPullResult._(
      attempted: true,
      pullResult: pullResult,
    );
  }

  final bool attempted;
  final String? skipReason;
  final MerkaSyncPullResult pullResult;
}

class MerkaSyncConfiguredPullRunner {
  MerkaSyncConfiguredPullRunner({
    Future<DatabaseExecutor> Function()? databaseProvider,
    Future<LicenciaInfo?> Function()? licenseProvider,
    MerkaSyncJsonGetter Function(String serverBaseUrl)? getterFactory,
  }) : _databaseProvider =
           databaseProvider ?? (() async => DatabaseHelper.instance.database),
       _licenseProvider =
           licenseProvider ??
           (() => LicenciaService.instance.obtenerLicencia()),
       _getterFactory =
           getterFactory ??
           ((serverBaseUrl) =>
               DioMerkaSyncJsonGetter(serverBaseUrl: serverBaseUrl));

  final Future<DatabaseExecutor> Function() _databaseProvider;
  final Future<LicenciaInfo?> Function() _licenseProvider;
  final MerkaSyncJsonGetter Function(String serverBaseUrl) _getterFactory;

  Future<MerkaSyncConfiguredPullResult> pullPending({int limit = 100}) async {
    final db = await _databaseProvider();
    await MerkaSyncLocalSchema.ensure(db);

    final endpoint = await _readConfig(db, 'merka_sync_server_endpoint');
    if (endpoint == null) {
      return MerkaSyncConfiguredPullResult.skipped(
        'No hay merka_sync_server_endpoint configurado.',
      );
    }

    final license = await _licenseProvider();
    final authToken = license?.offlineToken?.trim();
    if (authToken == null || authToken.isEmpty) {
      return MerkaSyncConfiguredPullResult.skipped(
        'No hay token de licencia disponible para sincronizar.',
      );
    }

    final localDeviceId = license?.installationId?.trim().isNotEmpty == true
        ? license!.installationId!.trim()
        : await _readConfig(db, 'merka_sync_device_id');
    if (localDeviceId == null || localDeviceId.isEmpty) {
      return MerkaSyncConfiguredPullResult.skipped(
        'No hay installation/device id disponible para sincronizar.',
      );
    }

    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final tenantKind = resolveMerkaSyncTenantKind(license);
    final tenantId = resolveMerkaSyncTenantId(license, companyId);
    final client = MerkaSyncHttpPullClient(
      getter: _getterFactory(endpoint),
      authTokenProvider: () async => authToken,
    );
    final result = await MerkaSyncPullService(client: client).pullPending(
      db: db,
      tenantKind: tenantKind,
      tenantId: tenantId,
      localDeviceId: localDeviceId,
      limit: limit,
    );
    return MerkaSyncConfiguredPullResult.attempted(result);
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
