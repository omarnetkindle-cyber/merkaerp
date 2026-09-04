import 'dart:convert';

import '../branch/branch_context.dart';
import '../database/database_gateway.dart';
import 'domain_event.dart';
import 'event_store.dart';

class EventDispatchResult {
  const EventDispatchResult({
    required this.dispatched,
    required this.failed,
    required this.deadLettered,
  });

  final int dispatched;
  final int failed;
  final int deadLettered;

  Map<String, Object?> toMap() => {
    'dispatched': dispatched,
    'failed': failed,
    'dead_lettered': deadLettered,
  };
}

abstract class EventProjection {
  String get name;

  Future<void> apply(EventEnvelope event);
}

class EventDispatcher {
  EventDispatcher({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    required List<EventProjection> projections,
    this.maxAttempts = 5,
  }) : _gateway = gateway,
       _projections = projections;

  final DatabaseGateway _gateway;
  final List<EventProjection> _projections;
  final int maxAttempts;

  Future<EventDispatchResult> dispatchPending({int limit = 100}) async {
    final rows = await _gateway.rawQuery(
      '''
      SELECT
        q.id AS queue_id,
        q.attempts AS queue_attempts,
        e.id AS event_sequence,
        e.*
      FROM event_dispatch_queue q
      INNER JOIN event_store e ON e.id = q.event_sequence
      WHERE q.status IN ('pending', 'retry')
        AND q.available_at <= ?
      ORDER BY q.id ASC
      LIMIT ?
      ''',
      [DateTime.now().toIso8601String(), limit],
    );

    var dispatched = 0;
    var failed = 0;
    var deadLettered = 0;

    for (final row in rows) {
      final queueId = (row['queue_id'] as num?)?.toInt() ?? 0;
      final attempts = (row['queue_attempts'] as num?)?.toInt() ?? 0;
      final event = _eventFromJoinedRow(row);
      try {
        for (final projection in _projections) {
          await projection.apply(event);
        }
        await _gateway.update(
          'event_dispatch_queue',
          {
            'status': 'dispatched',
            'dispatched_at': DateTime.now().toIso8601String(),
            'last_error': null,
          },
          where: 'id = ?',
          whereArgs: [queueId],
        );
        dispatched++;
      } catch (error) {
        final nextAttempts = attempts + 1;
        if (nextAttempts >= maxAttempts) {
          await _gateway.insert('event_dead_letters', {
            'event_sequence': event.sequence,
            'error': error.toString(),
            'failed_at': DateTime.now().toIso8601String(),
            'payload_json': jsonEncode(event.toMap()),
          });
          await _gateway.update(
            'event_dispatch_queue',
            {
              'status': 'dead_letter',
              'attempts': nextAttempts,
              'last_error': error.toString(),
            },
            where: 'id = ?',
            whereArgs: [queueId],
          );
          deadLettered++;
        } else {
          await _gateway.update(
            'event_dispatch_queue',
            {
              'status': 'retry',
              'attempts': nextAttempts,
              'available_at': DateTime.now()
                  .add(Duration(seconds: 5 * nextAttempts))
                  .toIso8601String(),
              'last_error': error.toString(),
            },
            where: 'id = ?',
            whereArgs: [queueId],
          );
          failed++;
        }
      }
    }

    return EventDispatchResult(
      dispatched: dispatched,
      failed: failed,
      deadLettered: deadLettered,
    );
  }

  EventEnvelope _eventFromJoinedRow(Map<String, Object?> row) {
    return EventEnvelope(
      sequence: (row['event_sequence'] as num?)?.toInt(),
      eventId: row['event_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      aggregateType: row['aggregate_type']?.toString() ?? '',
      aggregateId: row['aggregate_id']?.toString() ?? '',
      version: (row['version'] as num?)?.toInt() ?? 1,
      payload: _decode(row['payload_json']),
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

class PersistentEventBus implements DomainEventPublisher {
  PersistentEventBus({
    required EventStore eventStore,
    required BranchScopeProvider scopeProvider,
  }) : _eventStore = eventStore,
       _scopeProvider = scopeProvider;

  final EventStore _eventStore;
  final BranchScopeProvider _scopeProvider;

  @override
  Future<void> publish(DomainEvent event) async {
    final scope = await _scopeProvider.current();
    await _eventStore.append(EventEnvelope.fromEvent(event, scope: scope));
  }
}
