import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:merka_erp/sync/application/merka_sale_sync_outbox.dart';
import 'package:merka_erp/sync/application/merka_sync_push_service.dart';

void main() {
  late Database db;
  late DateTime now;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    now = DateTime.utc(2026, 9, 2, 15);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await MerkaSyncLocalSchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('pushPending marca como enviados los eventos aceptados', () async {
    final eventId = await _insertOutboxEvent(db);
    final client = _FakeMerkaSyncPushClient(
      ack: const MerkaSyncPushAck(
        accepted: true,
        remoteEventId: 'remote-1',
        remoteCursor: 'cursor-1',
      ),
    );

    final result = await MerkaSyncOutboxPushService(
      client: client,
      now: () => now,
    ).pushPending(db: db);

    expect(result.pushed, 1);
    expect(result.failed, 0);
    expect(result.terminalErrors, 0);
    expect(client.events.single.eventId, eventId);
    expect(client.events.single.toTransportJson()['payload'], {
      'sale': {'id': 10},
    });

    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'pushed');
    expect(rows.single['attempts'], 0);
    expect(rows.single['pushed_at'], now.toIso8601String());
    expect(rows.single['remote_cursor'], 'cursor-1');
    expect(rows.single['last_error'], isNull);
  });

  test(
    'pushPending deja retry con backoff cuando falla el transporte',
    () async {
      await _insertOutboxEvent(db);
      final client = _FakeMerkaSyncPushClient(error: StateError('offline'));

      final result = await MerkaSyncOutboxPushService(
        client: client,
        now: () => now,
      ).pushPending(db: db);

      expect(result.pushed, 0);
      expect(result.failed, 1);
      expect(result.terminalErrors, 0);

      final rows = await db.query('merka_sync_outbox');
      expect(rows.single['status'], 'retry');
      expect(rows.single['attempts'], 1);
      expect(
        rows.single['next_attempt_at'],
        now.add(const Duration(seconds: 5)).toIso8601String(),
      );
      expect(rows.single['last_error'].toString(), contains('offline'));
    },
  );

  test('pushPending omite retries que todavía no están disponibles', () async {
    await _insertOutboxEvent(
      db,
      status: 'retry',
      attempts: 1,
      nextAttemptAt: now.add(const Duration(minutes: 10)),
    );
    final client = _FakeMerkaSyncPushClient();

    final result = await MerkaSyncOutboxPushService(
      client: client,
      now: () => now,
    ).pushPending(db: db);

    expect(result.processed, 0);
    expect(client.events, isEmpty);

    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'retry');
    expect(rows.single['attempts'], 1);
  });

  test('pushPending pasa a error al agotar intentos', () async {
    await _insertOutboxEvent(db, attempts: 1);
    final client = _FakeMerkaSyncPushClient(error: StateError('server down'));

    final result = await MerkaSyncOutboxPushService(
      client: client,
      now: () => now,
      maxAttempts: 2,
    ).pushPending(db: db);

    expect(result.pushed, 0);
    expect(result.failed, 0);
    expect(result.terminalErrors, 1);

    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'error');
    expect(rows.single['attempts'], 2);
    expect(rows.single['next_attempt_at'], isNull);
    expect(rows.single['last_error'].toString(), contains('server down'));
  });
}

Future<String> _insertOutboxEvent(
  Database db, {
  String status = 'pending',
  int attempts = 0,
  DateTime? nextAttemptAt,
}) async {
  const uuid = Uuid();
  final eventId = uuid.v4();
  final payloadJson = jsonEncode({
    'sale': {'id': 10},
  });
  final createdAt = DateTime.utc(2026, 9, 2, 14).toIso8601String();
  await db.insert('merka_sync_outbox', {
    'event_id': eventId,
    'tenant_kind': 'commercial',
    'tenant_id': 'company:1',
    'company_id': 1,
    'branch_id': 1,
    'aggregate_type': 'sale',
    'aggregate_id': 'sale:1:device-1:10',
    'operation': 'confirmed',
    'event_name': 'sale.confirmed',
    'event_version': 1,
    'payload_json': payloadJson,
    'payload_checksum': sha256.convert(utf8.encode(payloadJson)).toString(),
    'idempotency_key': 'sale.confirmed:1:device-1:10:$eventId',
    'source_device_id': 'device-1',
    'source_user_id': 'user-1',
    'status': status,
    'attempts': attempts,
    'created_at': createdAt,
    'updated_at': createdAt,
    'next_attempt_at': nextAttemptAt?.toIso8601String(),
  });
  return eventId;
}

class _FakeMerkaSyncPushClient implements MerkaSyncPushClient {
  _FakeMerkaSyncPushClient({
    this.ack = const MerkaSyncPushAck(accepted: true),
    this.error,
  });

  final MerkaSyncPushAck ack;
  final Object? error;
  final List<MerkaSyncOutboundEvent> events = [];

  @override
  Future<MerkaSyncPushAck> push(MerkaSyncOutboundEvent event) async {
    events.add(event);
    final failure = error;
    if (failure != null) throw failure;
    return ack;
  }
}
