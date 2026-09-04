import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_session_service.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-6';
  const commandSecret = 'phase-six-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 30, 18, 10);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db, withCajaSesiones: true);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-six-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-6',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-6',
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

  test('reiniciar_sesiones cierra sólo sesiones abiertas', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('caja_sesiones', {
      'usuario': 'cajero',
      'estado': 'abierta',
      'abierta_en': clock.subtract(const Duration(hours: 2)).toIso8601String(),
    });
    await db.insert('caja_sesiones', {
      'usuario': 'admin',
      'estado': 'cerrada',
      'abierta_en': clock.subtract(const Duration(hours: 3)).toIso8601String(),
      'cerrada_en': clock.subtract(const Duration(hours: 1)).toIso8601String(),
    });

    final service = AgentSessionService(clock: () => clock);
    final result = await service.restartSessions(const {
      'reason': 'Cierre remoto de prueba',
      'request_id': 100,
    });

    expect(result['format'], 'MERKAERP_AGENT_SESSIONS_1');
    expect(result['closed_sessions'], 1);
    expect(result['table_present'], isTrue);
    final rows = await db.query('caja_sesiones', orderBy: 'usuario');
    expect(rows.where((row) => row['estado'] == 'abierta'), isEmpty);
    expect(
      rows.firstWhere((row) => row['usuario'] == 'cajero')['cerrada_en'],
      clock.toIso8601String(),
    );
    expect(
      rows.firstWhere((row) => row['usuario'] == 'admin')['cerrada_en'],
      clock.subtract(const Duration(hours: 1)).toIso8601String(),
    );
  });

  test('reiniciar_sesiones rechaza parámetros inseguros', () async {
    final service = AgentSessionService(clock: () => clock);

    await expectLater(
      service.restartSessions(const {'sql': 'DROP TABLE caja_sesiones'}),
      throwsA(
        isA<AgentSessionRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_SESSION_PARAMETER',
        ),
      ),
    );

    await expectLater(
      service.restartSessions(const {'reason': 'x; DROP TABLE sesiones'}),
      throwsA(
        isA<AgentSessionRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_SESSION_REASON',
        ),
      ),
    );
  });

  test('reiniciar_sesiones no falla si caja_sesiones no existe', () async {
    await DatabaseHelper.resetForTests();
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db, withCajaSesiones: false);

    final service = AgentSessionService(clock: () => clock);
    final result = await service.restartSessions(const {});

    expect(result['closed_sessions'], 0);
    expect(result['table_present'], isFalse);
  });

  test('comando firmado reinicia sesiones y persiste ACK completado', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('caja_sesiones', {
      'usuario': 'cajero',
      'estado': 'abierta',
      'abierta_en': clock.subtract(const Duration(hours: 2)).toIso8601String(),
    });
    final command = _signedCommand(
      id: 'CMD-SESSIONS-6A',
      nonce: 'NONCE-SESSIONS-6A',
      secret: commandSecret,
      installationId: installationId,
      now: DateTime.now().toUtc(),
      params: const {'reason': 'Rotación administrativa'},
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      sessionService: AgentSessionService(clock: () => clock),
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['closed_sessions'], 1);
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      contains('reiniciar_sesiones'),
    );
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
    action: TipoComando.reiniciar_sesiones.name,
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
    tipo: TipoComando.reiniciar_sesiones,
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

Future<void> _createMinimalSchema(
  Database db, {
  required bool withCajaSesiones,
}) async {
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
  if (!withCajaSesiones) return;
  await db.execute('''
    CREATE TABLE caja_sesiones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      usuario TEXT NOT NULL,
      estado TEXT NOT NULL DEFAULT 'abierta',
      abierta_en TEXT NOT NULL,
      cerrada_en TEXT,
      justificacion TEXT
    )
  ''');
}
