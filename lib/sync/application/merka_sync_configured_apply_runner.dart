import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import 'merka_sale_sync_outbox.dart';
import 'merka_sync_inbox_apply_service.dart';

class MerkaSyncConfiguredApplyRunner {
  MerkaSyncConfiguredApplyRunner({
    Future<Database> Function()? databaseProvider,
    DateTime Function()? now,
  }) : _databaseProvider =
           databaseProvider ?? (() async => DatabaseHelper.instance.database),
       _now = now;

  final Future<Database> Function() _databaseProvider;
  final DateTime Function()? _now;

  Future<MerkaSyncInboxApplyResult> applyPending({int limit = 50}) async {
    final db = await _databaseProvider();
    await MerkaSyncLocalSchema.ensure(db);
    return MerkaSyncInboxApplyService(
      now: _now,
    ).applyPending(db: db, limit: limit);
  }
}
