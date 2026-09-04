import '../domain/sync_models.dart';

class ConflictResolution {
  const ConflictResolution({
    required this.strategy,
    required this.winner,
    required this.requiresManualReview,
  });

  final ConflictResolutionStrategy strategy;
  final SyncEnvelope? winner;
  final bool requiresManualReview;
}

class SyncConflictResolver {
  const SyncConflictResolver({
    this.defaultStrategy = ConflictResolutionStrategy.latestWins,
  });

  final ConflictResolutionStrategy defaultStrategy;

  ConflictResolution resolve(SyncEnvelope local, SyncEnvelope remote) {
    final concurrent = local.vectorClock.concurrentWith(remote.vectorClock);
    if (concurrent && defaultStrategy == ConflictResolutionStrategy.manual) {
      return const ConflictResolution(
        strategy: ConflictResolutionStrategy.manual,
        winner: null,
        requiresManualReview: true,
      );
    }

    switch (defaultStrategy) {
      case ConflictResolutionStrategy.localWins:
        return ConflictResolution(
          strategy: defaultStrategy,
          winner: local,
          requiresManualReview: false,
        );
      case ConflictResolutionStrategy.remoteWins:
        return ConflictResolution(
          strategy: defaultStrategy,
          winner: remote,
          requiresManualReview: false,
        );
      case ConflictResolutionStrategy.latestWins:
        return ConflictResolution(
          strategy: defaultStrategy,
          winner: local.occurredAt.isAfter(remote.occurredAt) ? local : remote,
          requiresManualReview: false,
        );
      case ConflictResolutionStrategy.manual:
        return const ConflictResolution(
          strategy: ConflictResolutionStrategy.manual,
          winner: null,
          requiresManualReview: true,
        );
    }
  }
}
