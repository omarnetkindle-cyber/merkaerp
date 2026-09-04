import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_data_sanitizer.dart';
import 'package:merka_erp/agent/agent_diagnostics_service.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/agent/agent_support_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_license_client.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-3A';
  const commandSecret = 'phase-three-a-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 29, 15);
  late Database db;
  late LicenciaInfo license;
  late AgentDiagnosticsService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-three-a-test-key'),
    );
    license = LicenciaInfo(
      uuid: 'LIC-PHASE-3A',
      plan: TipoPlan.profesional,
      estado: EstadoLicencia.activa,
      fechaExpiracion: clock.add(const Duration(days: 30)),
      modulosHabilitados: const ['ventas'],
      hardwareFingerprint: 'HW-PHASE-3A',
      offlineToken: 'eyJheader.eyJsecret.signature',
      clientName: 'Empresa privada que no debe salir',
      installationId: installationId,
    );
    await LicenciaService.instance.guardarLicencia(license);
    ControlCenterSecretStore.instance.configureCommandSecretForTests(
      commandSecret,
    );
    service = AgentDiagnosticsService(
      databaseProvider: () async => db,
      licenseProvider: () async => license,
      operationalStateProvider: () async => LicenseOperationalState.onlineValid,
      backupProvider: () async => const <File>[],
      clock: () => clock,
    );
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test(
    'run_diagnostics ejecuta sólo checks cerrados y estructurados',
    () async {
      final result = await service.runDiagnostics({
        'checks': ['database', 'migrations', 'runtime'],
      });

      expect(result['format'], 'MERKAERP_AGENT_DIAGNOSTICS_1');
      expect(result['overall_status'], 'OK');
      final checks = (result['checks'] as List).cast<Map<String, dynamic>>();
      expect(checks.map((check) => check['id']), [
        'database',
        'migrations',
        'runtime',
      ]);
      expect(checks.every((check) => check['status'] == 'OK'), isTrue);
      expect((result['privacy'] as Map)['business_rows_included'], isFalse);
    },
  );

  test(
    'collect_diagnostics no expone licencia ni datos empresariales',
    () async {
      await db.insert('empresas', {
        'id': 1,
        'nombre': 'Comercial Secreta SAS',
        'nit': '900123456',
      });

      final result = await service.collectDiagnostics(const {});
      final encoded = jsonEncode(result);

      expect(result['mode'], 'sanitized_collection');
      expect(encoded, isNot(contains('eyJheader')));
      expect(encoded, isNot(contains('Empresa privada')));
      expect(encoded, isNot(contains('Comercial Secreta')));
      expect(encoded, isNot(contains('900123456')));
      expect(encoded.length, lessThan(100000));
    },
  );

  test(
    'verificar_base_datos detecta violaciones sin modificar filas',
    () async {
      await db.execute(
        'CREATE TABLE diagnostic_parent (id INTEGER PRIMARY KEY)',
      );
      await db.execute('''
      CREATE TABLE diagnostic_child (
        id INTEGER PRIMARY KEY,
        parent_id INTEGER REFERENCES diagnostic_parent(id)
      )
    ''');
      await db.insert('diagnostic_child', {'id': 1, 'parent_id': 999});

      final result = await service.verifyDatabase(const {});
      final check = (result['checks'] as List).single as Map<String, dynamic>;
      final details = check['details'] as Map<String, dynamic>;

      expect(result['overall_status'], 'ERROR');
      expect(details['foreign_key_violations'], 1);
      final count = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM diagnostic_child',
      );
      expect((count.single['total'] as num).toInt(), 1);
    },
  );

  test('rechaza SQL o comandos recibidos en parámetros', () async {
    await expectLater(
      service.runDiagnostics(const {
        'sql': 'DROP TABLE app_config',
        'checks': ['database'],
      }),
      throwsA(
        isA<AgentDiagnosticRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_DIAGNOSTIC_PARAMETER',
        ),
      ),
    );
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = 'app_config'",
    );
    expect(table, isNotEmpty);
  });

  test('rechaza checks no registrados en el catálogo local', () async {
    await expectLater(
      service.runDiagnostics(const {
        'checks': ['database', 'powershell'],
      }),
      throwsA(
        isA<AgentDiagnosticRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_DIAGNOSTIC_CHECK',
        ),
      ),
    );
  });

  test('sanitiza secretos, JWT, correo y rutas de usuario', () {
    final sanitized =
        AgentDataSanitizer.sanitize({
              'authorization': 'Bearer super-secret',
              'message':
                  'password=hunter2 token=abc user@empresa.test C:\\Users\\Maria\\db.sqlite eyJaaa.eyJbbb.ccc',
              'nested': {'api_key': 'key-123'},
            })
            as Map<String, dynamic>;
    final encoded = jsonEncode(sanitized);

    expect(encoded, isNot(contains('super-secret')));
    expect(encoded, isNot(contains('hunter2')));
    expect(encoded, isNot(contains('key-123')));
    expect(encoded, isNot(contains('user@empresa.test')));
    expect(encoded, isNot(contains('Maria')));
    expect(encoded, isNot(contains('eyJaaa')));
    expect(encoded, contains('<redacted>'));
  });

  test('comando firmado persiste resultado diagnóstico y ACK', () async {
    final command = _signedCommand(
      id: 'CMD-DIAGNOSTIC-3A',
      nonce: 'NONCE-DIAGNOSTIC-3A',
      secret: commandSecret,
      installationId: installationId,
      now: DateTime.now().toUtc(),
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      diagnosticsService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['overall_status'], 'OK');
    expect(result.datos?['format'], 'MERKAERP_AGENT_DIAGNOSTICS_1');
    final ack = (await MerkaAgentStore.instance.pendingAcks()).single;
    expect(ack.status, 'completed');
    expect(ack.result['overall_status'], 'OK');
    expect(
      int.parse(MerkaAgentContract.agentVersion.split('.').first),
      greaterThanOrEqualTo(3),
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      containsAll([
        'run_diagnostics',
        'collect_diagnostics',
        'verificar_base_datos',
      ]),
    );
  });

  test(
    'collect_diagnostics firmado sube artefacto diagnostic sanitizado',
    () async {
      final transport = _FakeTransport();
      final support = AgentSupportService(
        clientProvider: () async => ControlCenterLicenseClient(
          endpoint: 'https://control.test',
          transport: transport,
        ),
        tokenProvider: () async => 'signed-license-token',
        clock: () => clock,
      );
      final params = {
        'checks': ['database', 'runtime'],
        'request_id': '46',
      };
      final command = _signedCommand(
        id: 'CMD-DIAGNOSTIC-ARTIFACT-3A',
        nonce: 'NONCE-DIAGNOSTIC-ARTIFACT-3A',
        secret: commandSecret,
        installationId: installationId,
        now: DateTime.now().toUtc(),
        action: TipoComando.collect_diagnostics,
        params: params,
      );

      final result = await CCCommandsProcessor.instance.procesarComando(
        command,
        diagnosticsService: service,
        supportService: support,
      );

      expect(result.exito, isTrue);
      expect(result.datos?['artifact_uploaded'], isTrue);
      expect(result.datos?['artifact_type'], 'diagnostic');
      expect(result.datos?['artifact_id'], 'ART-DIAGNOSTIC-46');
      final call = transport.calls.single;
      expect(call.url, endsWith('/api/v1/agent/artifacts'));
      expect(call.payload['request_id'], '46');
      expect(call.payload['artifact_type'], 'diagnostic');
      expect(call.payload['name'], 'merkaerp-diagnostic-46.json');
      final content = jsonDecode(call.payload['content']! as String) as Map;
      expect(content['format'], 'MERKAERP_AGENT_DIAGNOSTICS_1');
      expect(content['mode'], 'sanitized_collection');
      expect(jsonEncode(content), isNot(contains('Empresa privada')));
      expect(jsonEncode(content), isNot(contains('signed-license-token')));
      expect(
        (await MerkaAgentStore.instance.pendingAcks()).single.status,
        'completed',
      );
    },
  );
}

ComandoRemoto _signedCommand({
  required String id,
  required String nonce,
  required String secret,
  required String installationId,
  required DateTime now,
  TipoComando action = TipoComando.run_diagnostics,
  Map<String, dynamic>? params,
}) {
  final timestamp = now.toIso8601String();
  final expiresAt = now.add(const Duration(minutes: 10)).toIso8601String();
  final commandParams =
      params ??
      const <String, dynamic>{
        'checks': ['database', 'migrations', 'runtime'],
      };
  final payload = MerkaAgentContract.canonicalCommandPayload(
    id: id,
    action: action.name,
    installationId: installationId,
    timestamp: timestamp,
    expiresAt: expiresAt,
    nonce: nonce,
    params: commandParams,
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();
  return ComandoRemoto(
    id: id,
    tipo: action,
    parametros: commandParams,
    timestamp: now,
    installationId: installationId,
    expiresAt: DateTime.parse(expiresAt),
    nonce: nonce,
    timestampRaw: timestamp,
    expiresAtRaw: expiresAt,
    firmaHmac: signature,
  );
}

final class _CapturedCall {
  const _CapturedCall(this.url, this.payload);

  final String url;
  final Map<String, Object?> payload;
}

final class _FakeTransport implements ControlCenterHttpTransport {
  final List<_CapturedCall> calls = [];

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) async {
    calls.add(_CapturedCall(url, payload));
    return {
      'success': true,
      'artifact_id': 'ART-DIAGNOSTIC-46',
      'sha256': 'b' * 64,
      'size_bytes': utf8.encode(payload['content']?.toString() ?? '').length,
    };
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) async => const {};
}

Future<void> _createMinimalSchema(Database db) async {
  await db.execute('PRAGMA user_version = ${DatabaseHelper.schemaVersion}');
  await db.execute(
    'CREATE TABLE app_config (clave TEXT PRIMARY KEY, valor TEXT)',
  );
  await db.insert('app_config', {'clave': 'company_active_id', 'valor': '1'});
  await db.execute('''
    CREATE TABLE empresas (
      id INTEGER PRIMARY KEY,
      nombre TEXT,
      nit TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE auditoria_eventos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      fecha TEXT,
      accion TEXT,
      entidad TEXT,
      entidad_id INTEGER,
      detalle TEXT,
      usuario TEXT,
      old_values TEXT,
      new_values TEXT,
      ip_address TEXT,
      device_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE sync_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      status TEXT NOT NULL
    )
  ''');
}
