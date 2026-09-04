import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:sqflite/sqflite.dart';

import 'agent/agent_contract.dart';
import 'agent/agent_store.dart';
import 'db_helper.dart';
import 'core/app/app_version.dart';
import 'licensing/domain/product_family.dart';
import 'services/licencia_service.dart';
import 'services/update_service.dart';
import 'services/health_reporter.dart';
import 'services/cc_commands_processor.dart';
import 'services/hardware_fingerprint_service.dart';
import 'services/control_center_endpoint.dart';
import 'services/control_center_license_client.dart';
import 'services/license_validation_service.dart';

class ControlCenterAgent {
  const ControlCenterAgent._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const defaultEndpoint = ControlCenterEndpoint.defaultEndpoint;
  static Timer? _telemetryTimer;
  static Timer? _commandTimer;
  static bool _started = false;
  static bool _heartbeatInFlight = false;
  static bool _pollInFlight = false;
  static bool _licenseReconciliationInFlight = false;
  static _ControlCenterLifecycleObserver? _lifecycleObserver;

  static void startBackground() {
    if (_started) return;
    _started = true;
    _lifecycleObserver ??= _ControlCenterLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    unawaited(
      _initializeBackground().catchError((Object error, StackTrace stackTrace) {
        _started = false;
        debugPrint('Control Center Agent no pudo iniciar: $error');
      }),
    );
  }

  static Future<void> _initializeBackground() async {
    // Configurar endpoint por defecto si no está configurado
    await _configureDefaultEndpoint();
    await MerkaAgentStore.instance.initialize();

    // Iniciar health reporter
    HealthReporter.instance.iniciar();

    await reconcileLicenseState();
    await _bootstrapAndPublishCapabilities();
    await _flushPendingAcks();
    await _flushPendingTelemetry();
    await _flushPendingErrors();
    await sendStartupHeartbeat(reconcileLicense: false);
    await pollRemoteCommands();

    // Enviar heartbeat cada 5 minutos
    _telemetryTimer?.cancel();
    _commandTimer?.cancel();
    _telemetryTimer = Timer.periodic(
      MerkaAgentContract.heartbeatInterval,
      (_) => sendStartupHeartbeat(),
    );
    _commandTimer = Timer.periodic(
      MerkaAgentContract.pollInterval,
      (_) => pollRemoteCommands(),
    );
  }

  static Future<void> stopBackground({bool sendFinalHeartbeat = true}) async {
    if (!_started) return;
    _started = false;
    _telemetryTimer?.cancel();
    _commandTimer?.cancel();
    _telemetryTimer = null;
    _commandTimer = null;
    if (sendFinalHeartbeat) {
      await sendStartupHeartbeat(finalHeartbeat: true);
      await _flushPendingAcks();
      await _flushPendingErrors();
    }
    HealthReporter.instance.detener();
    final observer = _lifecycleObserver;
    if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    _lifecycleObserver = null;
  }

  static Future<void> _configureDefaultEndpoint() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['control_center_endpoint'],
        limit: 1,
      );

      if (rows.isEmpty) {
        // Configurar endpoint por defecto si no existe
        await db.insert('app_config', {
          'clave': 'control_center_endpoint',
          'valor': defaultEndpoint,
        });
      } else {
        final val = rows.first['valor']?.toString();
        if (val == 'http://localhost:3000' ||
            val == 'http://localhost:8787' ||
            val == 'http://127.0.0.1:8787') {
          await db.update(
            'app_config',
            {'valor': defaultEndpoint},
            where: 'clave = ?',
            whereArgs: ['control_center_endpoint'],
          );
        }
      }
    } catch (error) {
      debugPrint('Error al configurar endpoint por defecto: $error');
    }
  }

  static Future<void> sendStartupHeartbeat({
    bool finalHeartbeat = false,
    bool reconcileLicense = true,
  }) async {
    if (_heartbeatInFlight) return;
    _heartbeatInFlight = true;
    Map<String, Object?>? payload;
    try {
      if (reconcileLicense && !finalHeartbeat) {
        final licenseState = await reconcileLicenseState();
        if (licenseState != null && !licenseState.allowsOperation) return;
        if (licenseState?.requiresSignedRefresh == true) {
          await pollRemoteCommands();
        }
      }
      final endpoint = await _endpoint();
      payload = await _heartbeatPayload();
      if (finalHeartbeat) payload['online'] = false;
      debugPrint('Control Center: Enviando heartbeat a $endpoint');
      final token =
          (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
      if (token == null || token.isEmpty) {
        throw StateError('No hay token de licencia para autenticar heartbeat');
      }
      await ControlCenterLicenseClient(
        endpoint: endpoint,
      ).heartbeat(payload, authorizationToken: token);
      debugPrint('Control Center: Heartbeat enviado exitosamente');
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CONTROL_CENTER_HEARTBEAT',
        entidad: 'control_center',
        detalle: endpoint,
      );
      await _flushPendingErrors(
        client: ControlCenterLicenseClient(endpoint: endpoint),
        token: token,
      );
    } catch (error) {
      debugPrint('Control Center heartbeat skipped: $error');
      if (payload != null) {
        await MerkaAgentStore.instance.enqueueTelemetry('heartbeat', payload);
      }
    } finally {
      _heartbeatInFlight = false;
    }
  }

  static Future<LicenseReconciliationResult?> reconcileLicenseState({
    ControlCenterLicenseClient? client,
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
  }) async {
    if (_licenseReconciliationInFlight) return null;
    _licenseReconciliationInFlight = true;
    try {
      final effectiveClient =
          client ?? ControlCenterLicenseClient(endpoint: await _endpoint());
      return await LicenciaService.instance.reconciliarEstadoOperativo(
        client: effectiveClient,
        validationService: validationService,
        fingerprintService: fingerprintService,
        currentHardwareFingerprint: currentHardwareFingerprint,
        now: now,
      );
    } catch (error) {
      debugPrint('Control Center license reconciliation skipped: $error');
      return null;
    } finally {
      _licenseReconciliationInFlight = false;
    }
  }

  static Future<void> reportEvent({
    required String event,
    required String module,
    String severity = 'info',
  }) async {
    try {
      final endpoint = await _endpoint();
      final token =
          (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
      if (token == null || token.isEmpty) return;
      await _postJson(Uri.parse('$endpoint/api/v1/telemetry/events'), {
        'event': event,
        'module': module,
        'severity': severity,
        'version': AppVersion.display,
        'installation_id': await _installationId(),
      }, bearerToken: token);
    } catch (error) {
      debugPrint('Control Center telemetry skipped: $error');
    }
  }

  static Future<void> pollRemoteCommands() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final endpoint = await _endpoint();
      final installationId = await _installationId();
      final licenseToken =
          (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
      if (licenseToken == null || licenseToken.isEmpty) return;
      final client = ControlCenterLicenseClient(endpoint: endpoint);
      await _flushPendingAcks(client: client, token: licenseToken);
      await _flushPendingErrors(client: client, token: licenseToken);
      final commands = await client.commands(
        installationId,
        authorizationToken: licenseToken,
      );
      for (final command in commands) {
        await _executeRemoteCommand(command);
        await _flushPendingAcks(client: client, token: licenseToken);
      }
    } catch (error) {
      debugPrint('Control Center command polling skipped: $error');
    } finally {
      _pollInFlight = false;
    }
  }

  static Future<void> _bootstrapAndPublishCapabilities() async {
    try {
      final token =
          (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
      if (token == null || token.isEmpty) return;
      final client = ControlCenterLicenseClient(endpoint: await _endpoint());
      final bootstrap = await client.bootstrap(authorizationToken: token);
      await MerkaAgentStore.instance.writeState(
        'bootstrap_v2',
        jsonEncode(bootstrap),
      );
      await client.publishCapabilities(
        capabilities: MerkaAgentContract.phaseOneCapabilities,
        agentVersion: MerkaAgentContract.agentVersion,
        architecture: await _architecture(),
        authorizationToken: token,
      );
    } catch (error) {
      debugPrint('Control Center bootstrap skipped: $error');
    }
  }

  static Future<void> _flushPendingAcks({
    ControlCenterLicenseClient? client,
    String? token,
  }) async {
    final effectiveToken =
        token ??
        (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
    if (effectiveToken == null || effectiveToken.isEmpty) return;
    final effectiveClient =
        client ?? ControlCenterLicenseClient(endpoint: await _endpoint());
    for (final ack in await MerkaAgentStore.instance.pendingAcks()) {
      try {
        await effectiveClient.ackCommand(
          commandId: ack.commandId,
          installationId: ack.installationId,
          status: ack.status,
          message: ack.message,
          result: ack.result,
          authorizationToken: effectiveToken,
        );
        await MerkaAgentStore.instance.markAckDelivered(ack.commandId);
      } on HttpException catch (error) {
        // Una respuesta perdida puede dejar el ACK confirmado en el servidor.
        // En ese caso un reintento devuelve 404 porque ya no está pendiente.
        if (error.message.contains('HTTP 404')) {
          await MerkaAgentStore.instance.markAckDelivered(ack.commandId);
          continue;
        }
        await MerkaAgentStore.instance.markAckAttemptFailed(ack.commandId);
        break;
      } catch (_) {
        await MerkaAgentStore.instance.markAckAttemptFailed(ack.commandId);
        break;
      }
    }
  }

  static Future<void> _flushPendingTelemetry() async {
    final token =
        (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
    if (token == null || token.isEmpty) return;
    final client = ControlCenterLicenseClient(endpoint: await _endpoint());
    for (final event in await MerkaAgentStore.instance.pendingTelemetry()) {
      try {
        if (event.eventType != 'heartbeat') {
          // Los demás tipos tendrán su endpoint dedicado en la fase 3.
          break;
        }
        await client.heartbeat(event.payload, authorizationToken: token);
        await MerkaAgentStore.instance.markTelemetryDelivered(event.id);
      } catch (_) {
        await MerkaAgentStore.instance.markTelemetryAttemptFailed(event.id);
        break;
      }
    }
  }

  @visibleForTesting
  static Future<void> flushPendingErrorsForTests({
    required ControlCenterLicenseClient client,
    required String token,
  }) => _flushPendingErrors(client: client, token: token);

  static Future<void> _flushPendingErrors({
    ControlCenterLicenseClient? client,
    String? token,
  }) async {
    final effectiveToken =
        token ??
        (await LicenciaService.instance.obtenerLicencia())?.offlineToken;
    if (effectiveToken == null || effectiveToken.isEmpty) return;
    final effectiveClient =
        client ?? ControlCenterLicenseClient(endpoint: await _endpoint());
    for (final error in await MerkaAgentStore.instance.pendingErrors()) {
      try {
        await effectiveClient.reportError(
          authorizationToken: effectiveToken,
          payload: error.payload,
        );
        await MerkaAgentStore.instance.markErrorDelivered(error.id);
      } catch (_) {
        await MerkaAgentStore.instance.markErrorAttemptFailed(error.id);
        break;
      }
    }
  }

  @visibleForTesting
  static Future<ResultadoComando> processCommandForTests(
    Map<String, Object?> command,
  ) {
    return _executeRemoteCommand(command);
  }

  static Future<String> _endpoint() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['control_center_endpoint'],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.first['valor']?.toString().trim();
    return ControlCenterEndpoint.normalize(value ?? defaultEndpoint);
  }

  static Future<String?> _authToken() async =>
      (await LicenciaService.instance.obtenerLicencia())?.offlineToken;

  static Future<Map<String, Object?>> _heartbeatPayload() async {
    final db = await DatabaseHelper.instance.database;
    final company = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final sw = Stopwatch()..start();
    await db.rawQuery('SELECT 1');
    sw.stop();

    // Obtener métricas de salud del HealthReporter
    final healthMetrics = await HealthReporter.instance.recolectarMetricas();

    // Obtener información de licencia
    final licencia = await LicenciaService.instance.obtenerLicencia();

    // Obtener hardware fingerprint para validación dual
    final hardwareFingerprint = await HardwareFingerprintService()
        .generateFingerprint();

    final syncRows = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM sqlite_master WHERE type = 'table' AND name = 'sync_outbox'",
    );
    var syncStatus = 'not_configured';
    if (((syncRows.first['total'] as num?)?.toInt() ?? 0) > 0) {
      final pending = await db.rawQuery(
        "SELECT COUNT(*) AS total FROM sync_outbox WHERE status IN ('pending', 'failed')",
      );
      syncStatus = (((pending.first['total'] as num?)?.toInt() ?? 0) == 0)
          ? 'ok'
          : 'pending';
    }

    // Verificar si hay actualización disponible
    final actualizacionDisponible = await UpdateService.instance
        .buscarActualizacion();

    return {
      'installationId': await _installationId(),
      'hardwareFingerprint': hardwareFingerprint,
      'companyName': company['nombre']?.toString() ?? 'MerkaERP local',
      'taxId': company['nit']?.toString() ?? '',
      'version': AppVersion.version,
      'appBuildNumber': AppVersion.build.toString(),
      'agentVersion': MerkaAgentContract.agentVersion,
      'capabilities': MerkaAgentContract.phaseOneCapabilities,
      'os': Platform.operatingSystem,
      'architecture': await _architecture(),
      'device': Platform.localHostname,
      'memoryMb': await _totalMemoryMb() ?? healthMetrics.memoryRssMb,
      'freeDiskMb': await _freeDiskMb(),
      'dbSchemaVersion': DatabaseHelper.schemaVersion.toString(),
      'pendingMigrations': 0,
      'licenseStatus': licencia?.estado.name ?? 'local',
      'licensePlan': licencia?.plan.name ?? 'unknown',
      'licenseId': licencia?.uuid,
      'edition': licencia?.productFamily.storageValue,
      'licenseExpiry': licencia?.fechaExpiracion.toIso8601String(),
      'licenseType': licencia?.tipoLicencia.name ?? 'SUSCRIPCION',
      'syncStatus': syncStatus,
      'databaseStatus': 'ok',
      'lastBackupAt': healthMetrics.ultimoRespaldo?.toIso8601String(),
      'criticalErrors': healthMetrics.erroresCriticos,
      'updateAvailable': actualizacionDisponible != null,
      'updateVersion': actualizacionDisponible?.version,
      'metrics': {
        'dbResponseMs': healthMetrics.dbResponseMs,
        'memoryRssMb': healthMetrics.memoryRssMb,
        'dbSizeMb': healthMetrics.dbSizeMb,
        'lastBackup': healthMetrics.ultimoRespaldo?.toIso8601String(),
        'heartbeatOk': healthMetrics.heartbeatOk,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
  }

  static Future<String> _installationId() async {
    final signedInstallationId = await LicenciaService.instance
        .reconciliarIdentidadInstalacionFirmada();
    if (signedInstallationId != null && signedInstallationId.isNotEmpty) {
      return signedInstallationId;
    }

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['control_center_installation_id'],
      limit: 1,
    );

    if (rows.isNotEmpty && rows.first['valor']?.toString().isNotEmpty == true) {
      return rows.first['valor']!.toString();
    }

    final fallbackId = const Uuid().v4();

    await db.insert('app_config', {
      'clave': 'control_center_installation_id',
      'valor': fallbackId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return fallbackId;
  }

  @visibleForTesting
  static Future<String> installationIdForTests() => _installationId();

  static Future<void> _postJson(
    Uri uri,
    Map<String, Object?> payload, {
    String? bearerToken,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final authToken = bearerToken ?? await _authToken();
      if (authToken != null && authToken.isNotEmpty) {
        request.headers.add('Authorization', 'Bearer $authToken');
      }

      request.write(jsonEncode(payload));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
    } finally {
      client.close(force: true);
    }
  }

  // ignore: unused_element — método pendiente de conectar a API de sincronización
  static Future<List<Map<String, Object?>>> _getJsonList(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(uri);

      // Agregar token de autenticación si existe
      final authToken = await _authToken();
      if (authToken != null) {
        request.headers.add('Authorization', 'Bearer $authToken');
      }

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == 404) return const [];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(body);
      final list = decoded is Map ? decoded['commands'] : decoded;
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) item.cast<String, Object?>(),
      ];
    } finally {
      client.close(force: true);
    }
  }

  static Future<ResultadoComando> _executeRemoteCommand(
    Map<String, Object?> command,
  ) async {
    final action = command['action']?.toString() ?? '';

    try {
      final comandoRemoto = ComandoRemoto.fromJson(
        command.cast<String, dynamic>(),
      );

      final resultado = await CCCommandsProcessor.instance.procesarComando(
        comandoRemoto,
      );
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: resultado.exito
            ? 'CONTROL_CENTER_COMMAND_${action}_SUCCESS'
            : 'CONTROL_CENTER_COMMAND_${action}_REJECTED',
        entidad: 'control_center',
        detalle: resultado.mensaje,
      );
      return resultado;
    } catch (e) {
      final id = command['id']?.toString() ?? '';
      final installationId =
          (command['installation_id'] ?? command['installationId'])
              ?.toString() ??
          '';
      if (id.isNotEmpty && installationId.isNotEmpty) {
        await MerkaAgentStore.instance.queueRejectedAck(
          commandId: id,
          installationId: installationId,
          message: 'Comando remoto inválido o no permitido',
          result: const {
            'error_code': 'REMOTE_ACTION_NOT_ALLOWED',
            'ack_status': 'rejected',
          },
        );
      }
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CONTROL_CENTER_COMMAND_INVALID',
        entidad: 'control_center',
        detalle: '$action: $e',
      );
      return ResultadoComando(
        exito: false,
        mensaje: 'Comando remoto inválido: $e',
        datos: const {'ack_status': 'rejected'},
      );
    }
  }

  static Future<ResultadoComando> handleRemoteAccessConsent(
    Map<String, Object?> command,
  ) async {
    final context = navigatorKey.currentContext;
    bool approved = false;

    if (context != null && context.mounted) {
      approved =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.display_settings, color: MerkaThemeTokens.info),
                  SizedBox(width: 8),
                  Text('MERKA solicita acceso remoto'),
                ],
              ),
              content: const Text(
                'El equipo de soporte de Control Center solicita acceso remoto a este equipo para asistencia técnica.\n\n'
                'Nota: Aprobar esta solicitud registrará su consentimiento. No se iniciará captura de pantalla ni transmisión en vivo (Stub pendiente de la Fase RA).',
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Rechazar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aprobar'),
                ),
              ],
            ),
          ) ??
          false;
    } else {
      await _registrarSolicitudAccesoRemotoStub(command);
      return const ResultadoComando(
        exito: true,
        mensaje:
            'Solicitud de acceso remoto registrada como stub sin UI activa (Fase RA pendiente).',
        datos: {'ack_status': 'done'},
      );
    }

    await _registrarSolicitudAccesoRemotoStub(
      command,
      consentimientoOtorgado: approved,
    );

    return ResultadoComando(
      exito: true,
      mensaje: approved
          ? 'Consentimiento otorgado por el usuario. Stub de acceso remoto (Fase RA pendiente, sin streaming real).'
          : 'Consentimiento denegado por el usuario.',
      datos: {'ack_status': approved ? 'approved' : 'rejected'},
    );
  }

  static Future<void> _registrarSolicitudAccesoRemotoStub(
    Map<String, Object?> command, {
    bool? consentimientoOtorgado,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final detalleConsent = consentimientoOtorgado == null
        ? 'Stub pendiente Fase RA: no inicia captura ni streaming de pantalla.'
        : (consentimientoOtorgado
              ? 'Consentimiento OTORGADO por el usuario. Stub pendiente Fase RA: no inicia captura ni streaming.'
              : 'Consentimiento DENEGADO por el usuario.');

    await db.insert('notificaciones', {
      'company_id': companyId,
      'tipo': 'control_center',
      'prioridad': 'warning',
      'titulo': 'MERKA solicita acceso remoto',
      'detalle': detalleConsent,
      'entidad': 'remote_access_stub',
      'entidad_id': command['id']?.toString(),
      'leida': 0,
      'creada_en': DateTime.now().toIso8601String(),
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CONTROL_CENTER_REMOTE_ACCESS_STUB',
      entidad: 'control_center',
      detalle: '$detalleConsent | Command: ${jsonEncode(command)}',
    );
  }

  static Future<String> _architecture() async {
    final environmentArchitecture =
        Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        Platform.environment['PROCESSOR_ARCHITECTURE'];
    if (environmentArchitecture != null &&
        environmentArchitecture.trim().isNotEmpty) {
      return environmentArchitecture;
    }
    if (Platform.isAndroid) {
      try {
        final info = await HardwareFingerprintService().getHardwareInfo();
        final abis = info['supportedAbis'];
        if (abis is List && abis.isNotEmpty) return abis.first.toString();
      } catch (_) {}
    }
    return 'unknown';
  }

  static Future<int?> _totalMemoryMb() async {
    try {
      if (Platform.isWindows) {
        final info = await HardwareFingerprintService().getHardwareInfo();
        final memory = info['systemMemoryInMegabytes'];
        if (memory is num) return memory.toInt();
      }
      if (Platform.isAndroid || Platform.isLinux) {
        final memInfo = await File('/proc/meminfo').readAsLines();
        final total = memInfo.firstWhere(
          (line) => line.startsWith('MemTotal:'),
        );
        final kb = int.tryParse(total.replaceAll(RegExp(r'[^0-9]'), ''));
        if (kb != null) return (kb / 1024).round();
      }
    } catch (_) {}
    return null;
  }

  static Future<int?> _freeDiskMb() async {
    try {
      if (Platform.isWindows) {
        final root = Directory.current.absolute.path.substring(0, 3);
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '[int64]([IO.DriveInfo]::new(\'$root\').AvailableFreeSpace / 1MB)',
        ]).timeout(const Duration(seconds: 3));
        return result.exitCode == 0
            ? int.tryParse(result.stdout.toString().trim())
            : null;
      }
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('df', [
          '-Pk',
          Directory.current.absolute.path,
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode != 0) return null;
        final lines = const LineSplitter()
            .convert(result.stdout.toString())
            .where((line) => line.trim().isNotEmpty)
            .toList();
        if (lines.length < 2) return null;
        final columns = lines.last.trim().split(RegExp(r'\s+'));
        if (columns.length < 4) return null;
        final availableKb = int.tryParse(columns[3]);
        return availableKb == null ? null : (availableKb / 1024).round();
      }
    } catch (_) {}
    return null;
  }
}

final class _ControlCenterLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(ControlCenterAgent.stopBackground());
    }
  }
}
