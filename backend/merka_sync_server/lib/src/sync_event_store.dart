import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import 'sync_event.dart';

class StoredSyncEvent {
  const StoredSyncEvent({
    required this.remoteEventId,
    required this.cursor,
    required this.duplicate,
  });

  final String remoteEventId;
  final String cursor;
  final bool duplicate;
}

class RemoteSyncEvent {
  const RemoteSyncEvent({
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
  final int? companyId;
  final int? branchId;
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
  final String clientEventId;
  final DateTime? clientCreatedAt;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => {
        'cursor': cursor,
        'remote_event_id': remoteEventId,
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
        'client_event_id': clientEventId,
        'client_created_at': clientCreatedAt?.toUtc().toIso8601String(),
        'received_at': receivedAt.toUtc().toIso8601String(),
      };
}

abstract class SyncEventStore {
  Future<void> ensureSchema();

  Future<StoredSyncEvent> append(SyncEvent event);

  Future<List<RemoteSyncEvent>> listEvents({
    required String tenantKind,
    required String tenantId,
    required int afterCursor,
    required int limit,
    String? excludeSourceDeviceId,
  });
}

class InMemorySyncEventStore implements SyncEventStore {
  final Map<String, StoredSyncEvent> _byIdempotency = {};
  final List<RemoteSyncEvent> _events = [];
  var _sequence = 0;

  @override
  Future<void> ensureSchema() async {}

  @override
  Future<StoredSyncEvent> append(SyncEvent event) async {
    final key = '${event.tenantKind}:${event.tenantId}:${event.idempotencyKey}';
    final existing = _byIdempotency[key];
    if (existing != null) {
      return StoredSyncEvent(
        remoteEventId: existing.remoteEventId,
        cursor: existing.cursor,
        duplicate: true,
      );
    }

    _sequence++;
    final stored = StoredSyncEvent(
      remoteEventId: const Uuid().v4(),
      cursor: _sequence.toString(),
      duplicate: false,
    );
    _byIdempotency[key] = stored;
    _events.add(
      RemoteSyncEvent(
        cursor: stored.cursor,
        remoteEventId: stored.remoteEventId,
        tenantKind: event.tenantKind,
        tenantId: event.tenantId,
        companyId: event.companyId,
        branchId: event.branchId,
        aggregateType: event.aggregateType,
        aggregateId: event.aggregateId,
        operation: event.operation,
        eventName: event.eventName,
        eventVersion: event.eventVersion,
        payload: event.payload,
        payloadChecksum: event.payloadChecksum,
        idempotencyKey: event.idempotencyKey,
        sourceDeviceId: event.sourceDeviceId,
        sourceUserId: event.sourceUserId,
        clientEventId: event.eventId,
        clientCreatedAt: event.createdAt,
        receivedAt: DateTime.now().toUtc(),
      ),
    );
    return stored;
  }

  @override
  Future<List<RemoteSyncEvent>> listEvents({
    required String tenantKind,
    required String tenantId,
    required int afterCursor,
    required int limit,
    String? excludeSourceDeviceId,
  }) async {
    return _events
        .where((event) => event.tenantKind == tenantKind)
        .where((event) => event.tenantId == tenantId)
        .where((event) => int.parse(event.cursor) > afterCursor)
        .where(
          (event) =>
              excludeSourceDeviceId == null ||
              event.sourceDeviceId != excludeSourceDeviceId,
        )
        .take(limit)
        .toList();
  }
}

class PostgresSyncEventStore implements SyncEventStore {
  PostgresSyncEventStore({required Connection connection})
      : _connection = connection;

  final Connection _connection;

  @override
  Future<void> ensureSchema() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS sync_events(
        id BIGSERIAL PRIMARY KEY,
        remote_event_id TEXT NOT NULL UNIQUE,
        tenant_kind TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        company_id INTEGER,
        branch_id INTEGER,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        event_name TEXT NOT NULL,
        event_version INTEGER NOT NULL DEFAULT 1,
        payload_json JSONB NOT NULL,
        payload_checksum TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        source_device_id TEXT NOT NULL,
        source_user_id TEXT,
        client_event_id TEXT NOT NULL,
        client_created_at TIMESTAMPTZ,
        received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE(tenant_kind, tenant_id, idempotency_key)
      )
    ''');
    await _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_events_tenant_cursor
      ON sync_events(tenant_kind, tenant_id, id)
    ''');
    await _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_events_aggregate
      ON sync_events(tenant_kind, tenant_id, aggregate_type, aggregate_id)
    ''');
  }

  @override
  Future<StoredSyncEvent> append(SyncEvent event) async {
    final remoteEventId = const Uuid().v4();
    final inserted = await _connection.execute(
      Sql.named('''
        INSERT INTO sync_events(
          remote_event_id,
          tenant_kind,
          tenant_id,
          company_id,
          branch_id,
          aggregate_type,
          aggregate_id,
          operation,
          event_name,
          event_version,
          payload_json,
          payload_checksum,
          idempotency_key,
          source_device_id,
          source_user_id,
          client_event_id,
          client_created_at
        )
        VALUES(
          @remote_event_id,
          @tenant_kind,
          @tenant_id,
          @company_id,
          @branch_id,
          @aggregate_type,
          @aggregate_id,
          @operation,
          @event_name,
          @event_version,
          CAST(@payload_json AS jsonb),
          @payload_checksum,
          @idempotency_key,
          @source_device_id,
          @source_user_id,
          @client_event_id,
          @client_created_at
        )
        ON CONFLICT(tenant_kind, tenant_id, idempotency_key) DO NOTHING
        RETURNING id, remote_event_id
      '''),
      parameters: {
        'remote_event_id': remoteEventId,
        'tenant_kind': event.tenantKind,
        'tenant_id': event.tenantId,
        'company_id': event.companyId,
        'branch_id': event.branchId,
        'aggregate_type': event.aggregateType,
        'aggregate_id': event.aggregateId,
        'operation': event.operation,
        'event_name': event.eventName,
        'event_version': event.eventVersion,
        'payload_json': jsonEncode(event.payload),
        'payload_checksum': event.payloadChecksum,
        'idempotency_key': event.idempotencyKey,
        'source_device_id': event.sourceDeviceId,
        'source_user_id': event.sourceUserId,
        'client_event_id': event.eventId,
        'client_created_at': event.createdAt,
      },
    );

    if (inserted.isNotEmpty) {
      final row = inserted.first.toColumnMap();
      final id = row['id'].toString();
      return StoredSyncEvent(
        remoteEventId: row['remote_event_id'].toString(),
        cursor: id,
        duplicate: false,
      );
    }

    final existing = await _connection.execute(
      Sql.named('''
        SELECT id, remote_event_id
        FROM sync_events
        WHERE tenant_kind = @tenant_kind
          AND tenant_id = @tenant_id
          AND idempotency_key = @idempotency_key
        LIMIT 1
      '''),
      parameters: {
        'tenant_kind': event.tenantKind,
        'tenant_id': event.tenantId,
        'idempotency_key': event.idempotencyKey,
      },
    );
    if (existing.isEmpty) {
      throw StateError('No se pudo recuperar evento idempotente existente.');
    }
    final row = existing.first.toColumnMap();
    return StoredSyncEvent(
      remoteEventId: row['remote_event_id'].toString(),
      cursor: row['id'].toString(),
      duplicate: true,
    );
  }

  @override
  Future<List<RemoteSyncEvent>> listEvents({
    required String tenantKind,
    required String tenantId,
    required int afterCursor,
    required int limit,
    String? excludeSourceDeviceId,
  }) async {
    final rows = await _connection.execute(
      Sql.named('''
        SELECT
          id,
          remote_event_id,
          tenant_kind,
          tenant_id,
          company_id,
          branch_id,
          aggregate_type,
          aggregate_id,
          operation,
          event_name,
          event_version,
          payload_json,
          payload_checksum,
          idempotency_key,
          source_device_id,
          source_user_id,
          client_event_id,
          client_created_at,
          received_at
        FROM sync_events
        WHERE tenant_kind = @tenant_kind
          AND tenant_id = @tenant_id
          AND id > @after_cursor
          AND (
            @exclude_source_device_id IS NULL
            OR source_device_id <> @exclude_source_device_id
          )
        ORDER BY id ASC
        LIMIT @limit
      '''),
      parameters: {
        'tenant_kind': tenantKind,
        'tenant_id': tenantId,
        'after_cursor': afterCursor,
        'exclude_source_device_id': excludeSourceDeviceId,
        'limit': limit,
      },
    );

    return rows.map((row) {
      final map = row.toColumnMap();
      return RemoteSyncEvent(
        cursor: map['id'].toString(),
        remoteEventId: map['remote_event_id'].toString(),
        tenantKind: map['tenant_kind'].toString(),
        tenantId: map['tenant_id'].toString(),
        companyId: _intValue(map['company_id']),
        branchId: _intValue(map['branch_id']),
        aggregateType: map['aggregate_type'].toString(),
        aggregateId: map['aggregate_id'].toString(),
        operation: map['operation'].toString(),
        eventName: map['event_name'].toString(),
        eventVersion: _intValue(map['event_version']) ?? 1,
        payload: _payloadMap(map['payload_json']),
        payloadChecksum: map['payload_checksum'].toString(),
        idempotencyKey: map['idempotency_key'].toString(),
        sourceDeviceId: map['source_device_id'].toString(),
        sourceUserId: map['source_user_id']?.toString(),
        clientEventId: map['client_event_id'].toString(),
        clientCreatedAt: _dateTimeValue(map['client_created_at']),
        receivedAt:
            _dateTimeValue(map['received_at']) ?? DateTime.now().toUtc(),
      );
    }).toList();
  }

  static Map<String, Object?> _payloadMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return {};
  }

  static int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
