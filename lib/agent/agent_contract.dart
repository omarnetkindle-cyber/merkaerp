import 'dart:collection';
import 'dart:convert';

/// Fuente local del contrato MerkaERP Agent v2 publicado por Control Center.
///
/// Las acciones se mantienen cerradas deliberadamente. Agregar una acción
/// requiere implementar su ejecutor local y una prueba; nunca se interpreta
/// código, SQL, PowerShell ni endpoints recibidos en [params].
abstract final class MerkaAgentContract {
  static const int version = 2;
  static const String agentVersion = '5.5.0';
  static const Duration pollInterval = Duration(seconds: 45);
  static const Duration heartbeatInterval = Duration(minutes: 5);

  static const Set<String> allowedActions = {
    'forzar_respaldo',
    'restaurar_respaldo',
    'reiniciar_sesiones',
    'reiniciar',
    'bloquear_instalacion',
    'activar_instalacion',
    'entrar_mantenimiento',
    'salir_mantenimiento',
    'forzar_actualizacion',
    'rollback_actualizacion',
    'aplicar_hotfix',
    'actualizar_modulos',
    'actualizar_licencia',
    'aplicar_configuracion',
    'aplicar_feature_flags',
    'forzar_sincronizacion',
    'run_diagnostics',
    'verificar_base_datos',
    'reconstruir_indices',
    'limpiar_cache',
    'ejecutar_reparacion',
    'enviar_log',
    'collect_diagnostics',
    'mensaje_admin',
    'solicitar_acceso_remoto',
  };

  /// Capacidades realmente disponibles y anunciables por el Agent actual.
  ///
  /// Las operaciones de las fases siguientes no se anuncian hasta contar con
  /// implementación transaccional y pruebas de seguridad.
  static const List<String> phaseOneCapabilities = [
    'agent.identity',
    'agent.heartbeat',
    'agent.polling',
    'agent.hmac_sha256',
    'agent.ack_queue',
    'agent.offline_queue',
    'agent.idempotency',
    'agent.license_reconciliation',
    'agent.offline_license_grace',
    'agent.sanitized_diagnostics',
    'agent.sanitized_logs',
    'agent.durable_error_reporting',
    'forzar_respaldo',
    'restaurar_respaldo',
    'bloquear_instalacion',
    'activar_instalacion',
    'reiniciar_sesiones',
    'reiniciar',
    'entrar_mantenimiento',
    'salir_mantenimiento',
    'mensaje_admin',
    'solicitar_acceso_remoto',
    'actualizar_modulos',
    'actualizar_licencia',
    'forzar_actualizacion',
    'rollback_actualizacion',
    'aplicar_hotfix',
    'aplicar_configuracion',
    'aplicar_feature_flags',
    'forzar_sincronizacion',
    'run_diagnostics',
    'collect_diagnostics',
    'verificar_base_datos',
    'reconstruir_indices',
    'limpiar_cache',
    'ejecutar_reparacion',
    'enviar_log',
  ];

  static String canonicalCommandPayload({
    required String id,
    required String action,
    required String installationId,
    required String timestamp,
    required String expiresAt,
    required String nonce,
    required Map<String, dynamic> params,
  }) {
    return jsonEncode(
      stableValue({
        'action': action,
        'expires_at': expiresAt,
        'id': id,
        'installation_id': installationId,
        'nonce': nonce,
        'params': params,
        'timestamp': timestamp,
      }),
    );
  }

  static dynamic stableValue(dynamic value) {
    if (value is List) return value.map(stableValue).toList();
    if (value is Map) {
      final sorted = SplayTreeMap<String, dynamic>();
      for (final entry in value.entries) {
        sorted[entry.key.toString()] = stableValue(entry.value);
      }
      return sorted;
    }
    return value;
  }
}
