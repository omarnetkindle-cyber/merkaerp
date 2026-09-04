import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_backup_service.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/core/backup/full_backup_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-4';
  const commandSecret = 'phase-four-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 29, 22);
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('merka_agent_phase4_');
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-four-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-4',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-4',
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
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'forzar_respaldo devuelve referencia, checksum y verificación',
    () async {
      final backupFile = await _writeBackup(tempDir, 'cc_forzado_1.mkbackup');
      final service = AgentBackupService(
        backupCreator: (_) async => backupFile,
        backupVerifier: (_) async => const FullBackupVerification(
          ok: true,
          message: 'ok',
          entries: 3,
          bytes: 120,
          documentFiles: 2,
          databaseVersion: 113,
        ),
        clock: () => clock,
      );

      final result = await service.forceBackup(const {'request_id': '90'});
      final expectedHash = await sha256.bind(backupFile.openRead()).first;

      expect(result['backup_ref'], 'cc_forzado_1.mkbackup');
      expect(result['checksum'], expectedHash.toString());
      expect(result['checksum_algorithm'], 'SHA-256');
      expect(result['verified'], isTrue);
      expect(result['entries'], 3);
      expect(result['document_files'], 2);
      expect(result['database_version'], 113);
      expect(result['local_path_disclosed'], isFalse);
    },
  );

  test('forzar_respaldo rechaza parámetros y labels inseguros', () async {
    final service = AgentBackupService(
      backupCreator: (_) async => _writeBackup(tempDir, 'unused.mkbackup'),
      backupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      clock: () => clock,
    );

    await expectLater(
      service.forceBackup(const {'path': r'C:\secretos\backup.db'}),
      throwsA(
        isA<AgentBackupRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_BACKUP_PARAMETER',
        ),
      ),
    );

    await expectLater(
      service.forceBackup(const {'label': '../otro'}),
      throwsA(
        isA<AgentBackupRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_BACKUP_LABEL',
        ),
      ),
    );
  });

  test(
    'forzar_respaldo falla recuperable si la verificación no pasa',
    () async {
      final service = AgentBackupService(
        backupCreator: (_) async => _writeBackup(tempDir, 'corrupt.mkbackup'),
        backupVerifier: (_) async => const FullBackupVerification(
          ok: false,
          message: 'checksum inválido',
        ),
        clock: () => clock,
      );

      await expectLater(
        service.forceBackup(const {}),
        throwsA(
          isA<AgentBackupExecutionException>().having(
            (error) => error.code,
            'code',
            'BACKUP_VERIFICATION_FAILED',
          ),
        ),
      );
    },
  );

  test('comando firmado crea respaldo y persiste ACK completado', () async {
    final backupFile = await _writeBackup(tempDir, 'signed_backup.mkbackup');
    final service = AgentBackupService(
      backupCreator: (label) async {
        expect(label, 'cc_forzado');
        return backupFile;
      },
      backupVerifier: (_) async => const FullBackupVerification(
        ok: true,
        message: 'ok',
        entries: 1,
        bytes: 32,
        databaseVersion: 113,
      ),
      clock: () => clock,
    );
    final now = DateTime.now().toUtc();
    final command = _signedCommand(
      id: 'CMD-BACKUP-4A',
      nonce: 'NONCE-BACKUP-4A',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: const {},
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      backupService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['backup_ref'], 'signed_backup.mkbackup');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      int.parse(MerkaAgentContract.agentVersion.split('.').first),
      greaterThanOrEqualTo(4),
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      contains('forzar_respaldo'),
    );
  });

  test(
    'restaurar_respaldo verifica checksum, drill y snapshot previo',
    () async {
      final backupFile = await _writeBackup(tempDir, 'target.mkbackup');
      final snapshotFile = await _writeBackup(tempDir, 'snapshot.mkbackup');
      final expectedHash = await sha256.bind(backupFile.openRead()).first;
      final snapshotHash = await sha256.bind(snapshotFile.openRead()).first;
      final creatorLabels = <String>[];
      File? restoredFile;
      final service = AgentBackupService(
        backupCreator: (label) async {
          creatorLabels.add(label);
          return snapshotFile;
        },
        backupVerifier: (_) async => const FullBackupVerification(
          ok: true,
          message: 'ok',
          entries: 2,
          bytes: 60,
          documentFiles: 1,
          databaseVersion: 113,
        ),
        backupLister: () async => [backupFile],
        restoreDrill: (_) async => const FullBackupDrillResult(
          ok: true,
          message: 'ok',
          databaseVersion: 113,
          tables: 12,
          documentReferences: 4,
          missingDocumentReferences: 0,
        ),
        backupRestorer: (backup) async {
          restoredFile = backup;
        },
        clock: () => clock,
      );

      final result = await service.restoreBackup({
        'backup_ref': 'target.mkbackup',
        'checksum': expectedHash.toString(),
        'request_id': '91',
      });

      expect(result['format'], 'MERKAERP_AGENT_RESTORE_1');
      expect(result['backup_ref'], 'target.mkbackup');
      expect(result['checksum'], expectedHash.toString());
      expect(result['pre_restore_backup_ref'], 'snapshot.mkbackup');
      expect(result['pre_restore_checksum'], snapshotHash.toString());
      expect(result['verified'], isTrue);
      expect(result['restore_drill_ok'], isTrue);
      expect(result['tables_checked'], 12);
      expect(result['document_references'], 4);
      expect(result['missing_document_references'], 0);
      expect(result['local_path_disclosed'], isFalse);
      expect(creatorLabels, ['cc_pre_restore']);
      expect(restoredFile, backupFile);
    },
  );

  test('restaurar_respaldo rechaza referencia o checksum inseguros', () async {
    final service = AgentBackupService(
      backupCreator: (_) async => _writeBackup(tempDir, 'snapshot.mkbackup'),
      backupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      backupLister: () async => const [],
      restoreDrill: (_) async =>
          const FullBackupDrillResult(ok: true, message: 'ok'),
      backupRestorer: (_) async {},
      clock: () => clock,
    );

    await expectLater(
      service.restoreBackup(const {
        'backup_ref': '../target.mkbackup',
        'checksum':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      }),
      throwsA(
        isA<AgentBackupRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_BACKUP_REF',
        ),
      ),
    );

    await expectLater(
      service.restoreBackup(const {
        'backup_ref': 'target.mkbackup',
        'checksum': 'bad',
      }),
      throwsA(
        isA<AgentBackupRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_BACKUP_CHECKSUM',
        ),
      ),
    );
  });

  test('restaurar_respaldo falla si el checksum no coincide', () async {
    final backupFile = await _writeBackup(tempDir, 'target.mkbackup');
    final service = AgentBackupService(
      backupCreator: (_) async => _writeBackup(tempDir, 'snapshot.mkbackup'),
      backupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      backupLister: () async => [backupFile],
      restoreDrill: (_) async =>
          const FullBackupDrillResult(ok: true, message: 'ok'),
      backupRestorer: (_) async {},
      clock: () => clock,
    );

    await expectLater(
      service.restoreBackup(const {
        'backup_ref': 'target.mkbackup',
        'checksum':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      }),
      throwsA(
        isA<AgentBackupExecutionException>().having(
          (error) => error.code,
          'code',
          'BACKUP_CHECKSUM_MISMATCH',
        ),
      ),
    );
  });

  test('restaurar_respaldo falla si el simulacro no pasa', () async {
    final backupFile = await _writeBackup(tempDir, 'target.mkbackup');
    final expectedHash = await sha256.bind(backupFile.openRead()).first;
    final service = AgentBackupService(
      backupCreator: (_) async => _writeBackup(tempDir, 'snapshot.mkbackup'),
      backupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      backupLister: () async => [backupFile],
      restoreDrill: (_) async =>
          const FullBackupDrillResult(ok: false, message: 'faltan documentos'),
      backupRestorer: (_) async {},
      clock: () => clock,
    );

    await expectLater(
      service.restoreBackup({
        'backup_ref': 'target.mkbackup',
        'checksum': expectedHash.toString(),
      }),
      throwsA(
        isA<AgentBackupExecutionException>().having(
          (error) => error.code,
          'code',
          'RESTORE_DRILL_FAILED',
        ),
      ),
    );
  });

  test('comando firmado restaura respaldo y persiste ACK completado', () async {
    final backupFile = await _writeBackup(tempDir, 'signed_restore.mkbackup');
    final snapshotFile = await _writeBackup(tempDir, 'pre_restore.mkbackup');
    final expectedHash = await sha256.bind(backupFile.openRead()).first;
    final service = AgentBackupService(
      backupCreator: (label) async {
        expect(label, 'cc_pre_restore');
        return snapshotFile;
      },
      backupVerifier: (_) async => const FullBackupVerification(
        ok: true,
        message: 'ok',
        entries: 2,
        bytes: 64,
        databaseVersion: 113,
      ),
      backupLister: () async => [backupFile],
      restoreDrill: (_) async => const FullBackupDrillResult(
        ok: true,
        message: 'ok',
        databaseVersion: 113,
        tables: 11,
      ),
      backupRestorer: (backup) async {
        expect(backup, backupFile);
      },
      clock: () => clock,
    );
    final now = DateTime.now().toUtc();
    final params = {
      'backup_ref': 'signed_restore.mkbackup',
      'checksum': expectedHash.toString(),
    };
    final command = _signedCommand(
      id: 'CMD-RESTORE-4B',
      nonce: 'NONCE-RESTORE-4B',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: params,
      action: TipoComando.restaurar_respaldo,
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      backupService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['backup_ref'], 'signed_restore.mkbackup');
    expect(result.datos?['pre_restore_backup_ref'], 'pre_restore.mkbackup');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      contains('restaurar_respaldo'),
    );
    expect(
      int.parse(MerkaAgentContract.agentVersion.split('.').first),
      greaterThanOrEqualTo(4),
    );
  });
}

Future<File> _writeBackup(Directory dir, String name) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsString('fake-backup-$name', flush: true);
  return file;
}

ComandoRemoto _signedCommand({
  required String id,
  required String nonce,
  required String secret,
  required String installationId,
  required DateTime now,
  required Map<String, dynamic> params,
  TipoComando action = TipoComando.forzar_respaldo,
}) {
  final timestamp = now.toIso8601String();
  final expiresAt = now.add(const Duration(minutes: 10)).toIso8601String();
  final payload = MerkaAgentContract.canonicalCommandPayload(
    id: id,
    action: action.name,
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
    tipo: action,
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
