enum SyncOperation { create, update, delete, upsert }

enum SyncEventStatus { pending, pushing, pushed, applied, conflict, failed }

enum ConflictResolutionStrategy { localWins, remoteWins, latestWins, manual }

class SyncVectorClock {
  const SyncVectorClock(this.values);

  final Map<String, int> values;

  int operator [](String nodeId) => values[nodeId] ?? 0;

  SyncVectorClock increment(String nodeId) {
    return SyncVectorClock({...values, nodeId: this[nodeId] + 1});
  }

  bool happensBefore(SyncVectorClock other) {
    var less = false;
    for (final node in {...values.keys, ...other.values.keys}) {
      final left = this[node];
      final right = other[node];
      if (left > right) return false;
      if (left < right) less = true;
    }
    return less;
  }

  bool concurrentWith(SyncVectorClock other) {
    return !happensBefore(other) && !other.happensBefore(this);
  }

  Map<String, Object?> toMap() => values;
}

class SyncEnvelope {
  const SyncEnvelope({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.aggregateType,
    required this.aggregateId,
    required this.operation,
    required this.payload,
    required this.occurredAt,
    required this.idempotencyKey,
    required this.vectorClock,
    this.tenantType = 'commercial',
    this.entidadId,
    this.usuarioId,
    this.status = SyncEventStatus.pending,
    this.version = 1,
    this.attempts = 0,
  });

  final String id;
  final int companyId;
  final int branchId;
  final String tenantType;
  final String? entidadId;
  final String? usuarioId;
  final String aggregateType;
  final String aggregateId;
  final SyncOperation operation;
  final Map<String, Object?> payload;
  final DateTime occurredAt;
  final String idempotencyKey;
  final SyncVectorClock vectorClock;
  final SyncEventStatus status;
  final int version;
  final int attempts;

  SyncEnvelope copyWith({
    SyncEventStatus? status,
    int? attempts,
    SyncVectorClock? vectorClock,
    String? tenantType,
    String? entidadId,
    String? usuarioId,
  }) {
    return SyncEnvelope(
      id: id,
      companyId: companyId,
      branchId: branchId,
      tenantType: tenantType ?? this.tenantType,
      entidadId: entidadId ?? this.entidadId,
      usuarioId: usuarioId ?? this.usuarioId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      operation: operation,
      payload: payload,
      occurredAt: occurredAt,
      idempotencyKey: idempotencyKey,
      vectorClock: vectorClock ?? this.vectorClock,
      status: status ?? this.status,
      version: version,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'company_id': companyId,
    'branch_id': branchId,
    'tenant_type': tenantType,
    'entidad_id': entidadId,
    'usuario_id': usuarioId,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'operation': operation.name,
    'payload': payload,
    'occurred_at': occurredAt.toIso8601String(),
    'idempotency_key': idempotencyKey,
    'vector_clock': vectorClock.toMap(),
    'status': status.name,
    'version': version,
    'attempts': attempts,
  };
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.local,
    required this.remote,
    required this.detectedAt,
    this.resolutionStrategy = ConflictResolutionStrategy.manual,
  });

  final String id;
  final SyncEnvelope local;
  final SyncEnvelope remote;
  final DateTime detectedAt;
  final ConflictResolutionStrategy resolutionStrategy;

  Map<String, Object?> toMap() => {
    'id': id,
    'local': local.toMap(),
    'remote': remote.toMap(),
    'detected_at': detectedAt.toIso8601String(),
    'resolution_strategy': resolutionStrategy.name,
  };
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingOutbox,
    required this.pendingInbox,
    required this.conflicts,
    required this.lastPushAt,
    required this.lastPullAt,
    required this.online,
  });

  final int pendingOutbox;
  final int pendingInbox;
  final int conflicts;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final bool online;

  bool get healthy => conflicts == 0;

  Map<String, Object?> toMap() => {
    'pending_outbox': pendingOutbox,
    'pending_inbox': pendingInbox,
    'conflicts': conflicts,
    'last_push_at': lastPushAt?.toIso8601String(),
    'last_pull_at': lastPullAt?.toIso8601String(),
    'online': online,
    'healthy': healthy,
  };

  factory SyncStatusSnapshot.offlineFirstReady() {
    return const SyncStatusSnapshot(
      pendingOutbox: 0,
      pendingInbox: 0,
      conflicts: 0,
      lastPushAt: null,
      lastPullAt: null,
      online: false,
    );
  }
}
