import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/sync/application/merka_sync_push_service.dart';
import 'package:merka_erp/sync/data/merka_sync_http_push_client.dart';

void main() {
  const event = MerkaSyncOutboundEvent(
    localId: 1,
    eventId: 'event-1',
    tenantKind: 'commercial',
    tenantId: 'company:1',
    companyId: 1,
    branchId: 1,
    aggregateType: 'sale',
    aggregateId: 'sale:1:device-1:10',
    operation: 'confirmed',
    eventName: 'sale.confirmed',
    eventVersion: 1,
    payload: {
      'sale': {'id': 10},
    },
    payloadChecksum: 'checksum-1',
    idempotencyKey: 'idem-1',
    sourceDeviceId: 'device-1',
    sourceUserId: 'user-1',
    status: 'pending',
    attempts: 0,
    createdAt: '2026-09-02T15:00:00.000Z',
  );

  test('push envía payload, tenant, device, token e idempotency key', () async {
    final poster = _FakePoster(
      response: const MerkaSyncHttpResponse(
        statusCode: 202,
        data: {'remote_event_id': 'remote-1', 'cursor': 'cursor-1'},
      ),
    );
    final client = MerkaSyncHttpPushClient(
      poster: poster,
      authTokenProvider: () async => 'token-abc',
    );

    final ack = await client.push(event);

    expect(ack.accepted, isTrue);
    expect(ack.remoteEventId, 'remote-1');
    expect(ack.remoteCursor, 'cursor-1');
    expect(poster.path, '/api/sync/events');
    expect(poster.body?['event_id'], 'event-1');
    expect(poster.body?['payload_checksum'], 'checksum-1');
    expect(poster.headers?['Authorization'], 'Bearer token-abc');
    expect(poster.headers?['Idempotency-Key'], 'idem-1');
    expect(poster.headers?['X-Merka-Tenant-Kind'], 'commercial');
    expect(poster.headers?['X-Merka-Tenant-Id'], 'company:1');
    expect(poster.headers?['X-Merka-Device-Id'], 'device-1');
  });

  test('push trata duplicado remoto como aceptado idempotente', () async {
    final poster = _FakePoster(
      response: const MerkaSyncHttpResponse(
        statusCode: 409,
        data: {'duplicate': true, 'remoteCursor': 'cursor-dup'},
      ),
    );
    final client = MerkaSyncHttpPushClient(
      poster: poster,
      authTokenProvider: () async => null,
    );

    final ack = await client.push(event);

    expect(ack.accepted, isTrue);
    expect(ack.duplicate, isTrue);
    expect(ack.remoteCursor, 'cursor-dup');
    expect(poster.headers?.containsKey('Authorization'), isFalse);
  });

  test('push lanza excepción descriptiva si servidor rechaza', () async {
    final poster = _FakePoster(
      response: const MerkaSyncHttpResponse(
        statusCode: 401,
        data: {'error': 'invalid token'},
      ),
    );
    final client = MerkaSyncHttpPushClient(
      poster: poster,
      authTokenProvider: () async => 'bad-token',
    );

    expect(
      () => client.push(event),
      throwsA(
        isA<MerkaSyncHttpPushException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', 'invalid token'),
      ),
    );
  });
}

class _FakePoster implements MerkaSyncJsonPoster {
  _FakePoster({required this.response});

  final MerkaSyncHttpResponse response;
  String? path;
  Map<String, Object?>? body;
  Map<String, String>? headers;

  @override
  Future<MerkaSyncHttpResponse> postJson({
    required String path,
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    this.path = path;
    this.body = body;
    this.headers = headers;
    return response;
  }
}
