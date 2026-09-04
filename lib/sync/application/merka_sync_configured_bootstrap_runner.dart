import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import 'merka_sale_sync_outbox.dart';

class MerkaSyncConfiguredBootstrapResult {
  const MerkaSyncConfiguredBootstrapResult({required this.queued});

  final int queued;

  Map<String, Object?> toMap() => {'queued': queued};
}

class MerkaSyncConfiguredBootstrapRunner {
  MerkaSyncConfiguredBootstrapRunner({
    Future<DatabaseExecutor> Function()? databaseProvider,
    Future<int> Function(DatabaseExecutor db)? companyIdProvider,
    MerkaMasterDataSyncOutboxWriter writer =
        const MerkaMasterDataSyncOutboxWriter(),
  }) : _databaseProvider =
           databaseProvider ?? (() async => DatabaseHelper.instance.database),
       _companyIdProvider =
           companyIdProvider ??
           ((db) => DatabaseHelper.instance.obtenerEmpresaActivaId(db)),
       _writer = writer;

  final Future<DatabaseExecutor> Function() _databaseProvider;
  final Future<int> Function(DatabaseExecutor db) _companyIdProvider;
  final MerkaMasterDataSyncOutboxWriter _writer;

  Future<MerkaSyncConfiguredBootstrapResult> enqueueCurrentCatalog() async {
    final db = await _databaseProvider();
    final companyId = await _companyIdProvider(db);
    final queued = await _writer.enqueueExistingMasterData(
      db: db,
      companyId: companyId,
    );
    return MerkaSyncConfiguredBootstrapResult(queued: queued);
  }
}
