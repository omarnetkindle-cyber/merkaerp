import 'package:sqflite/sqflite.dart';

import '../events/domain_event.dart';
import '../database/database_gateway.dart';

class BusinessTransactionContext {
  BusinessTransactionContext({
    required this.id,
    required this.name,
    required this.startedAt,
    this.correlationId,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final String? correlationId;
  final Map<String, Object?> metadata;
  final List<DomainEvent> _events = [];

  List<DomainEvent> get events => List.unmodifiable(_events);

  void addEvent(DomainEvent event) {
    _events.add(event);
  }
}

abstract class BusinessTransactionManager {
  Future<T> run<T>(
    String name,
    Future<T> Function(Transaction txn, BusinessTransactionContext context)
    action, {
    String? correlationId,
    Map<String, Object?> metadata,
  });
}

class SqliteBusinessTransactionManager implements BusinessTransactionManager {
  SqliteBusinessTransactionManager({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    DomainEventPublisher events = const NoopDomainEventPublisher(),
  }) : _gateway = gateway,
       _events = events;

  final DatabaseGateway _gateway;
  final DomainEventPublisher _events;

  @override
  Future<T> run<T>(
    String name,
    Future<T> Function(Transaction txn, BusinessTransactionContext context)
    action, {
    String? correlationId,
    Map<String, Object?> metadata = const {},
  }) async {
    final context = BusinessTransactionContext(
      id: _newId(),
      name: name,
      startedAt: DateTime.now(),
      correlationId: correlationId,
      metadata: metadata,
    );
    final result = await _gateway.transaction((txn) => action(txn, context));
    for (final event in context.events) {
      await _events.publish(event);
    }
    return result;
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
