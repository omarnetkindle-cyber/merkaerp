import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/backup/full_backup_service.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/agent/agent_update_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/services/update_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-5';
  const commandSecret = 'phase-five-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 29, 23);
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('merka_agent_phase5_');
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-five-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-5',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-5',
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

  test('forzar_actualizacion descarga y aplica metadata firmada', () async {
    final installer = await _writeInstaller(tempDir, 'MerkaERP-1.4.0.exe');
    InfoVersion? downloaded;
    String? appliedPath;
    final service = AgentUpdateService(
      updateChecker: () async => _updateInfo(),
      updateDownloader: (info) async {
        downloaded = info;
        return installer.path;
      },
      updateApplier: (path) async {
        appliedPath = path;
      },
      clock: () => clock,
    );

    final result = await service.forceUpdate(const {
      'target_version': '1.4.0',
      'channel': 'stable',
      'request_id': '100',
    });

    expect(downloaded?.version, '1.4.0');
    expect(appliedPath, installer.path);
    expect(result['format'], 'MERKAERP_AGENT_UPDATE_1');
    expect(result['installed_version'], '1.4.0');
    expect(result['download_ref'], 'MerkaERP-1.4.0.exe');
    expect(result['checksum'], 'a' * 64);
    expect(result['manifest_verified'], isTrue);
    expect(result['applied'], isTrue);
    expect(result['local_path_disclosed'], isFalse);
  });

  test(
    'forzar_actualizacion rechaza parámetros y versiones inseguras',
    () async {
      final service = AgentUpdateService(
        updateChecker: () async => _updateInfo(),
      );

      await expectLater(
        service.forceUpdate(const {'installer_path': r'C:\temp\evil.exe'}),
        throwsA(
          isA<AgentUpdateRequestException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_UPDATE_PARAMETER',
          ),
        ),
      );

      await expectLater(
        service.forceUpdate(const {'target_version': '../1.4.0'}),
        throwsA(
          isA<AgentUpdateRequestException>().having(
            (error) => error.code,
            'code',
            'INVALID_UPDATE_VERSION',
          ),
        ),
      );
    },
  );

  test(
    'forzar_actualizacion falla si la versión objetivo no está disponible',
    () async {
      final service = AgentUpdateService(
        updateChecker: () async => _updateInfo(),
      );

      await expectLater(
        service.forceUpdate(const {'target_version': '1.5.0'}),
        throwsA(
          isA<AgentUpdateExecutionException>().having(
            (error) => error.code,
            'code',
            'UPDATE_TARGET_NOT_AVAILABLE',
          ),
        ),
      );
    },
  );

  test('forzar_actualizacion rechaza URL o manifiesto inseguros', () async {
    final service = AgentUpdateService(
      updateChecker: () async => _updateInfo(
        url: 'http://updates.example.test/MerkaERP.exe',
        manifestToken: 'signed-manifest-token',
      ),
    );

    await expectLater(
      service.forceUpdate(const {}),
      throwsA(
        isA<AgentUpdateExecutionException>().having(
          (error) => error.code,
          'code',
          'UPDATE_INSECURE_URL',
        ),
      ),
    );

    final missingManifest = AgentUpdateService(
      updateChecker: () async => _updateInfo(manifestToken: ''),
    );
    await expectLater(
      missingManifest.forceUpdate(const {}),
      throwsA(
        isA<AgentUpdateExecutionException>().having(
          (error) => error.code,
          'code',
          'UPDATE_MANIFEST_REQUIRED',
        ),
      ),
    );
  });

  test(
    'comando firmado aplica actualización y persiste ACK completado',
    () async {
      final installer = await _writeInstaller(tempDir, 'MerkaERP-1.4.0.exe');
      final service = AgentUpdateService(
        updateChecker: () async => _updateInfo(),
        updateDownloader: (_) async => installer.path,
        updateApplier: (path) async {
          expect(path, installer.path);
        },
        clock: () => clock,
      );
      final now = DateTime.now().toUtc();
      final params = {'target_version': '1.4.0', 'canal': 'stable'};
      final command = _signedCommand(
        id: 'CMD-UPDATE-5A',
        nonce: 'NONCE-UPDATE-5A',
        secret: commandSecret,
        installationId: installationId,
        now: now,
        params: params,
      );

      final result = await CCCommandsProcessor.instance.procesarComando(
        command,
        updateService: service,
      );

      expect(result.exito, isTrue);
      expect(result.datos?['ack_status'], 'completed');
      expect(result.datos?['installed_version'], '1.4.0');
      expect(
        (await MerkaAgentStore.instance.pendingAcks()).single.status,
        'completed',
      );
      expect(
        MerkaAgentContract.phaseOneCapabilities,
        contains('forzar_actualizacion'),
      );
      expect(MerkaAgentContract.agentVersion, startsWith('5.'));
    },
  );

  test(
    'rollback_actualizacion valida versión y exige snapshot local',
    () async {
      final service = AgentUpdateService(
        updateChecker: () async => _updateInfo(),
      );

      await expectLater(
        service.rollbackUpdate(const {'target_version': '../1.3.0'}),
        throwsA(
          isA<AgentUpdateRequestException>().having(
            (error) => error.code,
            'code',
            'INVALID_UPDATE_VERSION',
          ),
        ),
      );

      await expectLater(
        service.rollbackUpdate(const {'target_version': '1.3.0'}),
        throwsA(
          isA<AgentUpdateExecutionException>().having(
            (error) => error.code,
            'code',
            'UPDATE_ROLLBACK_SNAPSHOT_UNAVAILABLE',
          ),
        ),
      );
    },
  );

  test(
    'rollback_actualizacion restaura snapshot pre-update verificado',
    () async {
      final backup = await _writeInstaller(tempDir, 'preupdate.mkbackup');
      final backupHash = await sha256.bind(backup.openRead()).first;
      await _writeRollbackSnapshot(
        fromVersion: '1.3.0',
        toVersion: '1.4.0',
        backupRef: 'preupdate.mkbackup',
        backupSha256: backupHash.toString(),
      );
      File? restoredBackup;
      final service = AgentUpdateService(
        rollbackBackupLister: () async => [backup],
        rollbackBackupVerifier: (_) async => const FullBackupVerification(
          ok: true,
          message: 'ok',
          entries: 2,
          bytes: 2048,
          documentFiles: 1,
          databaseVersion: 113,
        ),
        rollbackRestoreDrill: (_) async => const FullBackupDrillResult(
          ok: true,
          message: 'ok',
          databaseVersion: 113,
          tables: 30,
        ),
        rollbackRestorer: (file) async {
          restoredBackup = file;
        },
        clock: () => clock,
      );

      final result = await service.rollbackUpdate({
        'target_version': '1.3.0',
        'backup_ref': 'preupdate.mkbackup',
        'checksum': backupHash.toString(),
      });

      expect(restoredBackup, backup);
      expect(result['format'], 'MERKAERP_AGENT_ROLLBACK_1');
      expect(result['restored_version'], '1.3.0');
      expect(result['rolled_back_from_version'], '1.4.0');
      expect(result['data_snapshot_restored'], isTrue);
      expect(result['binary_rollback_applied'], isFalse);
      expect(result['binary_rollback_scheduled'], isFalse);
      expect(result['requires_signed_installer_rollback'], isTrue);
      expect(result['local_path_disclosed'], isFalse);
    },
  );

  test(
    'rollback_actualizacion agenda instalador firmado para rollback binario',
    () async {
      final backup = await _writeInstaller(
        tempDir,
        'preupdate_binary.mkbackup',
      );
      final backupHash = await sha256.bind(backup.openRead()).first;
      final installer = await _writeInstaller(
        tempDir,
        'MerkaERP-1.3.0-rollback.exe',
      );
      final installerHash = await sha256.bind(installer.openRead()).first;
      await _writeRollbackSnapshot(
        fromVersion: '1.3.0',
        toVersion: '1.4.0',
        backupRef: 'preupdate_binary.mkbackup',
        backupSha256: backupHash.toString(),
      );
      Map<String, dynamic>? scheduledPlan;
      final service = AgentUpdateService(
        rollbackPublisherTokenValidator: (token, installationId) async {
          expect(token, 'signed.rollback.manifest');
          expect(installationId, 'INST-PHASE-5');
          return _rollbackPayload(installerSha256: installerHash.toString());
        },
        rollbackBackupLister: () async => [backup],
        rollbackBackupVerifier: (_) async => const FullBackupVerification(
          ok: true,
          message: 'ok',
          entries: 2,
          bytes: 2048,
          documentFiles: 1,
          databaseVersion: 113,
        ),
        rollbackRestoreDrill: (_) async =>
            const FullBackupDrillResult(ok: true, message: 'ok'),
        rollbackRestorer: (_) async {},
        rollbackInstallerLister: () async => [installer],
        binaryRollbackScheduler: (plan) async {
          scheduledPlan = plan;
          return const {
            'format': 'MERKAERP_BINARY_ROLLBACK_SCHEDULED_1',
            'installer_ref': 'MerkaERP-1.3.0-rollback.exe',
            'plan_ref': 'rollback_plan_test.json',
            'scheduled': true,
          };
        },
        clock: () => clock,
      );

      final result = await service.rollbackUpdate({
        'target_version': '1.3.0',
        'backup_ref': 'preupdate_binary.mkbackup',
        'checksum': backupHash.toString(),
        'manifest_token': 'signed.rollback.manifest',
      });

      expect(scheduledPlan?['installer_path'], installer.path);
      expect(scheduledPlan?['installer_sha256'], installerHash.toString());
      expect(result['format'], 'MERKAERP_AGENT_ROLLBACK_1');
      expect(result['data_snapshot_restored'], isTrue);
      expect(result['binary_rollback_applied'], isFalse);
      expect(result['binary_rollback_scheduled'], isTrue);
      expect(result['requires_signed_installer_rollback'], isFalse);
      expect(result['binary_rollback_ref'], 'MerkaERP-1.3.0-rollback.exe');
      expect(result['binary_rollback_plan_ref'], 'rollback_plan_test.json');
      expect(result['local_path_disclosed'], isFalse);
    },
  );

  test('aplicar_hotfix rechaza parámetros o referencias inseguras', () async {
    final service = AgentUpdateService(
      updateChecker: () async => _updateInfo(),
    );

    await expectLater(
      service.applyHotfix(const {'script': 'Remove-Item -Recurse C:\\'}),
      throwsA(
        isA<AgentUpdateRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_UPDATE_PARAMETER',
        ),
      ),
    );

    await expectLater(
      service.applyHotfix(const {'hotfix_id': '../hotfix'}),
      throwsA(
        isA<AgentUpdateRequestException>().having(
          (error) => error.code,
          'code',
          'INVALID_HOTFIX_REF',
        ),
      ),
    );
  });

  test(
    'aplicar_hotfix ejecuta manifiesto firmado con snapshot previo',
    () async {
      final snapshot = await _writeInstaller(tempDir, 'prehotfix.mkbackup');
      final snapshotHash = await sha256.bind(snapshot.openRead()).first;
      final operations = <Map<String, dynamic>>[];
      final service = AgentUpdateService(
        publisherTokenValidator: (token, installationId) async {
          expect(token, 'signed.hotfix.manifest');
          expect(installationId, 'INST-PHASE-5');
          return _hotfixPayload(
            checksum: 'b' * 64,
            operations: const [
              {'type': 'repair', 'repair_code': 'clear_cache'},
              {
                'type': 'configuration',
                'settings': {'currency': 'COP'},
              },
              {
                'type': 'feature_flags',
                'technical_flags': {'rest_api_enabled': true},
              },
            ],
          );
        },
        hotfixBackupCreator: (_) async => snapshot,
        hotfixBackupVerifier: (_) async => const FullBackupVerification(
          ok: true,
          message: 'ok',
          entries: 1,
          bytes: 1024,
          databaseVersion: 113,
        ),
        safeRepairRunner: (params) async {
          operations.add({'type': 'repair', ...params});
          return const {
            'format': 'MERKAERP_AGENT_REPAIR_1',
            'repair_code': 'clear_cache',
          };
        },
        configurationApplier: (params) async {
          operations.add({'type': 'configuration', ...params});
          return const {
            'format': 'MERKAERP_AGENT_MANAGED_CONFIG_1',
            'applied_settings': ['currency'],
          };
        },
        featureFlagsApplier: (params) async {
          operations.add({'type': 'feature_flags', ...params});
          return const {
            'format': 'MERKAERP_AGENT_FEATURE_FLAGS_1',
            'applied_technical_flags': ['rest_api_enabled'],
          };
        },
        clock: () => clock,
      );

      final result = await service.applyHotfix({
        'hotfix_id': 'HF-2026-08-30-1',
        'target_version': '1.3.0',
        'checksum': 'b' * 64,
        'manifest_token': 'signed.hotfix.manifest',
      });

      expect(result['format'], 'MERKAERP_AGENT_HOTFIX_1');
      expect(result['hotfix_id'], 'HF-2026-08-30-1');
      expect(result['manifest_verified'], isTrue);
      expect(result['pre_hotfix_backup_ref'], 'prehotfix.mkbackup');
      expect(result['pre_hotfix_backup_checksum'], snapshotHash.toString());
      expect(result['operation_count'], 3);
      expect(result['local_path_disclosed'], isFalse);
      expect(operations.map((op) => op['type']), [
        'repair',
        'configuration',
        'feature_flags',
      ]);
    },
  );

  test('aplicar_hotfix restaura snapshot si una operación falla', () async {
    final snapshot = await _writeInstaller(
      tempDir,
      'prehotfix_failed.mkbackup',
    );
    var restored = false;
    final service = AgentUpdateService(
      publisherTokenValidator: (_, _) async => _hotfixPayload(
        checksum: 'd' * 64,
        operations: const [
          {'type': 'repair', 'repair_code': 'clear_cache'},
        ],
      ),
      hotfixBackupCreator: (_) async => snapshot,
      hotfixBackupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      safeRepairRunner: (_) async => throw StateError('fallo controlado'),
      rollbackRestorer: (_) async {
        restored = true;
      },
    );

    await expectLater(
      service.applyHotfix({
        'hotfix_id': 'HF-2026-08-30-1',
        'target_version': '1.3.0',
        'checksum': 'd' * 64,
        'manifest_token': 'signed.hotfix.manifest',
      }),
      throwsA(
        isA<AgentUpdateExecutionException>().having(
          (error) => error.code,
          'code',
          'UPDATE_HOTFIX_APPLY_FAILED',
        ),
      ),
    );
    expect(restored, isTrue);
  });

  test('rollback y hotfix firmados persisten ACK fallido controlado', () async {
    final service = AgentUpdateService(
      updateChecker: () async => _updateInfo(),
    );
    final now = DateTime.now().toUtc();
    final rollback = _signedCommand(
      id: 'CMD-ROLLBACK-5B',
      nonce: 'NONCE-ROLLBACK-5B',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: const {'target_version': '1.3.0'},
      action: TipoComando.rollback_actualizacion,
    );
    final hotfix = _signedCommand(
      id: 'CMD-HOTFIX-5B',
      nonce: 'NONCE-HOTFIX-5B',
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: {'hotfix_id': 'HF-2026-08-30-1', 'checksum': 'c' * 64},
      action: TipoComando.aplicar_hotfix,
    );

    final rollbackResult = await CCCommandsProcessor.instance.procesarComando(
      rollback,
      updateService: service,
    );
    final hotfixResult = await CCCommandsProcessor.instance.procesarComando(
      hotfix,
      updateService: service,
    );

    expect(rollbackResult.exito, isFalse);
    expect(
      rollbackResult.datos?['error_code'],
      'UPDATE_ROLLBACK_SNAPSHOT_UNAVAILABLE',
    );
    expect(rollbackResult.datos?['recoverable'], isTrue);
    expect(hotfixResult.exito, isFalse);
    expect(
      hotfixResult.datos?['error_code'],
      'UPDATE_HOTFIX_MANIFEST_REQUIRED',
    );
    expect(hotfixResult.datos?['recoverable'], isFalse);
    final acks = await MerkaAgentStore.instance.pendingAcks();
    expect(acks.map((ack) => ack.status), everyElement('failed'));
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      contains('rollback_actualizacion'),
    );
    expect(MerkaAgentContract.phaseOneCapabilities, contains('aplicar_hotfix'));
  });

  test('rollback firmado con snapshot persiste ACK completado', () async {
    final backup = await _writeInstaller(tempDir, 'signed_preupdate.mkbackup');
    final backupHash = await sha256.bind(backup.openRead()).first;
    await _writeRollbackSnapshot(
      fromVersion: '1.3.0',
      toVersion: '1.4.0',
      backupRef: 'signed_preupdate.mkbackup',
      backupSha256: backupHash.toString(),
    );
    final service = AgentUpdateService(
      rollbackBackupLister: () async => [backup],
      rollbackBackupVerifier: (_) async => const FullBackupVerification(
        ok: true,
        message: 'ok',
        entries: 1,
        bytes: 1024,
        databaseVersion: 113,
      ),
      rollbackRestoreDrill: (_) async =>
          const FullBackupDrillResult(ok: true, message: 'ok'),
      rollbackRestorer: (_) async {},
      clock: () => clock,
    );
    final command = _signedCommand(
      id: 'CMD-ROLLBACK-5C',
      nonce: 'NONCE-ROLLBACK-5C',
      secret: commandSecret,
      installationId: installationId,
      now: DateTime.now().toUtc(),
      params: {'target_version': '1.3.0', 'checksum': backupHash.toString()},
      action: TipoComando.rollback_actualizacion,
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      updateService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['restored_version'], '1.3.0');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
  });

  test('hotfix firmado persiste ACK completado', () async {
    final snapshot = await _writeInstaller(
      tempDir,
      'signed_prehotfix.mkbackup',
    );
    final service = AgentUpdateService(
      publisherTokenValidator: (_, _) async => _hotfixPayload(
        checksum: 'e' * 64,
        operations: const [
          {'type': 'repair', 'repair_code': 'clear_cache'},
        ],
      ),
      hotfixBackupCreator: (_) async => snapshot,
      hotfixBackupVerifier: (_) async =>
          const FullBackupVerification(ok: true, message: 'ok'),
      safeRepairRunner: (_) async => const {
        'format': 'MERKAERP_AGENT_REPAIR_1',
        'repair_code': 'clear_cache',
      },
      clock: () => clock,
    );
    final command = _signedCommand(
      id: 'CMD-HOTFIX-5C',
      nonce: 'NONCE-HOTFIX-5C',
      secret: commandSecret,
      installationId: installationId,
      now: DateTime.now().toUtc(),
      params: {
        'hotfix_id': 'HF-2026-08-30-1',
        'target_version': '1.3.0',
        'checksum': 'e' * 64,
        'manifest_token': 'signed.hotfix.manifest',
      },
      action: TipoComando.aplicar_hotfix,
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      updateService: service,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['hotfix_id'], 'HF-2026-08-30-1');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(MerkaAgentContract.agentVersion, startsWith('5.5.'));
  });
}

InfoVersion _updateInfo({
  String version = '1.4.0',
  String url = 'https://updates.example.test/MerkaERP-1.4.0.exe',
  String? sha,
  String? manifestToken = 'signed-manifest-token',
}) {
  return InfoVersion(
    version: version,
    canal: CanalActualizacion.stable,
    fechaPublicacion: DateTime.utc(2026, 8, 29),
    urlDescarga: url,
    tamanoBytes: 4096,
    sha256: sha ?? 'a' * 64,
    obligatoria: true,
    manifestToken: manifestToken,
  );
}

Future<File> _writeInstaller(Directory dir, String name) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsString('fake-installer-$name', flush: true);
  return file;
}

Future<void> _writeRollbackSnapshot({
  required String fromVersion,
  required String toVersion,
  required String backupRef,
  required String backupSha256,
}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('app_config', {
    'clave': UpdateService.rollbackSnapshotConfigKey,
    'valor': jsonEncode({
      'format': 'MERKAERP_UPDATE_ROLLBACK_SNAPSHOT_1',
      'from_version': fromVersion,
      'to_version': toVersion,
      'backup_ref': backupRef,
      'backup_sha256': backupSha256,
    }),
  });
}

Map<String, dynamic> _hotfixPayload({
  String hotfixId = 'HF-2026-08-30-1',
  String targetVersion = '1.3.0',
  String? checksum,
  required List<Map<String, dynamic>> operations,
}) {
  return {
    'hotfix': {
      'hotfix_id': hotfixId,
      'target_version': targetVersion,
      'checksum': ?checksum,
      'operations': operations,
    },
  };
}

Map<String, dynamic> _rollbackPayload({
  String targetVersion = '1.3.0',
  String fromVersion = '1.4.0',
  String installerRef = 'MerkaERP-1.3.0-rollback.exe',
  required String installerSha256,
}) {
  return {
    'rollback': {
      'target_version': targetVersion,
      'from_version': fromVersion,
      'installer_ref': installerRef,
      'installer_sha256': installerSha256,
    },
  };
}

ComandoRemoto _signedCommand({
  required String id,
  required String nonce,
  required String secret,
  required String installationId,
  required DateTime now,
  required Map<String, dynamic> params,
  TipoComando action = TipoComando.forzar_actualizacion,
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
