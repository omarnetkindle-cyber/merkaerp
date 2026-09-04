import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_restart_service.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-7';
  const commandSecret = 'phase-seven-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 30, 19, 20);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-seven-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-7',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-7',
        offlineToken: 'signed-license-token',
        installationId: installationId,
      ),
    );
    ControlCenterSecretStore.instance.configureCommandSecretForTests(
      commandSecret,
    );
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test(
    'reiniciar agenda relanzamiento diferido y persiste intención',
    () async {
      Duration? scheduledDelay;
      final service = AgentRestartService(
        clock: () => clock,
        executableProvider: () => r'C:\MerkaERP\MerkaERP.exe',
        restartScheduler: (delay) async {
          scheduledDelay = delay;
        },
      );

      final result = await service.requestRestart(const {
        'reason': 'Actualización administrativa',
        'delay_seconds': 7,
        'request_id': 200,
      });

      expect(result['format'], 'MERKAERP_AGENT_RESTART_1');
      expect(result['restart_scheduled'], isTrue);
      expect(result['delay_seconds'], 7);
      expect(result['local_path_disclosed'], isFalse);
      expect(scheduledDelay, const Duration(seconds: 7));

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('app_config');
      final config = {
        for (final row in rows) row['clave'] as String: row['valor'] as String,
      };
      expect(config['cc_restart_requested_at'], clock.toIso8601String());
      expect(config['cc_restart_reason'], 'Actualización administrativa');
      expect(config['cc_restart_delay_seconds'], '7');
    },
  );

  test(
    'reiniciar rechaza parámetros inseguros o delay fuera de rango',
    () async {
      final service = AgentRestartService(
        executableProvider: () => r'C:\MerkaERP\MerkaERP.exe',
        restartScheduler: (_) async {},
      );

      await expectLater(
        service.requestRestart(const {'command': 'shutdown /r'}),
        throwsA(
          isA<AgentRestartRequestException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_RESTART_PARAMETER',
          ),
        ),
      );

      await expectLater(
        service.requestRestart(const {'delay_seconds': 1}),
        throwsA(
          isA<AgentRestartRequestException>().having(
            (error) => error.code,
            'code',
            'INVALID_RESTART_DELAY',
          ),
        ),
      );

      await expectLater(
        service.requestRestart(const {'reason': 'reiniciar; del *'}),
        throwsA(
          isA<AgentRestartRequestException>().having(
            (error) => error.code,
            'code',
            'INVALID_RESTART_REASON',
          ),
        ),
      );
    },
  );

  test('reiniciar falla recuperable si no identifica ejecutable', () async {
    final service = AgentRestartService(
      executableProvider: () => '',
      restartScheduler: (_) async {},
    );

    await expectLater(
      service.requestRestart(const {}),
      throwsA(
        isA<AgentRestartExecutionException>().having(
          (error) => error.code,
          'code',
          'RESTART_EXECUTABLE_UNAVAILABLE',
        ),
      ),
    );
  });

  test('comando firmado programa reinicio y persiste ACK completado', () async {
    Duration? scheduledDelay;
    final service = AgentRestartService(
      clock: () => clock,
      executableProvider: () => r'C:\MerkaERP\MerkaERP.exe',
      restartScheduler: (delay) async {
        scheduledDelay = delay;
      },
    );
    final now = DateTime.now().toUtc();
    final command = _signedCommand(
      id: 'CMD-RESTART-7A',
      nonce: 'NONCE-RESTART-7A',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: const {'delay_seconds': 5},
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      restartService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['restart_scheduled'], isTrue);
    expect(scheduledDelay, const Duration(seconds: 5));
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(MerkaAgentContract.phaseOneCapabilities, contains('reiniciar'));
    expect(int.parse(MerkaAgentContract.agentVersion.split('.').first), 5);
  });
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
    action: TipoComando.reiniciar.name,
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
    tipo: TipoComando.reiniciar,
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
