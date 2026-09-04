import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_error_reporter.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/agent/agent_support_service.dart';
import 'package:merka_erp/control_center_agent.dart';
import 'package:merka_erp/core/logging/log_entry.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_license_client.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-3B';
  const commandSecret = 'phase-three-b-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 29, 18);
  late Database db;
  late _FakeTransport transport;
  late AgentSupportService support;

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
      LicenseSecureStore(testKey: 'agent-phase-three-b-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-3B',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-3B',
        offlineToken: 'signed-license-token',
        installationId: installationId,
      ),
    );
    ControlCenterSecretStore.instance.configureCommandSecretForTests(
      commandSecret,
    );
    transport = _FakeTransport();
    support = _supportService(transport, clock, [
      LogEntry(
        id: 'LOG-1',
        level: LogLevel.error,
        message: 'Falló password=hunter2 para user@empresa.test token=abc',
        module: 'database',
        userId: 'USER-SECRET',
        companyId: 'COMPANY-SECRET',
        timestamp: clock.subtract(const Duration(minutes: 5)),
        metadata: const {'api_key': 'private-key'},
        stackTrace: r'C:\Users\Maria\app.dart:10',
      ),
    ]);
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test('enviar_log carga JSON sanitizado con request_id y límite', () async {
    final result = await support.collectAndUploadLogs({
      'request_id': '42',
      'periodo_inicio': clock
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'periodo_fin': clock.toIso8601String(),
      'max_bytes': 2048,
    });

    expect(result['artifact_id'], 'ART-42');
    expect(result['sanitized'], isTrue);
    final call = transport.calls.single;
    expect(call.url, endsWith('/api/v1/agent/artifacts'));
    expect(call.payload['request_id'], '42');
    expect(call.payload['artifact_type'], 'logs');
    final content = call.payload['content'] as String;
    expect(utf8.encode(content).length, lessThanOrEqualTo(2048));
    expect(content, isNot(contains('hunter2')));
    expect(content, isNot(contains('user@empresa.test')));
    expect(content, isNot(contains('Maria')));
    expect(content, isNot(contains('USER-SECRET')));
    expect(content, isNot(contains('COMPANY-SECRET')));
    expect(content, isNot(contains('private-key')));
  });

  test('recorta entradas completas sin producir JSON inválido', () async {
    final logs = List.generate(
      20,
      (index) => LogEntry(
        id: '$index',
        level: LogLevel.warning,
        message: 'Mensaje técnico $index ${'x' * 300}',
        timestamp: clock.subtract(Duration(minutes: index)),
      ),
    );
    support = _supportService(transport, clock, logs);

    final result = await support.collectAndUploadLogs({
      'request_id': '43',
      'periodo_inicio': clock
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'periodo_fin': clock.toIso8601String(),
      'max_bytes': 1024,
    });
    final content = transport.calls.single.payload['content'] as String;

    expect(utf8.encode(content).length, lessThanOrEqualTo(1024));
    expect(() => jsonDecode(content), returnsNormally);
    expect(result['omitted_for_size'], greaterThan(0));
  });

  test('rechaza request_id inválido antes de subir contenido', () async {
    await expectLater(
      support.collectAndUploadLogs({'request_id': '../otra-instalacion'}),
      throwsA(
        isA<AgentLogRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_ARTIFACT_REQUEST_ID',
        ),
      ),
    );
    expect(transport.calls, isEmpty);
  });

  test('rechaza parámetros de archivo, SQL o shell', () async {
    await expectLater(
      support.collectAndUploadLogs(const {
        'request_id': '44',
        'path': r'C:\secretos',
        'sql': 'SELECT * FROM clientes',
      }),
      throwsA(
        isA<AgentLogRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_LOG_PARAMETER',
        ),
      ),
    );
    expect(transport.calls, isEmpty);
  });

  test('comando firmado sube logs y persiste ACK completado', () async {
    final now = DateTime.now().toUtc();
    final command = _signedCommand(
      id: 'CMD-LOGS-3B',
      nonce: 'NONCE-LOGS-3B',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: {
        'request_id': '45',
        'periodo_inicio': clock
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'periodo_fin': clock.toIso8601String(),
        'max_bytes': 4096,
      },
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      supportService: support,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['artifact_id'], 'ART-42');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      int.parse(MerkaAgentContract.agentVersion.split('.').first),
      greaterThanOrEqualTo(3),
    );
    expect(MerkaAgentContract.phaseOneCapabilities, contains('enviar_log'));
  });

  test('reporte de error se guarda sanitizado en cola durable', () async {
    await AgentErrorReporter.instance.queue(
      message: 'token=secret-value para admin@empresa.test',
      module: 'database',
      severity: 'critical',
      stackTrace: r'C:\Users\Pedro\service.dart:20',
      context: const {'password': 'dont-store-me', 'operation': 'open'},
    );

    final pending = (await MerkaAgentStore.instance.pendingErrors()).single;
    final encoded = jsonEncode(pending.payload);
    expect(pending.payload['severity'], 'critical');
    expect(encoded, isNot(contains('secret-value')));
    expect(encoded, isNot(contains('admin@empresa.test')));
    expect(encoded, isNot(contains('Pedro')));
    expect(encoded, isNot(contains('dont-store-me')));
  });

  test(
    'errores pendientes se reintentan y eliminan sólo al confirmar',
    () async {
      await AgentErrorReporter.instance.queue(
        message: 'Fallo técnico controlado',
        module: 'sync',
      );
      transport.error = const ControlCenterNetworkException('offline');
      final client = ControlCenterLicenseClient(
        endpoint: 'https://control.test',
        transport: transport,
      );

      await ControlCenterAgent.flushPendingErrorsForTests(
        client: client,
        token: 'signed-license-token',
      );
      var pending = (await MerkaAgentStore.instance.pendingErrors()).single;
      expect(pending.attempts, 1);

      transport.error = null;
      await ControlCenterAgent.flushPendingErrorsForTests(
        client: client,
        token: 'signed-license-token',
      );
      expect(await MerkaAgentStore.instance.pendingErrors(), isEmpty);
      expect(transport.calls.last.url, endsWith('/api/v1/errors/report'));
    },
  );
}

AgentSupportService _supportService(
  _FakeTransport transport,
  DateTime clock,
  List<LogEntry> logs,
) {
  return AgentSupportService(
    logProvider: () => logs,
    clientProvider: () async => ControlCenterLicenseClient(
      endpoint: 'https://control.test',
      transport: transport,
    ),
    tokenProvider: () async => 'signed-license-token',
    clock: () => clock,
  );
}

ComandoRemoto _signedCommand({
  required String id,
  required String nonce,
  required String secret,
  required String installationId,
  required DateTime now,
  required Map<String, dynamic> params,
}) {
  final timestamp = now.toIso8601String();
  final expiresAt = now.add(const Duration(minutes: 10)).toIso8601String();
  final payload = MerkaAgentContract.canonicalCommandPayload(
    id: id,
    action: TipoComando.enviar_log.name,
    installationId: installationId,
    timestamp: timestamp,
    expiresAt: expiresAt,
    nonce: nonce,
    params: params,
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();
  return ComandoRemoto(
    id: id,
    tipo: TipoComando.enviar_log,
    parametros: params,
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
  Object? error;

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) async {
    if (error != null) throw error!;
    calls.add(_CapturedCall(url, payload));
    if (url.endsWith('/agent/artifacts')) {
      return {
        'success': true,
        'artifact_id': 'ART-42',
        'sha256': 'a' * 64,
        'size_bytes': utf8.encode(payload['content']?.toString() ?? '').length,
      };
    }
    return const {'success': true, 'signature': 'ERROR-SIGNATURE'};
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) async => const {};
}

Future<void> _createMinimalSchema(Database db) async {
  await db.execute(
    'CREATE TABLE app_config (clave TEXT PRIMARY KEY, valor TEXT)',
  );
  await db.insert('app_config', {'clave': 'company_active_id', 'valor': '1'});
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
}
