import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/control_center_agent.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-one-test-key'),
    );
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
  });

  tearDown(() async {
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test('payload canónico coincide con el contrato backend y ordena anidados', () {
    final payload = MerkaAgentContract.canonicalCommandPayload(
      id: '42',
      action: 'mensaje_admin',
      installationId: 'INST-1',
      timestamp: '2026-08-28T12:00:00.000Z',
      expiresAt: '2026-08-28T12:10:00.000Z',
      nonce: 'NONCE-1',
      params: {
        'z': 1,
        'a': {'d': 4, 'c': 3},
      },
    );

    expect(
      payload,
      '{"action":"mensaje_admin","expires_at":"2026-08-28T12:10:00.000Z","id":"42","installation_id":"INST-1","nonce":"NONCE-1","params":{"a":{"c":3,"d":4},"z":1},"timestamp":"2026-08-28T12:00:00.000Z"}',
    );
  });

  test('una acción fuera del allowlist se rechaza sin mapearla a mensaje', () {
    expect(
      () => ComandoRemoto.fromJson({
        'id': '1',
        'action': 'powershell',
        'installation_id': 'INST-1',
        'timestamp': '2026-08-28T12:00:00.000Z',
        'expires_at': '2026-08-28T12:10:00.000Z',
        'nonce': 'N-1',
        'params': {'script': 'Get-Process'},
        'signature': '00',
      }),
      throwsFormatException,
    );
  });

  test(
    'resultado y ACK quedan persistidos y se recuperan por command_id',
    () async {
      final claim = await MerkaAgentStore.instance.claimCommand(
        commandId: 'CMD-STORE-1',
        nonce: 'NONCE-STORE-1',
        action: 'mensaje_admin',
        installationId: 'INST-1',
      );
      expect(claim.state, AgentCommandClaimState.claimed);

      await MerkaAgentStore.instance.completeCommand(
        commandId: 'CMD-STORE-1',
        installationId: 'INST-1',
        success: true,
        message: 'ok',
        result: const {'notification_id': 7},
        ackStatus: 'completed',
      );

      final repeated = await MerkaAgentStore.instance.claimCommand(
        commandId: 'CMD-STORE-1',
        nonce: 'NONCE-STORE-1',
        action: 'mensaje_admin',
        installationId: 'INST-1',
      );
      expect(repeated.state, AgentCommandClaimState.cached);
      expect(repeated.stored!.result['notification_id'], 7);

      final acks = await MerkaAgentStore.instance.pendingAcks();
      expect(acks, hasLength(1));
      expect(acks.single.commandId, 'CMD-STORE-1');
      expect(acks.single.result['notification_id'], 7);
    },
  );

  test(
    'reintento firmado devuelve resultado guardado sin ejecutar dos veces',
    () async {
      const installationId = 'INST-IDEMPOTENT-1';
      const secret = 'agent-command-secret-with-32-bytes';
      await _configureLicense(installationId);
      ControlCenterSecretStore.instance.configureCommandSecretForTests(secret);
      final command = _signedCommand(
        id: 'CMD-IDEMPOTENT-1',
        installationId: installationId,
        secret: secret,
        nonce: 'NONCE-IDEMPOTENT-1',
      );

      final first = await CCCommandsProcessor.instance.procesarComando(command);
      final repeated = await CCCommandsProcessor.instance.procesarComando(
        command,
      );

      expect(first.exito, isTrue);
      expect(repeated.exito, isTrue);
      final notifications = await db.query('notificaciones');
      expect(notifications, hasLength(1));
      expect(await MerkaAgentStore.instance.pendingAcks(), hasLength(1));
    },
  );

  test(
    'installation_uuid local se genera una vez y permanece estable',
    () async {
      final first = await ControlCenterAgent.installationIdForTests();
      final second = await ControlCenterAgent.installationIdForTests();

      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f-]{27}$')));
      final rows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['control_center_installation_id'],
      );
      expect(rows.single['valor'], first);
    },
  );

  test(
    'firma inválida no ejecuta y registra INVALID_COMMAND_SIGNATURE',
    () async {
      const installationId = 'INST-INVALID-1';
      await _configureLicense(installationId);
      ControlCenterSecretStore.instance.configureCommandSecretForTests(
        'valid-secret-with-at-least-32-bytes',
      );
      final command = _signedCommand(
        id: 'CMD-INVALID-1',
        installationId: installationId,
        secret: 'different-secret-with-32-bytes!!',
        nonce: 'NONCE-INVALID-1',
      );

      final result = await CCCommandsProcessor.instance.procesarComando(
        command,
      );

      expect(result.exito, isFalse);
      expect(result.datos?['error_code'], 'INVALID_COMMAND_SIGNATURE');
      expect(await db.query('notificaciones'), isEmpty);
      final audit = await db.query('auditoria_eventos');
      expect(
        audit.map((row) => row['accion']),
        contains('INVALID_COMMAND_SIGNATURE'),
      );
      final acks = await MerkaAgentStore.instance.pendingAcks();
      expect(acks.single.status, 'rejected');
    },
  );

  test('migración v113 crea todas las colas oficiales del Agent', () async {
    final migrationDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(migrationDb.close);

    await DatabaseHelper.instance.migrarDBForTesting(migrationDb, 112, 113);

    for (final table in const [
      'agent_state',
      'processed_command_ids',
      'pending_ack',
      'pending_telemetry',
      'pending_errors',
      'download_jobs',
    ]) {
      final rows = await migrationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      expect(rows, isNotEmpty, reason: 'Falta tabla oficial v113: $table');
    }
  });
}

Future<void> _configureLicense(String installationId) {
  return LicenciaService.instance.guardarLicencia(
    LicenciaInfo(
      uuid: 'LIC-$installationId',
      plan: TipoPlan.profesional,
      estado: EstadoLicencia.activa,
      fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
      modulosHabilitados: const ['ventas'],
      installationId: installationId,
    ),
  );
}

ComandoRemoto _signedCommand({
  required String id,
  required String installationId,
  required String secret,
  required String nonce,
}) {
  final timestamp = DateTime.now().toUtc();
  final expiresAt = timestamp.add(const Duration(minutes: 5));
  final timestampRaw = timestamp.toIso8601String();
  final expiresAtRaw = expiresAt.toIso8601String();
  const params = {'titulo': 'Aviso único', 'detalle': 'No duplicar'};
  final payload = MerkaAgentContract.canonicalCommandPayload(
    id: id,
    action: TipoComando.mensaje_admin.name,
    installationId: installationId,
    timestamp: timestampRaw,
    expiresAt: expiresAtRaw,
    nonce: nonce,
    params: params,
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();
  return ComandoRemoto(
    id: id,
    tipo: TipoComando.mensaje_admin,
    parametros: params,
    timestamp: timestamp,
    installationId: installationId,
    expiresAt: expiresAt,
    nonce: nonce,
    timestampRaw: timestampRaw,
    expiresAtRaw: expiresAtRaw,
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
  await db.execute('''
    CREATE TABLE notificaciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      tipo TEXT,
      prioridad TEXT,
      titulo TEXT,
      detalle TEXT,
      entidad TEXT,
      entidad_id TEXT,
      leida INTEGER,
      creada_en TEXT
    )
  ''');
}
