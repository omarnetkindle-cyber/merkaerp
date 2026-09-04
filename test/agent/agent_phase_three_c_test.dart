import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_managed_config_service.dart';
import 'package:merka_erp/agent/agent_maintenance_service.dart';
import 'package:merka_erp/agent/agent_repair_service.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/agent/agent_sync_service.dart';
import 'package:merka_erp/core/features/feature_flag.dart';
import 'package:merka_erp/core/maintenance/maintenance_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/features/feature_key.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-3C';
  const commandSecret = 'phase-three-c-command-secret-32-bytes';
  final clock = DateTime.utc(2026, 8, 29, 20);
  late AgentManagedConfigService managedConfig;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    SharedPreferences.setMockInitialValues({});
    await FeatureFlagService.instance.initialize();
    await FeatureFlagService.instance.resetAll();
    CompanyConfigurationService.instance.resetForTests();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-three-c-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-3C',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: clock.add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: 'HW-PHASE-3C',
        offlineToken: 'signed-license-token',
        installationId: installationId,
      ),
    );
    ControlCenterSecretStore.instance.configureCommandSecretForTests(
      commandSecret,
    );
    managedConfig = AgentManagedConfigService(clock: () => clock);
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
  });

  test('aplicar_configuracion persiste solo settings permitidos', () async {
    final result = await managedConfig.applyConfiguration({
      'settings': {
        'currency': 'usd',
        'vat_enabled': false,
        'withholding_enabled': true,
        'default_tax': '19',
      },
    });

    final config = await CompanyConfigurationService.instance.loadActive(
      force: true,
    );
    expect(result['applied_settings'], [
      'currency',
      'default_tax',
      'vat_enabled',
      'withholding_enabled',
    ]);
    expect(config.settings['currency'], 'USD');
    expect(config.settings['vat_enabled'], '0');
    expect(config.settings['withholding_enabled'], '1');
    expect(config.settings['default_tax'], '0');
  });

  test('aplicar_configuracion rechaza claves libres o peligrosas', () async {
    await expectLater(
      managedConfig.applyConfiguration(const {
        'settings': {'currency': 'COP'},
        'sql': 'DROP TABLE company_settings',
      }),
      throwsA(
        isA<AgentManagedConfigRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_MANAGED_CONFIG_PARAMETER',
        ),
      ),
    );

    await expectLater(
      managedConfig.applyConfiguration(const {
        'settings': {'control_center_endpoint': 'http://127.0.0.1:8787'},
      }),
      throwsA(
        isA<AgentManagedConfigRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_MANAGED_CONFIGURATION_KEY',
        ),
      ),
    );
  });

  test(
    'aplicar_feature_flags combina features empresariales y flags técnicas',
    () async {
      final result = await managedConfig.applyFeatureFlags({
        'business_features': {FeatureKey.crm: false, FeatureKey.pos: true},
        'technical_flags': {'rest_api_enabled': false},
      });
      final config = await CompanyConfigurationService.instance.loadActive(
        force: true,
      );

      expect(result['applied_business_features'], [
        FeatureKey.crm,
        FeatureKey.pos,
      ]);
      expect(result['applied_technical_flags'], ['rest_api_enabled']);
      expect(config.features[FeatureKey.crm], isFalse);
      expect(config.features[FeatureKey.pos], isTrue);
      expect(config.features[FeatureKey.cash], isTrue);
      expect(
        FeatureFlagService.instance.isEnabled('rest_api_enabled'),
        isFalse,
      );
    },
  );

  test(
    'aplicar_feature_flags puede tomar flags del bootstrap almacenado',
    () async {
      await MerkaAgentStore.instance.writeState(
        'bootstrap_v2',
        jsonEncode({
          'feature_flags': {
            FeatureKey.services: true,
            'webhooks_enabled': false,
          },
        }),
      );

      final result = await managedConfig.applyFeatureFlags({
        'from_bootstrap': true,
      });
      final config = await CompanyConfigurationService.instance.loadActive(
        force: true,
      );

      expect(result['source'], 'bootstrap_v2');
      expect(config.features[FeatureKey.services], isTrue);
      expect(
        FeatureFlagService.instance.isEnabled('webhooks_enabled'),
        isFalse,
      );
    },
  );

  test('aplicar_feature_flags rechaza flags desconocidas', () async {
    await expectLater(
      managedConfig.applyFeatureFlags(const {
        'flags': {'ejecutar_sql_remoto': true},
      }),
      throwsA(
        isA<AgentManagedConfigRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_FEATURE_FLAG',
        ),
      ),
    );
  });

  test(
    'comando firmado aplica feature flags y persiste ACK completado',
    () async {
      final now = DateTime.now().toUtc();
      final command = _signedCommand(
        id: 'CMD-FLAGS-3C',
        nonce: 'NONCE-FLAGS-3C',
        action: TipoComando.aplicar_feature_flags,
        secret: commandSecret,
        installationId: installationId,
        now: now,
        params: {
          'flags': {FeatureKey.crm: false, 'rest_api_enabled': false},
        },
      );

      final result = await CCCommandsProcessor.instance.procesarComando(
        command,
        managedConfigService: managedConfig,
      );

      expect(result.exito, isTrue);
      expect(result.datos?['ack_status'], 'completed');
      expect(
        (await MerkaAgentStore.instance.pendingAcks()).single.status,
        'completed',
      );
      expect(
        int.parse(MerkaAgentContract.agentVersion.split('.').first),
        greaterThanOrEqualTo(3),
      );
      expect(
        MerkaAgentContract.phaseOneCapabilities,
        containsAll(['aplicar_configuracion', 'aplicar_feature_flags']),
      );
    },
  );

  test('entrar_mantenimiento activa modo visible y bloqueo operativo', () async {
    final maintenance = AgentMaintenanceService(clock: () => clock);

    final result = await maintenance.enterMaintenance({
      'message':
          r'Mantenimiento preventivo token=secret admin@empresa.test C:\Users\Ana\log.txt',
    });

    expect(result['maintenance_mode'], isTrue);
    expect(result['operations_blocked'], isTrue);
    expect(await MaintenanceService.instance.isMaintenanceMode(), isTrue);
    expect(await DatabaseHelper.instance.operacionBloqueadaPorCierre(), isTrue);
    final message = await MaintenanceService.instance.getMaintenanceMessage();
    expect(message, contains('token=<redacted>'));
    expect(message, isNot(contains('secret')));
    expect(message, isNot(contains('admin@empresa.test')));
    expect(message, isNot(contains('Ana')));
  });

  test(
    'salir_mantenimiento desactiva modo visible y bloqueo operativo',
    () async {
      final maintenance = AgentMaintenanceService(clock: () => clock);
      await maintenance.enterMaintenance(const {'message': 'Ventana tecnica'});

      final result = await maintenance.exitMaintenance(const {});

      expect(result['maintenance_mode'], isFalse);
      expect(result['operations_blocked'], isFalse);
      expect(await MaintenanceService.instance.isMaintenanceMode(), isFalse);
      expect(
        await DatabaseHelper.instance.operacionBloqueadaPorCierre(),
        isFalse,
      );
    },
  );

  test('mantenimiento rechaza parametros no permitidos', () async {
    final maintenance = AgentMaintenanceService(clock: () => clock);

    await expectLater(
      maintenance.enterMaintenance(const {
        'message': 'ok',
        'shell': 'powershell Stop-Process',
      }),
      throwsA(
        isA<AgentMaintenanceRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_MAINTENANCE_PARAMETER',
        ),
      ),
    );

    await expectLater(
      maintenance.exitMaintenance(const {'path': r'C:\db.sqlite'}),
      throwsA(
        isA<AgentMaintenanceRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_MAINTENANCE_PARAMETER',
        ),
      ),
    );
  });

  test(
    'comando firmado entra y sale de mantenimiento con ACK durable',
    () async {
      final maintenance = AgentMaintenanceService(clock: () => clock);
      final now = DateTime.now().toUtc();

      final enter = _signedCommand(
        id: 'CMD-MAINT-ENTER-3C',
        nonce: 'NONCE-MAINT-ENTER-3C',
        action: TipoComando.entrar_mantenimiento,
        secret: commandSecret,
        installationId: installationId,
        now: now,
        params: const {'message': 'Mantenimiento remoto firmado'},
      );
      final enterResult = await CCCommandsProcessor.instance.procesarComando(
        enter,
        maintenanceService: maintenance,
      );

      final exit = _signedCommand(
        id: 'CMD-MAINT-EXIT-3C',
        nonce: 'NONCE-MAINT-EXIT-3C',
        action: TipoComando.salir_mantenimiento,
        secret: commandSecret,
        installationId: installationId,
        now: now,
        params: const {},
      );
      final exitResult = await CCCommandsProcessor.instance.procesarComando(
        exit,
        maintenanceService: maintenance,
      );

      expect(enterResult.exito, isTrue);
      expect(exitResult.exito, isTrue);
      expect(
        await DatabaseHelper.instance.operacionBloqueadaPorCierre(),
        isFalse,
      );
      final acks = await MerkaAgentStore.instance.pendingAcks();
      expect(acks.map((ack) => ack.status), everyElement('completed'));
      expect(
        MerkaAgentContract.phaseOneCapabilities,
        containsAll(['entrar_mantenimiento', 'salir_mantenimiento']),
      );
    },
  );

  test(
    'forzar_sincronizacion ejecuta el motor local sin payload remoto',
    () async {
      var refreshed = false;
      var synced = false;
      final lastSync = clock.subtract(const Duration(minutes: 1));
      final sync = AgentSyncService(
        refreshSession: () async => refreshed = true,
        syncRunner: () async => synced = true,
        statusProvider: () => SyncStatus.idle,
        lastSyncProvider: () => lastSync,
        clock: () => clock,
      );

      final result = await sync.forceSync(const {'request_id': '77'});

      expect(refreshed, isTrue);
      expect(synced, isTrue);
      expect(result['status'], 'idle');
      expect(result['last_sync_at'], lastSync.toIso8601String());
      expect(result['remote_payload_applied'], isFalse);
      expect(result['idempotent_queue'], isTrue);
    },
  );

  test('forzar_sincronizacion rechaza parametros libres', () async {
    final sync = AgentSyncService(
      refreshSession: () async {},
      syncRunner: () async {},
      statusProvider: () => SyncStatus.idle,
      lastSyncProvider: () => clock,
      clock: () => clock,
    );

    await expectLater(
      sync.forceSync(const {'table': 'ventas', 'sql': 'SELECT * FROM ventas'}),
      throwsA(
        isA<AgentSyncRequestException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_SYNC_PARAMETER',
        ),
      ),
    );
  });

  test('forzar_sincronizacion reporta offline como recuperable', () async {
    final sync = AgentSyncService(
      refreshSession: () async {},
      syncRunner: () async {},
      statusProvider: () => SyncStatus.offline,
      lastSyncProvider: () => null,
      clock: () => clock,
    );

    await expectLater(
      sync.forceSync(const {}),
      throwsA(
        isA<AgentSyncExecutionException>().having(
          (error) => error.code,
          'code',
          'SYNC_NOT_COMPLETED',
        ),
      ),
    );
  });

  test('comando firmado fuerza sincronizacion y persiste ACK', () async {
    final now = DateTime.now().toUtc();
    final sync = AgentSyncService(
      refreshSession: () async {},
      syncRunner: () async {},
      statusProvider: () => SyncStatus.idle,
      lastSyncProvider: () => clock,
      clock: () => clock,
    );
    final command = _signedCommand(
      id: 'CMD-SYNC-3C',
      nonce: 'NONCE-SYNC-3C',
      action: TipoComando.forzar_sincronizacion,
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: const {},
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      syncService: sync,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      contains('forzar_sincronizacion'),
    );
  });

  test(
    'reconstruir_indices ejecuta solo mantenimiento SQLite registrado',
    () async {
      final repair = AgentRepairService(
        databaseProvider: () => DatabaseHelper.instance.database,
        clearCache: () async {},
        cleanExpiredCache: () async {},
        cacheStats: () => const {'total_entries': 0},
        clock: () => clock,
      );

      final result = await repair.rebuildIndexes(const {'request_id': '88'});

      expect(result['repair_code'], 'reconstruir_indices');
      expect(result['steps'], ['REINDEX', 'ANALYZE', 'PRAGMA optimize']);
      expect(result['business_rows_modified'], isFalse);
    },
  );

  test('limpiar_cache solo limpia cache regenerable', () async {
    var clearCalls = 0;
    var expiredCalls = 0;
    final repair = AgentRepairService(
      databaseProvider: () => DatabaseHelper.instance.database,
      clearCache: () async => clearCalls++,
      cleanExpiredCache: () async => expiredCalls++,
      cacheStats: () => {'total_entries': clearCalls == 0 ? 3 : 0},
      clock: () => clock,
    );

    final all = await repair.clearCaches(const {'scope': 'all_regenerable'});
    final expired = await repair.clearCaches(const {'scope': 'expired'});

    expect(all['repair_code'], 'clear_cache');
    expect(all['business_rows_modified'], isFalse);
    expect(expired['scope'], 'expired');
    expect(clearCalls, 1);
    expect(expiredCalls, 1);
  });

  test(
    'ejecutar_reparacion rechaza codigos y parametros no registrados',
    () async {
      final repair = AgentRepairService(
        databaseProvider: () => DatabaseHelper.instance.database,
        clearCache: () async {},
        cleanExpiredCache: () async {},
        cacheStats: () => const {'total_entries': 0},
        clock: () => clock,
      );

      await expectLater(
        repair.runSafeRepair(const {'repair_code': 'drop_database'}),
        throwsA(
          isA<AgentRepairRequestException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_SAFE_REPAIR',
          ),
        ),
      );

      await expectLater(
        repair.rebuildIndexes(const {'sql': 'REINDEX'}),
        throwsA(
          isA<AgentRepairRequestException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_REPAIR_PARAMETER',
          ),
        ),
      );
    },
  );

  test('comando firmado ejecuta reparacion segura y persiste ACK', () async {
    final now = DateTime.now().toUtc();
    var clearCalls = 0;
    final repair = AgentRepairService(
      databaseProvider: () => DatabaseHelper.instance.database,
      clearCache: () async => clearCalls++,
      cleanExpiredCache: () async {},
      cacheStats: () => {'total_entries': clearCalls == 0 ? 1 : 0},
      clock: () => clock,
    );
    final command = _signedCommand(
      id: 'CMD-REPAIR-3C',
      nonce: 'NONCE-REPAIR-3C',
      action: TipoComando.ejecutar_reparacion,
      secret: commandSecret,
      installationId: installationId,
      now: now,
      params: const {'repair_code': 'clear_cache'},
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      repairService: repair,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['ack_status'], 'completed');
    expect(result.datos?['repair_code'], 'clear_cache');
    expect(clearCalls, 1);
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      containsAll([
        'reconstruir_indices',
        'limpiar_cache',
        'ejecutar_reparacion',
      ]),
    );
  });
}

ComandoRemoto _signedCommand({
  required String id,
  required String nonce,
  required TipoComando action,
  required String secret,
  required String installationId,
  required DateTime now,
  required Map<String, dynamic> params,
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
