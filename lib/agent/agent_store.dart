import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';

enum AgentCommandClaimState { claimed, cached, inFlight, replay }

final class StoredAgentCommand {
  const StoredAgentCommand({
    required this.commandId,
    required this.nonce,
    required this.action,
    required this.installationId,
    required this.status,
    required this.success,
    required this.message,
    required this.result,
  });

  final String commandId;
  final String nonce;
  final String action;
  final String installationId;
  final String status;
  final bool? success;
  final String message;
  final Map<String, dynamic> result;

  factory StoredAgentCommand.fromRow(Map<String, Object?> row) {
    Map<String, dynamic> result = const {};
    try {
      final decoded = jsonDecode(row['result_json']?.toString() ?? '{}');
      if (decoded is Map) result = decoded.cast<String, dynamic>();
    } catch (_) {}
    final successValue = row['success'];
    return StoredAgentCommand(
      commandId: row['command_id']?.toString() ?? '',
      nonce: row['nonce']?.toString() ?? '',
      action: row['action']?.toString() ?? '',
      installationId: row['installation_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'executing',
      success: successValue == null ? null : (successValue as num).toInt() == 1,
      message: row['message']?.toString() ?? '',
      result: result,
    );
  }
}

final class AgentCommandClaim {
  const AgentCommandClaim(this.state, {this.stored});

  final AgentCommandClaimState state;
  final StoredAgentCommand? stored;
}

final class PendingAgentAck {
  const PendingAgentAck({
    required this.commandId,
    required this.installationId,
    required this.status,
    required this.message,
    required this.result,
    required this.attempts,
  });

  final String commandId;
  final String installationId;
  final String status;
  final String message;
  final Map<String, dynamic> result;
  final int attempts;

  factory PendingAgentAck.fromRow(Map<String, Object?> row) {
    Map<String, dynamic> result = const {};
    try {
      final decoded = jsonDecode(row['result_json']?.toString() ?? '{}');
      if (decoded is Map) result = decoded.cast<String, dynamic>();
    } catch (_) {}
    return PendingAgentAck(
      commandId: row['command_id']?.toString() ?? '',
      installationId: row['installation_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'failed',
      message: row['message']?.toString() ?? '',
      result: result,
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

final class PendingAgentTelemetry {
  const PendingAgentTelemetry({
    required this.id,
    required this.eventType,
    required this.payload,
  });

  final int id;
  final String eventType;
  final Map<String, Object?> payload;

  factory PendingAgentTelemetry.fromRow(Map<String, Object?> row) {
    Map<String, Object?> payload = const {};
    try {
      final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
      if (decoded is Map) payload = decoded.cast<String, Object?>();
    } catch (_) {}
    return PendingAgentTelemetry(
      id: (row['id'] as num?)?.toInt() ?? 0,
      eventType: row['event_type']?.toString() ?? '',
      payload: payload,
    );
  }
}

final class PendingAgentError {
  const PendingAgentError({
    required this.id,
    required this.payload,
    required this.attempts,
  });

  final int id;
  final Map<String, Object?> payload;
  final int attempts;

  factory PendingAgentError.fromRow(Map<String, Object?> row) {
    Map<String, Object?> payload = const {};
    try {
      final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
      if (decoded is Map) payload = decoded.cast<String, Object?>();
    } catch (_) {}
    return PendingAgentError(
      id: (row['id'] as num?)?.toInt() ?? 0,
      payload: payload,
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cola durable del agente. Vive en la misma SQLite local de MerkaERP para que
/// los ACK y resultados sobrevivan cierres, reinicios y pérdida de red.
class MerkaAgentStore {
  MerkaAgentStore({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseHelper.instance.database);

  static final MerkaAgentStore instance = MerkaAgentStore();

  final Future<Database> Function() _databaseProvider;

  Future<Database> get _database => _databaseProvider();

  Future<void> initialize() async {
    final db = await _database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS processed_command_ids (
        command_id TEXT PRIMARY KEY,
        nonce TEXT NOT NULL UNIQUE,
        action TEXT NOT NULL,
        installation_id TEXT NOT NULL,
        status TEXT NOT NULL,
        success INTEGER,
        message TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_ack (
        command_id TEXT PRIMARY KEY,
        installation_id TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '{}',
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_errors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload_json TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_jobs (
        id TEXT PRIMARY KEY,
        job_type TEXT NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        checksum_sha256 TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_ack_created ON pending_ack(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_telemetry_created ON pending_telemetry(created_at)',
    );
  }

  Future<String?> readState(String key) async {
    await initialize();
    final db = await _database;
    final rows = await db.query(
      'agent_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']?.toString();
  }

  Future<void> writeState(String key, String value) async {
    await initialize();
    final db = await _database;
    await db.insert('agent_state', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AgentCommandClaim> claimCommand({
    required String commandId,
    required String nonce,
    required String action,
    required String installationId,
  }) async {
    await initialize();
    final db = await _database;
    return db.transaction((txn) async {
      final sameId = await txn.query(
        'processed_command_ids',
        where: 'command_id = ?',
        whereArgs: [commandId],
        limit: 1,
      );
      if (sameId.isNotEmpty) {
        final stored = StoredAgentCommand.fromRow(sameId.single);
        if (stored.nonce != nonce || stored.action != action) {
          return AgentCommandClaim(
            AgentCommandClaimState.replay,
            stored: stored,
          );
        }
        return AgentCommandClaim(
          stored.status == 'executing'
              ? AgentCommandClaimState.inFlight
              : AgentCommandClaimState.cached,
          stored: stored,
        );
      }

      final sameNonce = await txn.query(
        'processed_command_ids',
        where: 'nonce = ?',
        whereArgs: [nonce],
        limit: 1,
      );
      if (sameNonce.isNotEmpty) {
        return AgentCommandClaim(
          AgentCommandClaimState.replay,
          stored: StoredAgentCommand.fromRow(sameNonce.single),
        );
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('processed_command_ids', {
        'command_id': commandId,
        'nonce': nonce,
        'action': action,
        'installation_id': installationId,
        'status': 'executing',
        'created_at': now,
      });
      return const AgentCommandClaim(AgentCommandClaimState.claimed);
    });
  }

  Future<void> completeCommand({
    required String commandId,
    required String installationId,
    required bool success,
    required String message,
    required Map<String, dynamic> result,
    required String ackStatus,
  }) async {
    await initialize();
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    final resultJson = jsonEncode(result);
    await db.transaction((txn) async {
      await txn.update(
        'processed_command_ids',
        {
          'status': success ? 'completed' : 'failed',
          'success': success ? 1 : 0,
          'message': message,
          'result_json': resultJson,
          'completed_at': now,
        },
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      await txn.insert('pending_ack', {
        'command_id': commandId,
        'installation_id': installationId,
        'status': ackStatus,
        'message': message,
        'result_json': resultJson,
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> queueRejectedAck({
    required String commandId,
    required String installationId,
    required String message,
    required Map<String, dynamic> result,
  }) async {
    await initialize();
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('pending_ack', {
      'command_id': commandId,
      'installation_id': installationId,
      'status': 'rejected',
      'message': message,
      'result_json': jsonEncode(result),
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingAgentAck>> pendingAcks({int limit = 100}) async {
    await initialize();
    final db = await _database;
    final rows = await db.query(
      'pending_ack',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(PendingAgentAck.fromRow).toList(growable: false);
  }

  Future<void> markAckDelivered(String commandId) async {
    await initialize();
    final db = await _database;
    await db.delete(
      'pending_ack',
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
  }

  Future<void> markAckAttemptFailed(String commandId) async {
    await initialize();
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE pending_ack
         SET attempts = attempts + 1, updated_at = ?
         WHERE command_id = ?''',
      [DateTime.now().toUtc().toIso8601String(), commandId],
    );
  }

  Future<void> enqueueTelemetry(
    String eventType,
    Map<String, Object?> payload,
  ) async {
    await initialize();
    final db = await _database;
    if (eventType == 'heartbeat') {
      // Un heartbeat nuevo reemplaza al anterior: conserva estado reciente y
      // evita reproducir cientos de muestras obsoletas al recuperar la red.
      await db.delete(
        'pending_telemetry',
        where: 'event_type = ?',
        whereArgs: [eventType],
      );
    }
    await db.insert('pending_telemetry', {
      'event_type': eventType,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.rawDelete('''
      DELETE FROM pending_telemetry WHERE id NOT IN (
        SELECT id FROM pending_telemetry ORDER BY id DESC LIMIT 500
      )
    ''');
  }

  Future<List<PendingAgentTelemetry>> pendingTelemetry({
    int limit = 100,
  }) async {
    await initialize();
    final db = await _database;
    final rows = await db.query(
      'pending_telemetry',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(PendingAgentTelemetry.fromRow).toList(growable: false);
  }

  Future<void> markTelemetryDelivered(int id) async {
    await initialize();
    final db = await _database;
    await db.delete('pending_telemetry', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markTelemetryAttemptFailed(int id) async {
    await initialize();
    final db = await _database;
    await db.rawUpdate(
      'UPDATE pending_telemetry SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> enqueueError(Map<String, Object?> payload) async {
    await initialize();
    final db = await _database;
    await db.insert('pending_errors', {
      'payload_json': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.rawDelete('''
      DELETE FROM pending_errors WHERE id NOT IN (
        SELECT id FROM pending_errors ORDER BY id DESC LIMIT 500
      )
    ''');
  }

  Future<List<PendingAgentError>> pendingErrors({int limit = 100}) async {
    await initialize();
    final db = await _database;
    final rows = await db.query(
      'pending_errors',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(PendingAgentError.fromRow).toList(growable: false);
  }

  Future<void> markErrorDelivered(int id) async {
    await initialize();
    final db = await _database;
    await db.delete('pending_errors', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markErrorAttemptFailed(int id) async {
    await initialize();
    final db = await _database;
    await db.rawUpdate(
      'UPDATE pending_errors SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }
}
