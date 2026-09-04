import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/sync/application/merka_sale_sync_outbox.dart';
import 'package:merka_erp/sync/application/merka_sync_pull_service.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await MerkaSyncLocalSchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('pullPending guarda eventos remotos en inbox y checkpoint', () async {
    final client = _FakePullClient(
      pages: [
        MerkaSyncPullPage(
          events: [_remoteEvent(cursor: '7')],
          cursor: '7',
          hasMore: false,
        ),
      ],
    );

    final result = await MerkaSyncPullService(client: client).pullPending(
      db: db,
      tenantKind: 'commercial',
      tenantId: 'company:1',
      localDeviceId: 'device-2',
    );

    expect(result.received, 1);
    expect(result.duplicates, 0);
    expect(result.cursor, '7');
    expect(client.cursors.single, '0');

    final inbox = await db.query('merka_sync_inbox');
    expect(inbox, hasLength(1));
    expect(inbox.single['remote_event_id'], 'remote-7');
    expect(inbox.single['status'], 'pending');

    final checkpoints = await db.query('merka_sync_checkpoints');
    expect(checkpoints.single['cursor'], '7');
    expect(checkpoints.single['direction'], 'pull');
  });

  test('pullPending es idempotente y no duplica inbox', () async {
    final event = _remoteEvent(cursor: '7');
    final client = _FakePullClient(
      pages: [
        MerkaSyncPullPage(events: [event], cursor: '7', hasMore: false),
        MerkaSyncPullPage(events: [event], cursor: '7', hasMore: false),
      ],
    );
    final service = MerkaSyncPullService(client: client);

    await service.pullPending(
      db: db,
      tenantKind: 'commercial',
      tenantId: 'company:1',
      localDeviceId: 'device-2',
    );
    final result = await service.pullPending(
      db: db,
      tenantKind: 'commercial',
      tenantId: 'company:1',
      localDeviceId: 'device-2',
    );

    expect(result.received, 0);
    expect(result.duplicates, 1);
    final inbox = await db.query('merka_sync_inbox');
    expect(inbox, hasLength(1));
  });

  test('remote event rechaza checksum incorrecto', () {
    expect(
      () => MerkaSyncRemoteEvent.fromJson({
        ..._remoteEventJson(cursor: '8'),
        'payload_checksum': 'bad',
      }),
      throwsFormatException,
    );
  });
}

MerkaSyncRemoteEvent _remoteEvent({required String cursor}) {
  return MerkaSyncRemoteEvent.fromJson(_remoteEventJson(cursor: cursor));
}

Map<String, Object?> _remoteEventJson({required String cursor}) {
  final payload = {
    'schema_version': 1,
    'event_name': 'sale.confirmed',
    'sale': {'id': 10},
  };
  return {
    'cursor': cursor,
    'remote_event_id': 'remote-$cursor',
    'tenant_kind': 'commercial',
    'tenant_id': 'company:1',
    'company_id': 1,
    'branch_id': 1,
    'aggregate_type': 'sale',
    'aggregate_id': 'sale:1:device-1:10',
    'operation': 'confirmed',
    'event_name': 'sale.confirmed',
    'event_version': 1,
    'payload': payload,
    'payload_checksum': sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString(),
    'idempotency_key': 'sale.confirmed:1:device-1:10',
    'source_device_id': 'device-1',
    'source_user_id': 'user-1',
    'client_event_id': 'client-event-1',
    'client_created_at': '2026-09-02T15:00:00.000Z',
    'received_at': '2026-09-02T15:01:00.000Z',
  };
}

class _FakePullClient implements MerkaSyncPullClient {
  _FakePullClient({required this.pages});

  final List<MerkaSyncPullPage> pages;
  final List<String> cursors = [];

  @override
  Future<MerkaSyncPullPage> pull({
    required String cursor,
    required int limit,
  }) async {
    cursors.add(cursor);
    return pages.removeAt(0);
  }
}
