// lib/core/invoicing/dian_transmission_client_registry.dart
//
// Punto de resolución del transporte DIAN activo.
//
// Lee el campo `mode` de la integración DIAN configurada:
//   • 'PTA'     → ConfiguredDianTransmissionClient (REST via proveedor tecnológico)
//   • 'DIRECTO' → DianDirectTransport (SOAP/certificado propio, fail-closed)
//   • (nada)    → NoOpDianTransmissionClient (sin configuración alguna)
//
// Cada llamada a [dianClient()] resuelve el transporte en el momento.
// Esto garantiza que un cambio de modo en la configuración se refleje
// inmediatamente sin reiniciar la app.

import 'dian_direct_transport.dart';
import 'dian_transmission_client.dart';
import 'dian_transmission_client_configured.dart';
import 'dian_transmission_client_noop.dart';
import '../../integrations/application/integration_settings_service.dart';

/// Instancia global de conveniencia (compatible con el código existente que
/// importa `dianTransmissionClientInstance` directamente).
/// Apunta al resolvedor dinámico por defecto.
DianTransmissionClient dianTransmissionClientInstance =
    _DynamicDianClient._instance;

/// Resuelve el cliente DIAN correcto según el campo `mode` configurado.
/// Devuelve siempre un cliente no-nulo (fail-closed por defecto).
Future<DianTransmissionClient> dianClient() =>
    _DynamicDianClient._instance.resolve();

/// Envuelve la lógica de resolución y también implementa el contrato
/// DianTransmissionClient para mantener retrocompatibilidad con código
/// que usa dianTransmissionClientInstance directamente.
class _DynamicDianClient implements DianTransmissionClient {
  _DynamicDianClient._();
  static final _DynamicDianClient _instance = _DynamicDianClient._();

  final _settings = IntegrationSettingsService.instance;
  final _noop = NoOpDianTransmissionClient();
  final _pta = ConfiguredDianTransmissionClient();
  final _direct = DianDirectTransport();

  Future<DianTransmissionClient> resolve() async {
    try {
      final profile = await _settings.load('dian');
      if (!profile.enabled) return _noop;
      final mode = (profile.config['mode'] ?? 'PTA').trim().toUpperCase();
      return mode == 'DIRECTO' ? _direct : _pta;
    } catch (_) {
      return _noop;
    }
  }

  // ── Retrocompatibilidad: delega al cliente resuelto dinámicamente ─────────

  @override
  Future<ConfigStatus> checkConfiguration() async =>
      (await resolve()).checkConfiguration();

  @override
  Future<ConnectionCheckResult> checkConnectivity() async =>
      (await resolve()).checkConnectivity();

  @override
  Future<TransmissionResult> transmitInvoice({
    required int ventaId,
    required String xml,
    required String cufe,
    Map<String, dynamic>? metadata,
  }) async =>
      (await resolve()).transmitInvoice(
        ventaId: ventaId,
        xml: xml,
        cufe: cufe,
        metadata: metadata,
      );

  @override
  Future<EnablementResult> sendEnablementPackage({
    required String packageContent,
    Map<String, dynamic>? metadata,
  }) async =>
      (await resolve()).sendEnablementPackage(
        packageContent: packageContent,
        metadata: metadata,
      );
}
