import '../core/maintenance/maintenance_service.dart';
import '../db_helper.dart';
import 'agent_data_sanitizer.dart';

final class AgentMaintenanceRequestException implements Exception {
  const AgentMaintenanceRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentMaintenanceService {
  AgentMaintenanceService({
    MaintenanceService? maintenanceService,
    DateTime Function()? clock,
  }) : _maintenanceService = maintenanceService ?? MaintenanceService.instance,
       _clock = clock ?? DateTime.now;

  static final AgentMaintenanceService instance = AgentMaintenanceService();

  final MaintenanceService _maintenanceService;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> enterMaintenance(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {
      'message',
      'mensaje',
      'reason',
      'motivo',
      'request_id',
    });
    final message = _maintenanceMessage(params);

    await _maintenanceService.enableMaintenanceMode(message: message);
    await DatabaseHelper.instance.cambiarBloqueoOperativo(true);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_ENTRAR_MANTENIMIENTO',
      entidad: 'control_center',
      detalle: message,
    );

    return {
      'format': 'MERKAERP_AGENT_MAINTENANCE_1',
      'maintenance_mode': true,
      'operations_blocked': true,
      'admin_access_preserved': true,
      'message': message,
      'changed_at': _clock().toUtc().toIso8601String(),
      'sanitized': true,
    };
  }

  Future<Map<String, dynamic>> exitMaintenance(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'request_id'});

    await _maintenanceService.disableMaintenanceMode();
    await DatabaseHelper.instance.cambiarBloqueoOperativo(false);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_SALIR_MANTENIMIENTO',
      entidad: 'control_center',
      detalle: 'Modo mantenimiento desactivado por comando remoto firmado',
    );

    return {
      'format': 'MERKAERP_AGENT_MAINTENANCE_1',
      'maintenance_mode': false,
      'operations_blocked': false,
      'admin_access_preserved': true,
      'changed_at': _clock().toUtc().toIso8601String(),
      'sanitized': true,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentMaintenanceRequestException(
        'UNSUPPORTED_MAINTENANCE_PARAMETER',
        'Parametro de mantenimiento no permitido: ${unsupported.first}',
      );
    }
  }

  String _maintenanceMessage(Map<String, dynamic> params) {
    final raw =
        params['message'] ??
        params['mensaje'] ??
        params['reason'] ??
        params['motivo'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return 'Sistema en mantenimiento por solicitud administrativa.';
    }
    final sanitized = AgentDataSanitizer.sanitizeText(raw.toString().trim());
    if (sanitized.length > 500) return sanitized.substring(0, 500);
    return sanitized;
  }
}
