import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/sync/application/merka_sale_sync_outbox.dart';
import 'package:merka_erp/sync/application/merka_sync_configured_push_runner.dart';
import 'package:merka_erp/sync/data/merka_sync_http_push_client.dart';

void main() {
  late Database db;
  late _FakePoster poster;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await MerkaSyncLocalSchema.ensure(db);
    await _insertOutboxEvent(db);
    poster = _FakePoster(
      response: const MerkaSyncHttpResponse(statusCode: 202),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('no intenta push si falta endpoint configurado', () async {
    final result = await MerkaSyncConfiguredPushRunner(
      databaseProvider: () async => db,
      authTokenProvider: () async => 'token-abc',
      posterFactory: (_) => poster,
    ).pushPending();

    expect(result.attempted, isFalse);
    expect(result.skipReason, contains('merka_sync_server_endpoint'));
    expect(poster.calls, 0);
    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'pending');
    expect(rows.single['attempts'], 0);
  });

  test('no intenta push si falta token de licencia', () async {
    await _setEndpoint(db);

    final result = await MerkaSyncConfiguredPushRunner(
      databaseProvider: () async => db,
      authTokenProvider: () async => null,
      posterFactory: (_) => poster,
    ).pushPending();

    expect(result.attempted, isFalse);
    expect(result.skipReason, contains('token de licencia'));
    expect(poster.calls, 0);
    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'pending');
    expect(rows.single['attempts'], 0);
  });

  test('con endpoint y token empuja eventos pendientes', () async {
    await _setEndpoint(db);

    final result = await MerkaSyncConfiguredPushRunner(
      databaseProvider: () async => db,
      authTokenProvider: () async => 'token-abc',
      posterFactory: (baseUrl) {
        poster.baseUrl = baseUrl;
        return poster;
      },
      now: () => DateTime.utc(2026, 9, 2, 16),
    ).pushPending();

    expect(result.attempted, isTrue);
    expect(result.pushResult.pushed, 1);
    expect(poster.calls, 1);
    expect(poster.baseUrl, 'https://example-sync.test');
    expect(poster.headers?['Authorization'], 'Bearer token-abc');

    final rows = await db.query('merka_sync_outbox');
    expect(rows.single['status'], 'pushed');
  });
}

Future<void> _setEndpoint(Database db) async {
  await db.insert('app_config', {
    'clave': 'merka_sync_server_endpoint',
    'valor': 'https://example-sync.test',
  });
}

Future<void> _insertOutboxEvent(Database db) async {
  final payloadJson = jsonEncode({
    'sale': {'id': 10},
  });
  final createdAt = DateTime.utc(2026, 9, 2, 14).toIso8601String();
  await db.insert('merka_sync_outbox', {
    'event_id': 'event-1',
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
    'idempotency_key': 'sale.confirmed:1:device-1:10',
    'source_device_id': 'device-1',
    'source_user_id': 'user-1',
    'status': 'pending',
    'attempts': 0,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
}

class _FakePoster implements MerkaSyncJsonPoster {
  _FakePoster({required this.response});

  final MerkaSyncHttpResponse response;
  int calls = 0;
  String? baseUrl;
  Map<String, String>? headers;

  @override
  Future<MerkaSyncHttpResponse> postJson({
    required String path,
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    calls++;
    this.headers = headers;
    return response;
  }
}
