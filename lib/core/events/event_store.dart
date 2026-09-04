import 'dart:convert';

import '../branch/branch_context.dart';
import '../database/database_gateway.dart';
import 'domain_event.dart';

class EventEnvelope {
  EventEnvelope({
    required this.eventId,
    required this.name,
    required this.aggregateType,
    required this.aggregateId,
    required this.payload,
    required this.occurredAt,
    required this.companyId,
    required this.branchId,
    required this.idempotencyKey,
    this.sequence,
    this.version = 1,
    this.correlationId,
    this.causationId,
    this.traceId,
    this.metadata = const {},
  });

  final int? sequence;
  final String eventId;
  final String name;
  final String aggregateType;
  final String aggregateId;
  final int version;
  final Map<String, Object?> payload;
  final DateTime occurredAt;
  final int companyId;
  final int branchId;
  final String idempotencyKey;
  final String? correlationId;
  final String? causationId;
  final String? traceId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toMap() => {
    'sequence': sequence,
    'event_id': eventId,
    'name': name,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'version': version,
    'payload': payload,
    'occurred_at': occurredAt.toIso8601String(),
    'company_id': companyId,
    'branch_id': branchId,
    'idempotency_key': idempotencyKey,
    'correlation_id': correlationId,
    'causation_id': causationId,
    'trace_id': traceId,
    'metadata': metadata,
  };

  EventEnvelope withSequence(int sequence) {
    return EventEnvelope(
      sequence: sequence,
      eventId: eventId,
      name: name,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      version: version,
      payload: payload,
      occurredAt: occurredAt,
      companyId: companyId,
      branchId: branchId,
      idempotencyKey: idempotencyKey,
      correlationId: correlationId,
      causationId: causationId,
      traceId: traceId,
      metadata: metadata,
    );
  }

  factory EventEnvelope.fromEvent(
    DomainEvent event, {
    required BranchScope scope,
    String? aggregateType,
    String? aggregateId,
    String? correlationId,
    String? causationId,
    String? traceId,
    String? idempotencyKey,
  }) {
    final resolvedAggregateType =
        aggregateType ??
        event.payload['aggregate_type']?.toString() ??
        event.name;
    final resolvedAggregateId =
        aggregateId ??
        event.payload['aggregate_id']?.toString() ??
        event.payload['sale_id']?.toString() ??
        event.payload['purchase_id']?.toString() ??
        event.payload['invoice_id']?.toString() ??
        event.payload['document_id']?.toString() ??
        _newId();
    final eventId = _newId();
    return EventEnvelope(
      eventId: eventId,
      name: event.name,
      aggregateType: resolvedAggregateType,
      aggregateId: resolvedAggregateId,
      version: (event.payload['event_version'] as num?)?.toInt() ?? 1,
      payload: event.payload,
      occurredAt: event.occurredAt,
      companyId:
          (event.payload['company_id'] as num?)?.toInt() ?? scope.companyId,
      branchId: (event.payload['branch_id'] as num?)?.toInt() ?? scope.branchId,
      idempotencyKey:
          idempotencyKey ??
          event.payload['idempotency_key']?.toString() ??
          event.payload['request_id']?.toString() ??
          eventId,
      correlationId:
          correlationId ?? event.payload['correlation_id']?.toString(),
      causationId: causationId ?? event.payload['causation_id']?.toString(),
      traceId: traceId ?? event.payload['trace_id']?.toString(),
    );
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

abstract class EventStore {
  Future<EventEnvelope> append(EventEnvelope event);

  Future<List<EventEnvelope>> load({int afterSequence = 0, int limit = 200});

  Future<List<EventEnvelope>> loadAggregate(
    String aggregateType,
    String aggregateId,
  );
}

class SqliteEventStore implements EventStore {
  SqliteEventStore({DatabaseGateway gateway = const SqliteDatabaseGateway()})
    : _gateway = gateway;

  final DatabaseGateway _gateway;

  @override
  Future<EventEnvelope> append(EventEnvelope event) async {
    return _gateway.transaction((txn) async {
      final existing = await txn.query(
        'event_store',
        where: 'idempotency_key = ?',
        whereArgs: [event.idempotencyKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return _fromRow(existing.first);
      }

      final sequence = await txn.insert('event_store', _toRow(event));
      await txn.insert('event_dispatch_queue', {
        'event_sequence': sequence,
        'status': 'pending',
        'attempts': 0,
        'available_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      return event.withSequence(sequence);
    });
  }

  @override
  Future<List<EventEnvelope>> load({
    int afterSequence = 0,
    int limit = 200,
  }) async {
    final rows = await _gateway.query(
      'event_store',
      where: 'id > ?',
      whereArgs: [afterSequence],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<EventEnvelope>> loadAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    final rows = await _gateway.query(
      'event_store',
      where: 'aggregate_type = ? AND aggregate_id = ?',
      whereArgs: [aggregateType, aggregateId],
      orderBy: 'id ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Map<String, Object?> _toRow(EventEnvelope event) => {
    'event_id': event.eventId,
    'name': event.name,
    'aggregate_type': event.aggregateType,
    'aggregate_id': event.aggregateId,
    'version': event.version,
    'payload_json': jsonEncode(event.payload),
    'metadata_json': jsonEncode(event.metadata),
    'company_id': event.companyId,
    'branch_id': event.branchId,
    'idempotency_key': event.idempotencyKey,
    'correlation_id': event.correlationId,
    'causation_id': event.causationId,
    'trace_id': event.traceId,
    'occurred_at': event.occurredAt.toIso8601String(),
    'created_at': DateTime.now().toIso8601String(),
  };

  EventEnvelope _fromRow(Map<String, Object?> row) {
    return EventEnvelope(
      sequence: (row['id'] as num?)?.toInt(),
      eventId: row['event_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      aggregateType: row['aggregate_type']?.toString() ?? '',
      aggregateId: row['aggregate_id']?.toString() ?? '',
      version: (row['version'] as num?)?.toInt() ?? 1,
      payload: _decode(row['payload_json']),
      metadata: _decode(row['metadata_json']),
      occurredAt:
          DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      companyId: (row['company_id'] as num?)?.toInt() ?? 0,
      branchId: (row['branch_id'] as num?)?.toInt() ?? 0,
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      correlationId: row['correlation_id']?.toString(),
      causationId: row['causation_id']?.toString(),
      traceId: row['trace_id']?.toString(),
    );
  }

  Map<String, Object?> _decode(Object? value) {
    if (value == null || value.toString().isEmpty) return {};
    final decoded = jsonDecode(value.toString());
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }
}
