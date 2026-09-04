import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:merka_sync_server/src/sync_auth.dart';
import 'package:merka_sync_server/src/sync_event_store.dart';
import 'package:merka_sync_server/src/sync_routes.dart';

void main() {
  late Handler handler;

  setUp(() {
    handler = MerkaSyncApi(
      auth: const _FixedAuthVerifier(
        SyncAuthContext(
          tenantKind: 'commercial',
          tenantId: 'company:1',
          deviceId: 'device-1',
          userId: 'user-1',
        ),
      ),
      store: InMemorySyncEventStore(),
    ).handler;
  });

  test('GET /health responde ok', () async {
    final response = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['ok'], isTrue);
  });

  test('POST /api/sync/events acepta evento válido', () async {
    final response = await _postEvent(handler, _eventBody());

    expect(response.statusCode, 202);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['accepted'], isTrue);
    expect(body['duplicate'], isFalse);
    expect(body['remote_event_id'], isNotEmpty);
    expect(body['remote_cursor'], '1');
  });

  test('POST /api/sync/events responde idempotente para duplicados', () async {
    await _postEvent(handler, _eventBody());

    final response = await _postEvent(handler, _eventBody());

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['accepted'], isTrue);
    expect(body['duplicate'], isTrue);
    expect(body['remote_cursor'], '1');
  });

  test('POST /api/sync/events rechaza si falta authorization', () async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/sync/events'),
        body: jsonEncode(_eventBody()),
      ),
    );

    expect(response.statusCode, 401);
  });

  test('POST /api/sync/events rechaza tenant manipulado', () async {
    final response = await _postEvent(handler, {
      ..._eventBody(),
      'tenant_id': 'company:999',
    });

    expect(response.statusCode, 401);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['error'], contains('tenant_id'));
  });

  test('POST /api/sync/events rechaza checksum incorrecto', () async {
    final response = await _postEvent(handler, {
      ..._eventBody(),
      'payload_checksum': 'bad-checksum',
    });

    expect(response.statusCode, 400);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['error'], contains('payload_checksum'));
  });

  test('GET /api/sync/events entrega eventos incrementales a otro device',
      () async {
    final store = InMemorySyncEventStore();
    final device1 = _handlerWith(store: store, deviceId: 'device-1');
    final device2 = _handlerWith(store: store, deviceId: 'device-2');
    await _postEvent(device1, _eventBody());

    final response = await _getEvents(device2, cursor: 0);

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['accepted'], isTrue);
    expect(body['cursor'], '1');
    expect(body['has_more'], isFalse);
    final events = body['events'] as List;
    expect(events, hasLength(1));
    expect((events.single as Map)['event_name'], 'sale.confirmed');
    expect((events.single as Map)['source_device_id'], 'device-1');
  });

  test('GET /api/sync/events respeta cursor incremental', () async {
    final store = InMemorySyncEventStore();
    final device1 = _handlerWith(store: store, deviceId: 'device-1');
    final device2 = _handlerWith(store: store, deviceId: 'device-2');
    await _postEvent(device1, _eventBody());

    final response = await _getEvents(device2, cursor: 1);

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['cursor'], '1');
    expect(body['events'], isEmpty);
  });

  test('GET /api/sync/events no devuelve eventos propios por defecto',
      () async {
    await _postEvent(handler, _eventBody());

    final response = await _getEvents(handler, cursor: 0);

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['cursor'], '0');
    expect(body['events'], isEmpty);
  });

  test('GET /api/sync/events puede incluir eventos propios si se solicita',
      () async {
    await _postEvent(handler, _eventBody());

    final response = await _getEvents(handler, cursor: 0, includeSelf: true);

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['cursor'], '1');
    expect(body['events'], hasLength(1));
  });

  test('GET /api/sync/events aísla tenants', () async {
    final store = InMemorySyncEventStore();
    final tenant1 = _handlerWith(store: store, tenantId: 'company:1');
    final tenant2 = _handlerWith(store: store, tenantId: 'company:2');
    await _postEvent(tenant1, _eventBody());

    final response = await _getEvents(tenant2, cursor: 0);

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['tenant_id'], 'company:2');
    expect(body['events'], isEmpty);
  });
}

Future<Response> _postEvent(Handler handler, Map<String, Object?> body) async {
  return await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/sync/events'),
      headers: const {'authorization': 'Bearer valid'},
      body: jsonEncode(body),
    ),
  );
}

Future<Response> _getEvents(
  Handler handler, {
  required int cursor,
  bool includeSelf = false,
}) async {
  return await handler(
    Request(
      'GET',
      Uri.parse(
        'http://localhost/api/sync/events?cursor=$cursor&include_self=$includeSelf',
      ),
      headers: const {'authorization': 'Bearer valid'},
    ),
  );
}

Handler _handlerWith({
  required InMemorySyncEventStore store,
  String tenantKind = 'commercial',
  String tenantId = 'company:1',
  String deviceId = 'device-1',
}) {
  return MerkaSyncApi(
    auth: _FixedAuthVerifier(
      SyncAuthContext(
        tenantKind: tenantKind,
        tenantId: tenantId,
        deviceId: deviceId,
        userId: 'user-1',
      ),
    ),
    store: store,
  ).handler;
}

Map<String, Object?> _eventBody() {
  final payload = {
    'schema_version': 1,
    'event_name': 'sale.confirmed',
    'sale': {'id': 10},
    'details': [],
    'inventory_movements': [],
  };
  return {
    'event_id': 'client-event-1',
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
    'payload_checksum':
        sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
    'idempotency_key': 'sale.confirmed:1:device-1:10',
    'source_device_id': 'device-1',
    'source_user_id': 'user-1',
    'created_at': '2026-09-02T15:00:00.000Z',
  };
}

class _FixedAuthVerifier implements SyncAuthVerifier {
  const _FixedAuthVerifier(this.context);

  final SyncAuthContext context;

  @override
  Future<SyncAuthContext> verify(String? authorizationHeader) async {
    if (authorizationHeader != 'Bearer valid') {
      throw const SyncAuthException('Authorization inválido.');
    }
    return context;
  }
}
