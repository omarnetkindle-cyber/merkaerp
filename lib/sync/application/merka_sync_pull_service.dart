import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'merka_sale_sync_outbox.dart';

class MerkaSyncRemoteEvent {
  const MerkaSyncRemoteEvent({
    required this.cursor,
    required this.remoteEventId,
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
    required this.clientEventId,
    required this.clientCreatedAt,
    required this.receivedAt,
  });

  final String cursor;
  final String remoteEventId;
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
  final String? clientEventId;
  final String? clientCreatedAt;
  final String? receivedAt;

  factory MerkaSyncRemoteEvent.fromJson(Map<String, Object?> json) {
    final payload = _mapValue(json['payload']);
    final event = MerkaSyncRemoteEvent(
      cursor: _requiredString(json, 'cursor'),
      remoteEventId: _requiredString(json, 'remote_event_id'),
      tenantKind: _requiredString(json, 'tenant_kind'),
      tenantId: _requiredString(json, 'tenant_id'),
      companyId: _intValue(json['company_id']) ?? 0,
      branchId: _intValue(json['branch_id']) ?? 1,
      aggregateType: _requiredString(json, 'aggregate_type'),
      aggregateId: _requiredString(json, 'aggregate_id'),
      operation: _requiredString(json, 'operation'),
      eventName: _requiredString(json, 'event_name'),
      eventVersion: _intValue(json['event_version']) ?? 1,
      payload: payload,
      payloadChecksum: _requiredString(json, 'payload_checksum'),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      sourceDeviceId: _requiredString(json, 'source_device_id'),
      sourceUserId: _stringValue(json['source_user_id']),
      clientEventId: _stringValue(json['client_event_id']),
      clientCreatedAt: _stringValue(json['client_created_at']),
      receivedAt: _stringValue(json['received_at']),
    );
    event.validateChecksum();
    return event;
  }

  void validateChecksum() {
    final computed = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    if (computed != payloadChecksum) {
      throw FormatException(
        'payload_checksum inválido para evento remoto $remoteEventId.',
      );
    }
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = _stringValue(json[key]);
    if (value == null) throw FormatException('$key requerido.');
    return value;
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static Map<String, Object?> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('payload debe ser objeto JSON.');
  }
}

class MerkaSyncPullPage {
  const MerkaSyncPullPage({
    required this.events,
    required this.cursor,
    required this.hasMore,
  });

  final List<MerkaSyncRemoteEvent> events;
  final String cursor;
  final bool hasMore;
}

abstract class MerkaSyncPullClient {
  Future<MerkaSyncPullPage> pull({required String cursor, required int limit});
}

class MerkaSyncPullResult {
  const MerkaSyncPullResult({
    required this.received,
    required this.duplicates,
    required this.cursor,
    required this.hasMore,
  });

  final int received;
  final int duplicates;
  final String cursor;
  final bool hasMore;

  Map<String, Object?> toMap() => {
    'received': received,
    'duplicates': duplicates,
    'cursor': cursor,
    'has_more': hasMore,
  };
}

class MerkaSyncPullService {
  MerkaSyncPullService({required MerkaSyncPullClient client})
    : _client = client;

  final MerkaSyncPullClient _client;

  Future<MerkaSyncPullResult> pullPending({
    required DatabaseExecutor db,
    required String tenantKind,
    required String tenantId,
    required String localDeviceId,
    int limit = 100,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);

    final checkpoint = await _readCheckpoint(
      db,
      tenantKind: tenantKind,
      tenantId: tenantId,
      localDeviceId: localDeviceId,
    );
    final page = await _client.pull(cursor: checkpoint, limit: limit);

    var received = 0;
    var duplicates = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final event in page.events) {
      final exists = await db.query(
        'merka_sync_inbox',
        columns: ['id'],
        where: 'remote_event_id = ? OR idempotency_key = ?',
        whereArgs: [event.remoteEventId, event.idempotencyKey],
        limit: 1,
      );
      if (exists.isNotEmpty) {
        duplicates++;
        continue;
      }
      await db.insert('merka_sync_inbox', {
        'remote_event_id': event.remoteEventId,
        'tenant_kind': event.tenantKind,
        'tenant_id': event.tenantId,
        'company_id': event.companyId,
        'branch_id': event.branchId,
        'aggregate_type': event.aggregateType,
        'aggregate_id': event.aggregateId,
        'event_name': event.eventName,
        'payload_json': jsonEncode(event.payload),
        'payload_checksum': event.payloadChecksum,
        'idempotency_key': event.idempotencyKey,
        'source_device_id': event.sourceDeviceId,
        'status': 'pending',
        'received_at': event.receivedAt ?? now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      received++;
    }

    await _writeCheckpoint(
      db,
      tenantKind: tenantKind,
      tenantId: tenantId,
      localDeviceId: localDeviceId,
      cursor: page.cursor,
    );

    return MerkaSyncPullResult(
      received: received,
      duplicates: duplicates,
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  Future<String> _readCheckpoint(
    DatabaseExecutor db, {
    required String tenantKind,
    required String tenantId,
    required String localDeviceId,
  }) async {
    final rows = await db.query(
      'merka_sync_checkpoints',
      columns: ['cursor'],
      where: '''
        tenant_kind = ?
        AND tenant_id = ?
        AND source_device_id = ?
        AND direction = ?
      ''',
      whereArgs: [tenantKind, tenantId, localDeviceId, 'pull'],
      limit: 1,
    );
    if (rows.isEmpty) return '0';
    return rows.single['cursor']?.toString() ?? '0';
  }

  Future<void> _writeCheckpoint(
    DatabaseExecutor db, {
    required String tenantKind,
    required String tenantId,
    required String localDeviceId,
    required String cursor,
  }) async {
    await db.insert('merka_sync_checkpoints', {
      'tenant_kind': tenantKind,
      'tenant_id': tenantId,
      'source_device_id': localDeviceId,
      'direction': 'pull',
      'cursor': cursor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
