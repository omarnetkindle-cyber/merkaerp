import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'merka_sale_sync_outbox.dart';

class MerkaSyncOutboundEvent {
  const MerkaSyncOutboundEvent({
    required this.localId,
    required this.eventId,
    required this.tenantKind,
    required this.tenantId,
    required this.companyId,
    required this.branchId,
    required this.aggregateType,
    required this.aggregateId,
    required this.operation,
    required this.eventName,
    required this.eventVersion,
    required this.payload,
    required this.payloadChecksum,
    required this.idempotencyKey,
    required this.sourceDeviceId,
    required this.sourceUserId,
    required this.status,
    required this.attempts,
    required this.createdAt,
  });

  final int localId;
  final String eventId;
  final String tenantKind;
  final String tenantId;
  final int companyId;
  final int branchId;
  final String aggregateType;
  final String aggregateId;
  final String operation;
  final String eventName;
  final int eventVersion;
  final Map<String, Object?> payload;
  final String payloadChecksum;
  final String idempotencyKey;
  final String sourceDeviceId;
  final String? sourceUserId;
  final String status;
  final int attempts;
  final String createdAt;

  factory MerkaSyncOutboundEvent.fromRow(Map<String, Object?> row) {
    return MerkaSyncOutboundEvent(
      localId: (row['id'] as num).toInt(),
      eventId: row['event_id'].toString(),
      tenantKind: row['tenant_kind'].toString(),
      tenantId: row['tenant_id'].toString(),
      companyId: (row['company_id'] as num).toInt(),
      branchId: (row['branch_id'] as num?)?.toInt() ?? 1,
      aggregateType: row['aggregate_type'].toString(),
      aggregateId: row['aggregate_id'].toString(),
      operation: row['operation'].toString(),
      eventName: row['event_name'].toString(),
      eventVersion: (row['event_version'] as num?)?.toInt() ?? 1,
      payload: _decodePayload(row['payload_json']),
      payloadChecksum: row['payload_checksum'].toString(),
      idempotencyKey: row['idempotency_key'].toString(),
      sourceDeviceId: row['source_device_id'].toString(),
      sourceUserId: row['source_user_id']?.toString(),
      status: row['status'].toString(),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      createdAt: row['created_at'].toString(),
    );
  }

  Map<String, Object?> toTransportJson() => {
    'event_id': eventId,
    'tenant_kind': tenantKind,
    'tenant_id': tenantId,
    'company_id': companyId,
    'branch_id': branchId,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'operation': operation,
    'event_name': eventName,
    'event_version': eventVersion,
    'payload': payload,
    'payload_checksum': payloadChecksum,
    'idempotency_key': idempotencyKey,
    'source_device_id': sourceDeviceId,
    'source_user_id': sourceUserId,
    'created_at': createdAt,
  };

  static Map<String, Object?> _decodePayload(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return {};
    final decoded = jsonDecode(value.toString());
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('El payload del outbox no es un objeto JSON.');
  }
}

class MerkaSyncPushAck {
  const MerkaSyncPushAck({
    required this.accepted,
    this.remoteEventId,
    this.remoteCursor,
    this.duplicate = false,
  });

  final bool accepted;
  final String? remoteEventId;
  final String? remoteCursor;
  final bool duplicate;
}

abstract class MerkaSyncPushClient {
  Future<MerkaSyncPushAck> push(MerkaSyncOutboundEvent event);
}

class MerkaSyncPushResult {
  const MerkaSyncPushResult({
    required this.pushed,
    required this.failed,
    required this.terminalErrors,
  });

  final int pushed;
  final int failed;
  final int terminalErrors;

  int get processed => pushed + failed + terminalErrors;

  Map<String, Object?> toMap() => {
    'pushed': pushed,
    'failed': failed,
    'terminal_errors': terminalErrors,
    'processed': processed,
  };
}

class MerkaSyncOutboxPushService {
  MerkaSyncOutboxPushService({
    required MerkaSyncPushClient client,
    DateTime Function()? now,
    this.maxAttempts = 5,
  }) : _client = client,
       _now = now ?? (() => DateTime.now().toUtc());

  final MerkaSyncPushClient _client;
  final DateTime Function() _now;
  final int maxAttempts;

  Future<MerkaSyncPushResult> pushPending({
    required DatabaseExecutor db,
    int limit = 50,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);

    final current = _now().toUtc();
    final rows = await db.query(
      'merka_sync_outbox',
      where: '''
        status IN (?, ?)
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ''',
      whereArgs: ['pending', 'retry', current.toIso8601String()],
      orderBy: 'id ASC',
      limit: limit,
    );

    var pushed = 0;
    var failed = 0;
    var terminalErrors = 0;

    for (final row in rows) {
      final event = MerkaSyncOutboundEvent.fromRow(row);
      try {
        final ack = await _client.push(event);
        if (!ack.accepted) {
          throw StateError('El servidor rechazó el evento ${event.eventId}.');
        }
        await _markPushed(db, event, ack);
        pushed++;
      } catch (error) {
        final terminal = await _markFailed(db, event, error);
        if (terminal) {
          terminalErrors++;
        } else {
          failed++;
        }
      }
    }

    return MerkaSyncPushResult(
      pushed: pushed,
      failed: failed,
      terminalErrors: terminalErrors,
    );
  }

  Future<void> _markPushed(
    DatabaseExecutor db,
    MerkaSyncOutboundEvent event,
    MerkaSyncPushAck ack,
  ) async {
    final pushedAt = _now().toUtc().toIso8601String();
    await db.update(
      'merka_sync_outbox',
      {
        'status': 'pushed',
        'updated_at': pushedAt,
        'pushed_at': pushedAt,
        'last_error': null,
        'remote_cursor': ack.remoteCursor ?? ack.remoteEventId,
      },
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: [event.localId, 'pending', 'retry'],
    );
  }

  Future<bool> _markFailed(
    DatabaseExecutor db,
    MerkaSyncOutboundEvent event,
    Object error,
  ) async {
    final failedAt = _now().toUtc();
    final nextAttempts = event.attempts + 1;
    final isTerminal = nextAttempts >= maxAttempts;
    await db.update(
      'merka_sync_outbox',
      {
        'status': isTerminal ? 'error' : 'retry',
        'attempts': nextAttempts,
        'updated_at': failedAt.toIso8601String(),
        'next_attempt_at': isTerminal
            ? null
            : failedAt.add(_retryDelay(nextAttempts)).toIso8601String(),
        'last_error': error.toString(),
      },
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: [event.localId, 'pending', 'retry'],
    );
    return isTerminal;
  }

  Duration _retryDelay(int attempts) {
    final boundedAttempts = attempts.clamp(1, 6);
    return Duration(seconds: 5 * boundedAttempts * boundedAttempts);
  }
}
