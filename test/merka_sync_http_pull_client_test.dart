import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/sync/data/merka_sync_http_pull_client.dart';
import 'package:merka_erp/sync/data/merka_sync_http_push_client.dart';

void main() {
  test('pull envía cursor, límite, token y parsea eventos', () async {
    final poster = _FakeGetter(
      response: MerkaSyncHttpResponse(
        statusCode: 200,
        data: {
          'accepted': true,
          'cursor': '12',
          'has_more': false,
          'events': [_remoteEventJson(cursor: '12')],
        },
      ),
    );
    final client = MerkaSyncHttpPullClient(
      getter: poster,
      authTokenProvider: () async => 'token-abc',
    );

    final page = await client.pull(cursor: '3', limit: 50);

    expect(page.cursor, '12');
    expect(page.events.single.remoteEventId, 'remote-12');
    expect(poster.path, '/api/sync/events');
    expect(poster.query?['cursor'], '3');
    expect(poster.query?['limit'], 50);
    expect(poster.query?['include_self'], isFalse);
    expect(poster.headers?['Authorization'], 'Bearer token-abc');
  });

  test('pull lanza excepción descriptiva si servidor rechaza', () async {
    final getter = _FakeGetter(
      response: const MerkaSyncHttpResponse(
        statusCode: 401,
        data: {'error': 'invalid token'},
      ),
    );
    final client = MerkaSyncHttpPullClient(
      getter: getter,
      authTokenProvider: () async => 'bad-token',
    );

    expect(
      () => client.pull(cursor: '0', limit: 100),
      throwsA(
        isA<MerkaSyncHttpPullException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', 'invalid token'),
      ),
    );
  });
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
  };
}

class _FakeGetter implements MerkaSyncJsonGetter {
  _FakeGetter({required this.response});

  final MerkaSyncHttpResponse response;
  String? path;
  Map<String, Object?>? query;
  Map<String, String>? headers;

  @override
  Future<MerkaSyncHttpResponse> getJson({
    required String path,
    required Map<String, Object?> query,
    required Map<String, String> headers,
  }) async {
    this.path = path;
    this.query = query;
    this.headers = headers;
    return response;
  }
}
