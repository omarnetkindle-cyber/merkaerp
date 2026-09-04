import 'dart:convert';

import '../../core/database/database_gateway.dart';
import '../application/sync_orchestrator.dart';
import '../domain/sync_models.dart';

class SqliteSyncRepository implements SyncEventRepository {
  const SqliteSyncRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
  }) : _gateway = gateway;

  final DatabaseGateway _gateway;

  @override
  Future<void> enqueueOutbox(SyncEnvelope event) async {
    await _gateway.insert('sync_outbox', {
      'company_id': event.companyId,
      'branch_id': event.branchId,
      'tenant_type': event.tenantType,
      'entidad_id': event.entidadId,
      'user_id': event.usuarioId,
      'aggregate_type': event.aggregateType,
      'aggregate_id': event.aggregateId,
      'event_type': event.operation.name,
      'payload_json': jsonEncode(event.payload),
      'idempotency_key': event.idempotencyKey,
      'vector_clock_json': jsonEncode(event.vectorClock.toMap()),
      'status': event.status.name,
      'attempts': event.attempts,
      'created_at': event.occurredAt.toIso8601String(),
    });
  }

  @override
  Future<SyncEnvelope?> findLocalAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    final rows = await _gateway.query(
      'sync_outbox',
      where: 'aggregate_type = ? AND aggregate_id = ?',
      whereArgs: [aggregateType, aggregateId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromOutbox(rows.first);
  }

  @override
  Future<bool> hasInboxEvent(String idempotencyKey) async {
    final rows = await _gateway.query(
      'sync_inbox',
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markOutboxPushed(String eventId) async {
    await _gateway.update(
      'sync_outbox',
      {
        'status': SyncEventStatus.pushed.name,
        'processed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [int.tryParse(eventId) ?? eventId],
    );
  }

  @override
  Future<List<SyncEnvelope>> pendingOutbox({int limit = 100}) async {
    final rows = await _gateway.query(
      'sync_outbox',
      where: "status IN ('pending', 'failed')",
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_fromOutbox).toList();
  }

  @override
  Future<void> recordConflict(SyncConflict conflict) async {
    await _gateway.insert('sync_conflicts', {
      'company_id': conflict.remote.companyId,
      'branch_id': conflict.remote.branchId,
      'tenant_type': conflict.remote.tenantType,
      'entidad_id': conflict.remote.entidadId,
      'user_id': conflict.remote.usuarioId,
      'aggregate_type': conflict.remote.aggregateType,
      'aggregate_id': conflict.remote.aggregateId,
      'local_payload_json': jsonEncode(conflict.local.toMap()),
      'remote_payload_json': jsonEncode(conflict.remote.toMap()),
      'resolution': conflict.resolutionStrategy.name,
      'status': 'open',
      'detected_at': conflict.detectedAt.toIso8601String(),
      'resolved_at': null,
    });
  }

  @override
  Future<SyncStatusSnapshot> status() async {
    final pendingOutbox = await _count(
      "SELECT COUNT(*) AS total FROM sync_outbox WHERE status IN ('pending', 'failed')",
    );
    final pendingInbox = await _count(
      "SELECT COUNT(*) AS total FROM sync_inbox WHERE status = 'pending'",
    );
    final conflicts = await _count(
      "SELECT COUNT(*) AS total FROM sync_conflicts WHERE status = 'open'",
    );
    return SyncStatusSnapshot(
      pendingOutbox: pendingOutbox,
      pendingInbox: pendingInbox,
      conflicts: conflicts,
      lastPushAt: null,
      lastPullAt: null,
      online: false,
    );
  }

  @override
  Future<void> storeInbox(SyncEnvelope event) async {
    await _gateway.insert('sync_inbox', {
      'company_id': event.companyId,
      'branch_id': event.branchId,
      'tenant_type': event.tenantType,
      'entidad_id': event.entidadId,
      'user_id': event.usuarioId,
      'aggregate_type': event.aggregateType,
      'aggregate_id': event.aggregateId,
      'event_type': event.operation.name,
      'payload_json': jsonEncode(event.payload),
      'idempotency_key': event.idempotencyKey,
      'vector_clock_json': jsonEncode(event.vectorClock.toMap()),
      'status': event.status.name,
      'received_at': DateTime.now().toIso8601String(),
      'applied_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> _count(String sql) async {
    final rows = await _gateway.rawQuery(sql);
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  SyncEnvelope _fromOutbox(Map<String, Object?> row) {
    final payloadText = row['payload_json']?.toString() ?? '{}';
    final clockText = row['vector_clock_json']?.toString() ?? '{}';
    final payload = jsonDecode(payloadText) as Map<String, dynamic>;
    final clock = (jsonDecode(clockText) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );
    return SyncEnvelope(
      id: row['id'].toString(),
      companyId: (row['company_id'] as num?)?.toInt() ?? 0,
      branchId: (row['branch_id'] as num?)?.toInt() ?? 0,
      tenantType: row['tenant_type']?.toString() ?? 'commercial',
      entidadId: row['entidad_id']?.toString(),
      usuarioId: row['user_id']?.toString() ?? row['usuario_id']?.toString(),
      aggregateType: row['aggregate_type']?.toString() ?? '',
      aggregateId: row['aggregate_id']?.toString() ?? '',
      operation: SyncOperation.values.firstWhere(
        (item) => item.name == row['event_type']?.toString(),
        orElse: () => SyncOperation.upsert,
      ),
      payload: payload,
      occurredAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      vectorClock: SyncVectorClock(clock),
      status: SyncEventStatus.values.firstWhere(
        (item) => item.name == row['status']?.toString(),
        orElse: () => SyncEventStatus.pending,
      ),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}
