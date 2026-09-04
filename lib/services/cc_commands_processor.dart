import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../agent/agent_backup_service.dart';
import '../agent/agent_contract.dart';
import '../agent/agent_data_sanitizer.dart';
import '../agent/agent_diagnostics_service.dart';
import '../agent/agent_error_reporter.dart';
import '../agent/agent_managed_config_service.dart';
import '../agent/agent_maintenance_service.dart';
import '../agent/agent_repair_service.dart';
import '../agent/agent_restart_service.dart';
import '../agent/agent_session_service.dart';
import '../agent/agent_store.dart';
import '../agent/agent_support_service.dart';
import '../agent/agent_sync_service.dart';
import '../agent/agent_update_service.dart';
import '../control_center_agent.dart';
import '../db_helper.dart';
import 'licencia_service.dart';
import 'control_center_secret_store.dart';
import 'hardware_fingerprint_service.dart';
import 'license_validation_service.dart';

enum TipoComando {
  forzar_respaldo,
  restaurar_respaldo,
  reiniciar_sesiones,
  reiniciar,
  bloquear_instalacion,
  activar_instalacion,
  entrar_mantenimiento,
  salir_mantenimiento,
  forzar_actualizacion,
  rollback_actualizacion,
  aplicar_hotfix,
  actualizar_modulos,
  actualizar_licencia,
  aplicar_configuracion,
  aplicar_feature_flags,
  forzar_sincronizacion,
  run_diagnostics,
  verificar_base_datos,
  reconstruir_indices,
  limpiar_cache,
  ejecutar_reparacion,
  enviar_log,
  collect_diagnostics,
  mensaje_admin,
  solicitar_acceso_remoto,
}

enum EstadoComando { pendiente, procesando, completado, fallido }

class ComandoRemoto {
  const ComandoRemoto({
    required this.id,
    required this.tipo,
    required this.parametros,
    required this.timestamp,
    required this.installationId,
    required this.expiresAt,
    required this.nonce,
    this.timestampRaw,
    this.expiresAtRaw,
    this.firmaHmac,
    this.estado = EstadoComando.pendiente,
    this.resultado,
    this.error,
  });

  final String id;
  final TipoComando tipo;
  final Map<String, dynamic> parametros;
  final DateTime timestamp;
  final String installationId;
  final DateTime expiresAt;
  final String nonce;
  final String? timestampRaw;
  final String? expiresAtRaw;
  final String? firmaHmac;
  final EstadoComando estado;
  final Map<String, dynamic>? resultado;
  final String? error;

  String get _timestampForSignature =>
      timestampRaw ?? timestamp.toUtc().toIso8601String();
  String get _expiresForSignature =>
      expiresAtRaw ?? expiresAt.toUtc().toIso8601String();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': tipo.name,
      'parametros': parametros,
      'timestamp': _timestampForSignature,
      'installation_id': installationId,
      'expires_at': _expiresForSignature,
      'nonce': nonce,
      'firma_hmac': firmaHmac,
      'estado': estado.name,
      'resultado': resultado,
      'error': error,
    };
  }

  static ComandoRemoto fromJson(Map<String, dynamic> json) {
    final action = (json['action'] ?? json['tipo'])?.toString() ?? '';
    if (!MerkaAgentContract.allowedActions.contains(action)) {
      throw FormatException('Remote action not allowed: $action');
    }
    final timestampText =
        (json['timestamp'] ?? json['created_at'])?.toString() ?? '';
    final expiresText = json['expires_at']?.toString() ?? '';
    return ComandoRemoto(
      id: json['id']?.toString() ?? '',
      tipo: TipoComando.values.firstWhere((e) => e.name == action),
      parametros:
          ((json['params'] ?? json['parametros']) as Map?)
              ?.cast<String, dynamic>() ??
          <String, dynamic>{},
      timestamp:
          DateTime.tryParse(timestampText)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      installationId:
          (json['installation_id'] ?? json['installationId'])?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(expiresText)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      nonce: json['nonce']?.toString() ?? '',
      timestampRaw: timestampText,
      expiresAtRaw: expiresText,
      firmaHmac: (json['signature'] ?? json['firma_hmac'])?.toString(),
      estado: EstadoComando.values.firstWhere(
        (e) => e.name == json['estado'],
        orElse: () => EstadoComando.pendiente,
      ),
      resultado: (json['resultado'] as Map?)?.cast<String, dynamic>(),
      error: json['error']?.toString(),
    );
  }

  String _generarPayloadParaFirma() {
    return MerkaAgentContract.canonicalCommandPayload(
      id: id,
      action: tipo.name,
      installationId: installationId,
      timestamp: _timestampForSignature,
      expiresAt: _expiresForSignature,
      nonce: nonce,
      params: parametros,
    );
  }

  bool validarFirma(String secretKey) {
    final firma = firmaHmac;
    if (firma == null || firma.isEmpty || secretKey.isEmpty) return false;
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final expected = hmac
        .convert(utf8.encode(_generarPayloadParaFirma()))
        .toString();
    if (expected.length != firma.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ firma.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class ResultadoComando {
  const ResultadoComando({
    required this.exito,
    required this.mensaje,
    this.datos,
  });

  final bool exito;
  final String mensaje;
  final Map<String, dynamic>? datos;

  Map<String, dynamic> toJson() {
    return {'exito': exito, 'mensaje': mensaje, 'datos': datos};
  }
}

class CCCommandsProcessor {
  CCCommandsProcessor._();

  static final CCCommandsProcessor instance = CCCommandsProcessor._();

  Future<String?> _obtenerSecretHmac() =>
      ControlCenterSecretStore.instance.readCommandSecret();

  Future<void> configurarSecretHmac(String secret) async {
    await ControlCenterSecretStore.instance.writeCommandSecret(secret);

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_HMAC_SECRET_CONFIGURADO',
      entidad: 'control_center',
      detalle: 'Secreto HMAC almacenado en el almacén seguro del sistema',
    );
  }

  Future<bool> validarComando(ComandoRemoto comando) async {
    final secret = await _obtenerSecretHmac();
    if (secret == null || secret.isEmpty) return false;
    if (comando.firmaHmac == null || comando.firmaHmac!.isEmpty) return false;
    if (comando.id.isEmpty ||
        comando.installationId.isEmpty ||
        comando.nonce.isEmpty) {
      return false;
    }

    final now = DateTime.now().toUtc();
    if (!comando.expiresAt.isAfter(now)) return false;
    if (comando.timestamp.isAfter(now.add(const Duration(minutes: 2)))) {
      return false;
    }
    if (comando.timestamp.isBefore(now.subtract(const Duration(minutes: 15)))) {
      return false;
    }

    final licencia = await LicenciaService.instance.obtenerLicencia();
    final localInstallationId = licencia?.installationId;
    if (localInstallationId == null ||
        localInstallationId != comando.installationId) {
      return false;
    }
    return comando.validarFirma(secret);
  }

  Future<ResultadoComando> procesarComando(
    ComandoRemoto comando, {
    LicenseValidationService? licenseValidationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
    AgentDiagnosticsService? diagnosticsService,
    AgentSupportService? supportService,
    AgentManagedConfigService? managedConfigService,
    AgentMaintenanceService? maintenanceService,
    AgentSyncService? syncService,
    AgentRepairService? repairService,
    AgentBackupService? backupService,
    AgentUpdateService? updateService,
    AgentSessionService? sessionService,
    AgentRestartService? restartService,
  }) async {
    if (!await validarComando(comando)) {
      const result = ResultadoComando(
        exito: false,
        mensaje:
            'Comando remoto rechazado: firma, expiración, instalación o nonce inválido',
        datos: {
          'ack_status': 'rejected',
          'error_code': 'INVALID_COMMAND_SIGNATURE',
        },
      );
      await MerkaAgentStore.instance.queueRejectedAck(
        commandId: comando.id,
        installationId: comando.installationId,
        message: result.mensaje,
        result: result.datos!,
      );
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'INVALID_COMMAND_SIGNATURE',
        entidad: 'control_center',
        detalle: '${comando.tipo.name}:${comando.id}',
      );
      return result;
    }

    final claim = await MerkaAgentStore.instance.claimCommand(
      commandId: comando.id,
      nonce: comando.nonce,
      action: comando.tipo.name,
      installationId: comando.installationId,
    );
    if (claim.state == AgentCommandClaimState.cached) {
      final stored = claim.stored!;
      return ResultadoComando(
        exito: stored.success == true,
        mensaje: stored.message,
        datos: stored.result,
      );
    }
    if (claim.state == AgentCommandClaimState.replay) {
      const result = ResultadoComando(
        exito: false,
        mensaje: 'Comando remoto rechazado por replay de command_id o nonce',
        datos: {'ack_status': 'rejected', 'error_code': 'COMMAND_REPLAY'},
      );
      await MerkaAgentStore.instance.queueRejectedAck(
        commandId: comando.id,
        installationId: comando.installationId,
        message: result.mensaje,
        result: result.datos!,
      );
      return result;
    }
    if (claim.state == AgentCommandClaimState.inFlight) {
      const result = ResultadoComando(
        exito: false,
        mensaje:
            'El comando quedó en ejecución durante un cierre anterior; no se repetirá automáticamente',
        datos: {
          'ack_status': 'failed',
          'error_code': 'COMMAND_OUTCOME_UNKNOWN',
          'recoverable': true,
        },
      );
      await MerkaAgentStore.instance.completeCommand(
        commandId: comando.id,
        installationId: comando.installationId,
        success: false,
        message: result.mensaje,
        result: result.datos!,
        ackStatus: 'failed',
      );
      return result;
    }

    late ResultadoComando result;
    try {
      switch (comando.tipo) {
        case TipoComando.forzar_respaldo:
          result = await _ejecutarForzarRespaldo(
            comando,
            backupService ?? AgentBackupService.instance,
          );
        case TipoComando.restaurar_respaldo:
          result = await _ejecutarRestaurarRespaldo(
            comando,
            backupService ?? AgentBackupService.instance,
          );
        case TipoComando.reiniciar_sesiones:
          result = await _ejecutarReiniciarSesiones(
            comando,
            sessionService ?? AgentSessionService.instance,
          );
        case TipoComando.entrar_mantenimiento:
          result = await _ejecutarEntrarMantenimiento(
            comando,
            maintenanceService ?? AgentMaintenanceService.instance,
          );
        case TipoComando.salir_mantenimiento:
          result = await _ejecutarSalirMantenimiento(
            comando,
            maintenanceService ?? AgentMaintenanceService.instance,
          );
        case TipoComando.actualizar_modulos:
          result = await _ejecutarActualizarLicenciaFirmada(
            comando,
            validationService: licenseValidationService,
            fingerprintService: fingerprintService,
            currentHardwareFingerprint: currentHardwareFingerprint,
            now: now,
          );
        case TipoComando.enviar_log:
          result = await _ejecutarEnviarLog(
            comando,
            supportService ?? AgentSupportService.instance,
          );
        case TipoComando.mensaje_admin:
          result = await _ejecutarMensajeAdmin(comando);
        case TipoComando.bloquear_instalacion:
          result = await _ejecutarBloquearInstalacion(comando);
        case TipoComando.activar_instalacion:
          result = await _ejecutarActivarInstalacion(comando);
        case TipoComando.forzar_actualizacion:
          result = await _ejecutarForzarActualizacion(
            comando,
            updateService ?? AgentUpdateService.instance,
          );
        case TipoComando.rollback_actualizacion:
          result = await _ejecutarRollbackActualizacion(
            comando,
            updateService ?? AgentUpdateService.instance,
          );
        case TipoComando.reiniciar:
          result = await _ejecutarReiniciar(
            comando,
            restartService ?? AgentRestartService.instance,
          );
        case TipoComando.forzar_sincronizacion:
          result = await _ejecutarForzarSincronizacion(
            comando,
            syncService ?? AgentSyncService.instance,
          );
        case TipoComando.aplicar_configuracion:
          result = await _ejecutarAplicarConfiguracion(
            comando,
            managedConfigService ?? AgentManagedConfigService.instance,
          );
        case TipoComando.aplicar_feature_flags:
          result = await _ejecutarAplicarFeatureFlags(
            comando,
            managedConfigService ?? AgentManagedConfigService.instance,
          );
        case TipoComando.actualizar_licencia:
          result = await _ejecutarActualizarLicenciaFirmada(
            comando,
            validationService: licenseValidationService,
            fingerprintService: fingerprintService,
            currentHardwareFingerprint: currentHardwareFingerprint,
            now: now,
          );
        case TipoComando.solicitar_acceso_remoto:
          result = await _ejecutarSolicitarAccesoRemoto(comando);
        case TipoComando.run_diagnostics:
          result = await _ejecutarDiagnostico(
            comando,
            diagnosticsService ?? AgentDiagnosticsService.instance,
          );
        case TipoComando.collect_diagnostics:
          result = await _ejecutarDiagnostico(
            comando,
            diagnosticsService ?? AgentDiagnosticsService.instance,
            supportService: supportService ?? AgentSupportService.instance,
          );
        case TipoComando.verificar_base_datos:
          result = await _ejecutarDiagnostico(
            comando,
            diagnosticsService ?? AgentDiagnosticsService.instance,
          );
        case TipoComando.reconstruir_indices:
          result = await _ejecutarReconstruirIndices(
            comando,
            repairService ?? AgentRepairService.instance,
          );
        case TipoComando.limpiar_cache:
          result = await _ejecutarLimpiarCache(
            comando,
            repairService ?? AgentRepairService.instance,
          );
        case TipoComando.ejecutar_reparacion:
          result = await _ejecutarReparacionSegura(
            comando,
            repairService ?? AgentRepairService.instance,
          );
        case TipoComando.aplicar_hotfix:
          result = await _ejecutarAplicarHotfix(
            comando,
            updateService ?? AgentUpdateService.instance,
          );
      }
    } catch (e, stackTrace) {
      final safeError = AgentDataSanitizer.sanitizeText(e.toString());
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CC_COMANDO_ERROR',
        entidad: 'control_center',
        detalle: '${comando.tipo.name}: $safeError',
      );
      await AgentErrorReporter.instance.queue(
        message: safeError,
        module: 'control_center_commands',
        stackTrace: stackTrace.toString(),
        context: {'action': comando.tipo.name, 'command_id': comando.id},
      );

      result = ResultadoComando(
        exito: false,
        mensaje: 'Error técnico al procesar el comando remoto',
        datos: const {'ack_status': 'failed', 'error_code': 'COMMAND_FAILED'},
      );
    }
    final data = result.datos ?? const <String, dynamic>{};
    final ackStatus =
        data['ack_status']?.toString() ??
        (result.exito ? 'completed' : 'failed');
    await MerkaAgentStore.instance.completeCommand(
      commandId: comando.id,
      installationId: comando.installationId,
      success: result.exito,
      message: result.mensaje,
      result: data,
      ackStatus: ackStatus,
    );
    return result;
  }

  Future<ResultadoComando> _ejecutarDiagnostico(
    ComandoRemoto comando,
    AgentDiagnosticsService service, {
    AgentSupportService? supportService,
  }) async {
    try {
      final diagnostic = switch (comando.tipo) {
        TipoComando.run_diagnostics => await service.runDiagnostics(
          comando.parametros,
        ),
        TipoComando.collect_diagnostics => await service.collectDiagnostics(
          comando.parametros,
        ),
        TipoComando.verificar_base_datos => await service.verifyDatabase(
          comando.parametros,
        ),
        _ => throw StateError('Acción de diagnóstico local no registrada'),
      };
      final data = <String, dynamic>{'ack_status': 'completed', ...diagnostic};
      final requestId = comando.parametros['request_id']?.toString().trim();
      if (comando.tipo == TipoComando.collect_diagnostics &&
          requestId != null &&
          requestId.isNotEmpty) {
        final artifact = await (supportService ?? AgentSupportService.instance)
            .uploadDiagnosticArtifact(diagnostic, comando.parametros);
        data.addAll(artifact);
      }
      return ResultadoComando(
        exito: true,
        mensaje: 'Diagnóstico técnico completado',
        datos: data,
      );
    } on AgentDiagnosticRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de diagnóstico rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentLogRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de artefacto diagnóstico rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible completar el diagnóstico técnico',
        datos: {
          'ack_status': 'failed',
          'error_code': 'DIAGNOSTIC_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarForzarRespaldo(
    ComandoRemoto comando,
    AgentBackupService service,
  ) async {
    try {
      final result = await service.forceBackup(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Respaldo integral generado y verificado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentBackupRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de respaldo rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentBackupExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible completar el respaldo integral',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible generar el respaldo integral',
        datos: {
          'ack_status': 'failed',
          'error_code': 'BACKUP_CREATE_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarRestaurarRespaldo(
    ComandoRemoto comando,
    AgentBackupService service,
  ) async {
    try {
      final result = await service.restoreBackup(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Respaldo integral restaurado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentBackupRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de restauración rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentBackupExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible restaurar el respaldo integral',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible restaurar el respaldo integral',
        datos: {
          'ack_status': 'failed',
          'error_code': 'BACKUP_RESTORE_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarReiniciarSesiones(
    ComandoRemoto comando,
    AgentSessionService service,
  ) async {
    try {
      final result = await service.restartSessions(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Todas las sesiones activas fueron cerradas',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentSessionRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de reinicio de sesiones rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible reiniciar sesiones',
        datos: {
          'ack_status': 'failed',
          'error_code': 'SESSION_RESTART_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarEnviarLog(
    ComandoRemoto comando,
    AgentSupportService service,
  ) async {
    try {
      final result = await service.collectAndUploadLogs(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Logs técnicos sanitizados y cargados',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentLogRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de logs rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible cargar los logs técnicos',
        datos: {
          'ack_status': 'failed',
          'error_code': 'LOG_ARTIFACT_UPLOAD_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarEntrarMantenimiento(
    ComandoRemoto comando,
    AgentMaintenanceService service,
  ) async {
    try {
      final result = await service.enterMaintenance(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Modo mantenimiento activado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentMaintenanceRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de mantenimiento rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible activar el modo mantenimiento',
        datos: {
          'ack_status': 'failed',
          'error_code': 'MAINTENANCE_ENTER_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarSalirMantenimiento(
    ComandoRemoto comando,
    AgentMaintenanceService service,
  ) async {
    try {
      final result = await service.exitMaintenance(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Modo mantenimiento desactivado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentMaintenanceRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de mantenimiento rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible desactivar el modo mantenimiento',
        datos: {
          'ack_status': 'failed',
          'error_code': 'MAINTENANCE_EXIT_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarReconstruirIndices(
    ComandoRemoto comando,
    AgentRepairService service,
  ) async {
    try {
      final result = await service.rebuildIndexes(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Índices reconstruidos y base optimizada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentRepairRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de reparación rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible reconstruir los índices',
        datos: {
          'ack_status': 'failed',
          'error_code': 'REINDEX_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarLimpiarCache(
    ComandoRemoto comando,
    AgentRepairService service,
  ) async {
    try {
      final result = await service.clearCaches(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Caché regenerable limpiada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentRepairRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de reparación rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible limpiar la caché regenerable',
        datos: {
          'ack_status': 'failed',
          'error_code': 'CACHE_CLEAR_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarReparacionSegura(
    ComandoRemoto comando,
    AgentRepairService service,
  ) async {
    try {
      final result = await service.runSafeRepair(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Reparación segura ejecutada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentRepairRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de reparación rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible ejecutar la reparación segura',
        datos: {
          'ack_status': 'failed',
          'error_code': 'SAFE_REPAIR_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarAplicarConfiguracion(
    ComandoRemoto comando,
    AgentManagedConfigService service,
  ) async {
    try {
      final result = await service.applyConfiguration(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Configuración administrada aplicada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentManagedConfigRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de configuración rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible aplicar la configuración administrada',
        datos: {
          'ack_status': 'failed',
          'error_code': 'MANAGED_CONFIGURATION_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarAplicarFeatureFlags(
    ComandoRemoto comando,
    AgentManagedConfigService service,
  ) async {
    try {
      final result = await service.applyFeatureFlags(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Feature flags administradas aplicadas',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentManagedConfigRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de feature flags rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible aplicar feature flags administradas',
        datos: {
          'ack_status': 'failed',
          'error_code': 'FEATURE_FLAGS_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarMensajeAdmin(ComandoRemoto comando) async {
    try {
      final titulo = comando.parametros['titulo'] as String?;
      final detalle = comando.parametros['detalle'] as String?;
      final prioridad = comando.parametros['prioridad'] as String? ?? 'info';

      if (titulo == null) {
        return ResultadoComando(
          exito: false,
          mensaje: 'Se requiere título del mensaje',
        );
      }

      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

      await db.insert('notificaciones', {
        'company_id': companyId,
        'tipo': 'control_center',
        'prioridad': prioridad,
        'titulo': titulo,
        'detalle': detalle ?? '',
        'entidad': 'remote_command',
        'entidad_id': null,
        'leida': 0,
        'creada_en': DateTime.now().toIso8601String(),
      });

      return ResultadoComando(
        exito: true,
        mensaje: 'Mensaje enviado al administrador',
        datos: {'titulo': titulo},
      );
    } catch (e) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Error al enviar mensaje: $e',
      );
    }
  }

  Future<ResultadoComando> _ejecutarBloquearInstalacion(
    ComandoRemoto comando,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;

      await db.execute(
        "INSERT OR REPLACE INTO app_config (clave, valor) VALUES ('instalacion_bloqueada', '1')",
      );

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CC_COMANDO_BLOQUEAR_INSTALACION',
        entidad: 'control_center',
        detalle: jsonEncode(comando.parametros),
      );

      return ResultadoComando(exito: true, mensaje: 'Instalación bloqueada');
    } catch (e) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Error al bloquear instalación: $e',
      );
    }
  }

  Future<ResultadoComando> _ejecutarActivarInstalacion(
    ComandoRemoto comando,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;

      await db.execute(
        "INSERT OR REPLACE INTO app_config (clave, valor) VALUES ('instalacion_bloqueada', '0')",
      );

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CC_COMANDO_ACTIVAR_INSTALACION',
        entidad: 'control_center',
        detalle: jsonEncode(comando.parametros),
      );

      return ResultadoComando(exito: true, mensaje: 'Instalación activada');
    } catch (e) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Error al activar instalación: $e',
      );
    }
  }

  Future<ResultadoComando> _ejecutarForzarActualizacion(
    ComandoRemoto comando,
    AgentUpdateService service,
  ) async {
    try {
      final result = await service.forceUpdate(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Actualización firmada aplicada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentUpdateRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de actualización rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentUpdateExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible aplicar la actualización firmada',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible aplicar la actualización firmada',
        datos: {
          'ack_status': 'failed',
          'error_code': 'UPDATE_APPLY_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarRollbackActualizacion(
    ComandoRemoto comando,
    AgentUpdateService service,
  ) async {
    try {
      final result = await service.rollbackUpdate(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Rollback firmado aplicado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentUpdateRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de rollback rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentUpdateExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Rollback remoto no disponible de forma segura',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible ejecutar el rollback firmado',
        datos: {
          'ack_status': 'failed',
          'error_code': 'UPDATE_ROLLBACK_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarAplicarHotfix(
    ComandoRemoto comando,
    AgentUpdateService service,
  ) async {
    try {
      final result = await service.applyHotfix(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Hotfix firmado aplicado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentUpdateRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de hotfix rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentUpdateExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Hotfix remoto no disponible de forma segura',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible aplicar el hotfix firmado',
        datos: {
          'ack_status': 'failed',
          'error_code': 'UPDATE_HOTFIX_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarReiniciar(
    ComandoRemoto comando,
    AgentRestartService service,
  ) async {
    try {
      final result = await service.requestRestart(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Reinicio controlado programado',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentRestartRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de reinicio rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentRestartExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible programar el reinicio controlado',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible programar el reinicio controlado',
        datos: {
          'ack_status': 'failed',
          'error_code': 'RESTART_SCHEDULE_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarForzarSincronizacion(
    ComandoRemoto comando,
    AgentSyncService service,
  ) async {
    try {
      final result = await service.forceSync(comando.parametros);
      return ResultadoComando(
        exito: true,
        mensaje: 'Sincronización forzada completada',
        datos: {'ack_status': 'completed', ...result},
      );
    } on AgentSyncRequestException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'Solicitud de sincronización rechazada por seguridad',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': false,
        },
      );
    } on AgentSyncExecutionException catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'La sincronización no pudo completarse',
        datos: {
          'ack_status': 'failed',
          'error_code': error.code,
          'recoverable': true,
        },
      );
    } catch (error) {
      return ResultadoComando(
        exito: false,
        mensaje: 'No fue posible forzar la sincronización',
        datos: {
          'ack_status': 'failed',
          'error_code': 'SYNC_FORCE_FAILED',
          'recoverable': true,
          'error': AgentDataSanitizer.sanitizeText(error.toString()),
        },
      );
    }
  }

  Future<ResultadoComando> _ejecutarActualizarLicenciaFirmada(
    ComandoRemoto comando, {
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
  }) async {
    final token = comando.parametros['license_token']?.toString().trim();
    if (token == null || token.isEmpty) {
      return const ResultadoComando(
        exito: false,
        mensaje:
            'Se requiere license_token RS256; no se aceptan módulos sueltos',
        datos: {
          'ack_status': 'rejected',
          'error_code': 'SIGNED_LICENSE_TOKEN_REQUIRED',
        },
      );
    }

    final update = await LicenciaService.instance.aplicarActualizacionFirmada(
      token: token,
      expectedInstallationId: comando.installationId,
      validationService: validationService,
      fingerprintService: fingerprintService,
      currentHardwareFingerprint: currentHardwareFingerprint,
      now: now,
    );
    if (!update.applied) {
      return ResultadoComando(
        exito: false,
        mensaje: 'El token de licencia firmado fue rechazado',
        datos: {'ack_status': 'rejected', 'error_code': update.errorCode},
      );
    }

    return ResultadoComando(
      exito: true,
      mensaje: 'Licencia y módulos actualizados desde token RS256',
      datos: {
        'ack_status': 'completed',
        'modules': update.modules,
        'status': update.status,
        'product_family': update.productFamily,
        'expires_at': update.expiresAt?.toIso8601String(),
      },
    );
  }

  Future<ResultadoComando> _ejecutarSolicitarAccesoRemoto(
    ComandoRemoto comando,
  ) async {
    return ControlCenterAgent.handleRemoteAccessConsent(comando.parametros);
  }

  Future<bool> verificarInstalacionBloqueada() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['instalacion_bloqueada'],
      limit: 1,
    );

    if (rows.isEmpty) return false;
    final valor = rows.first['valor']?.toString();
    return valor == '1';
  }
}
