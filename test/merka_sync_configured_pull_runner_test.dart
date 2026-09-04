import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/licensing/domain/product_family.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/sync/application/merka_sale_sync_outbox.dart';
import 'package:merka_erp/sync/application/merka_sync_configured_pull_runner.dart';
import 'package:merka_erp/sync/data/merka_sync_http_pull_client.dart';
import 'package:merka_erp/sync/data/merka_sync_http_push_client.dart';

void main() {
  late Database db;
  late _FakeGetter getter;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await MerkaSyncLocalSchema.ensure(db);
    await db.insert('app_config', {'clave': 'company_active_id', 'valor': '1'});
    getter = _FakeGetter(
      response: MerkaSyncHttpResponse(
        statusCode: 200,
        data: {
          'accepted': true,
          'cursor': '9',
          'has_more': false,
          'events': [_remoteEventJson(cursor: '9')],
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('no intenta pull si falta endpoint configurado', () async {
    final result = await MerkaSyncConfiguredPullRunner(
      databaseProvider: () async => db,
      licenseProvider: () async => _license(),
      getterFactory: (_) => getter,
    ).pullPending();

    expect(result.attempted, isFalse);
    expect(result.skipReason, contains('merka_sync_server_endpoint'));
    expect(getter.calls, 0);
  });

  test('no intenta pull si falta token de licencia', () async {
    await _setEndpoint(db);

    final result = await MerkaSyncConfiguredPullRunner(
      databaseProvider: () async => db,
      licenseProvider: () async => _license(offlineToken: null),
      getterFactory: (_) => getter,
    ).pullPending();

    expect(result.attempted, isFalse);
    expect(result.skipReason, contains('token de licencia'));
    expect(getter.calls, 0);
  });

  test('con endpoint, token y device baja eventos a inbox', () async {
    await _setEndpoint(db);

    final result = await MerkaSyncConfiguredPullRunner(
      databaseProvider: () async => db,
      licenseProvider: () async => _license(),
      getterFactory: (baseUrl) {
        getter.baseUrl = baseUrl;
        return getter;
      },
    ).pullPending();

    expect(result.attempted, isTrue);
    expect(result.pullResult.received, 1);
    expect(getter.calls, 1);
    expect(getter.baseUrl, 'https://example-sync.test');
    expect(getter.headers?['Authorization'], 'Bearer token-abc');

    final inbox = await db.query('merka_sync_inbox');
    expect(inbox, hasLength(1));
    final checkpoints = await db.query('merka_sync_checkpoints');
    expect(checkpoints.single['tenant_kind'], 'commercial');
    expect(checkpoints.single['tenant_id'], 'company:1');
    expect(checkpoints.single['source_device_id'], 'device-2');
    expect(checkpoints.single['cursor'], '9');
  });
}

Future<void> _setEndpoint(Database db) async {
  await db.insert('app_config', {
    'clave': 'merka_sync_server_endpoint',
    'valor': 'https://example-sync.test',
  });
}

LicenciaInfo _license({String? offlineToken = 'token-abc'}) {
  return LicenciaInfo(
    uuid: 'license-1',
    plan: TipoPlan.profesional,
    estado: EstadoLicencia.activa,
    fechaExpiracion: DateTime.utc(2027),
    modulosHabilitados: const ['ventas', 'inventario'],
    productFamily: ProductFamily.commercial,
    offlineToken: offlineToken,
    installationId: 'device-2',
  );
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
  int calls = 0;
  String? baseUrl;
  Map<String, String>? headers;

  @override
  Future<MerkaSyncHttpResponse> getJson({
    required String path,
    required Map<String, Object?> query,
    required Map<String, String> headers,
  }) async {
    calls++;
    this.headers = headers;
    return response;
  }
}
