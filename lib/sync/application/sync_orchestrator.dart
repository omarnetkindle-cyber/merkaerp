import '../domain/sync_models.dart';
import 'conflict_resolver.dart';

abstract class SyncEventRepository {
  Future<void> enqueueOutbox(SyncEnvelope event);

  Future<List<SyncEnvelope>> pendingOutbox({int limit = 100});

  Future<bool> hasInboxEvent(String idempotencyKey);

  Future<SyncEnvelope?> findLocalAggregate(
    String aggregateType,
    String aggregateId,
  );

  Future<void> storeInbox(SyncEnvelope event);

  Future<void> markOutboxPushed(String eventId);

  Future<void> recordConflict(SyncConflict conflict);

  Future<SyncStatusSnapshot> status();
}

class SyncPushResult {
  const SyncPushResult({required this.sent, required this.failed});

  final int sent;
  final int failed;

  Map<String, Object?> toMap() => {'sent': sent, 'failed': failed};
}

class SyncPullResult {
  const SyncPullResult({
    required this.applied,
    required this.ignored,
    required this.conflicts,
  });

  final int applied;
  final int ignored;
  final int conflicts;

  Map<String, Object?> toMap() => {
    'applied': applied,
    'ignored': ignored,
    'conflicts': conflicts,
  };
}

class SyncOrchestrator {
  SyncOrchestrator({
    required SyncEventRepository repository,
    SyncConflictResolver resolver = const SyncConflictResolver(),
  }) : _repository = repository,
       _resolver = resolver;

  final SyncEventRepository _repository;
  final SyncConflictResolver _resolver;

  Future<void> enqueue(SyncEnvelope event) async {
    await _repository.enqueueOutbox(event);
  }

  Future<SyncPushResult> push({
    Future<bool> Function(SyncEnvelope event)? transport,
    int limit = 100,
  }) async {
    final events = await _repository.pendingOutbox(limit: limit);
    var sent = 0;
    var failed = 0;
    for (final event in events) {
      final ok = await (transport?.call(event) ?? Future.value(true));
      if (ok) {
        await _repository.markOutboxPushed(event.id);
        sent++;
      } else {
        failed++;
      }
    }
    return SyncPushResult(sent: sent, failed: failed);
  }

  Future<SyncPullResult> pull(List<SyncEnvelope> remoteEvents) async {
    var applied = 0;
    var ignored = 0;
    var conflicts = 0;

    for (final remote in remoteEvents) {
      if (await _repository.hasInboxEvent(remote.idempotencyKey)) {
        ignored++;
        continue;
      }
      final local = await _repository.findLocalAggregate(
        remote.aggregateType,
        remote.aggregateId,
      );
      if (local != null &&
          local.vectorClock.concurrentWith(remote.vectorClock)) {
        final resolution = _resolver.resolve(local, remote);
        if (resolution.requiresManualReview) {
          await _repository.recordConflict(
            SyncConflict(
              id: '${remote.aggregateType}:${remote.aggregateId}',
              local: local,
              remote: remote,
              detectedAt: DateTime.now(),
            ),
          );
          conflicts++;
          continue;
        }
      }
      await _repository.storeInbox(
        remote.copyWith(status: SyncEventStatus.applied),
      );
      applied++;
    }

    return SyncPullResult(
      applied: applied,
      ignored: ignored,
      conflicts: conflicts,
    );
  }

  Future<SyncStatusSnapshot> status() => _repository.status();
}
