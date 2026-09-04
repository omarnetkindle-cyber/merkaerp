import 'dian_transmission_client.dart';
import '../../db_helper.dart';

/// Fail-closed implementation used when no real PTA/DIAN transport is registered.
/// It may inspect local configuration, but it never reports a simulated send as
/// a successful electronic-invoicing operation.
class NoOpDianTransmissionClient implements DianTransmissionClient {
  /// Optional configuration reader function for testing/injection.
  /// If not provided, falls back to DatabaseHelper.instance.obtenerDianConfig().
  final Future<Map<String, String>> Function()? _configReader;

  NoOpDianTransmissionClient({Future<Map<String, String>> Function()? configReader}) : _configReader = configReader;

  Future<Map<String, String>> _readConfig() async {
    if (_configReader != null) return await _configReader();
    try {
      final cfg = await DatabaseHelper.instance.obtenerDianConfig();
      return cfg;
    } catch (e) {
      return {};
    }
  }

  @override
  Future<ConfigStatus> checkConfiguration() async {
    final cfg = await _readConfig();
    final hasTechKey = (cfg['dian_tech_key'] ?? '').isNotEmpty;
    final hasPin = (cfg['dian_pin'] ?? '').isNotEmpty;
    final hasSoftwareId = (cfg['dian_software_id'] ?? '').isNotEmpty;

    if (hasTechKey && hasPin && hasSoftwareId) return ConfigStatus.configuredComplete;
    if (hasTechKey || hasPin || hasSoftwareId) return ConfigStatus.configuredPartial;
    return ConfigStatus.notConfigured;
  }

  @override
  Future<ConnectionCheckResult> checkConnectivity() async {
    final cfgStatus = await checkConfiguration();
    if (cfgStatus == ConfigStatus.notConfigured) {
      return ConnectionCheckResult(
        status: ConnectivityStatus.notConfigured,
        message: 'Sin configuración DIAN. Guarde configuración en Centro de Facturación.',
      );
    }

    return ConnectionCheckResult(
      status: ConnectivityStatus.notConnected,
      message: 'No hay un transporte DIAN/PTA productivo configurado. La aplicación no enviará documentos electrónicos hasta registrar uno.',
    );
  }

  @override
  Future<TransmissionResult> transmitInvoice({
    required int ventaId,
    required String xml,
    required String cufe,
    Map<String, dynamic>? metadata,
  }) async {
    final cfgStatus = await checkConfiguration();
    if (cfgStatus == ConfigStatus.notConfigured) {
      return TransmissionResult(
        status: TransmissionStatus.notConfigured,
        message: 'No se ha guardado la configuración DIAN. Guarde la Resolución/ PIN antes de emitir.',
        details: {'ventaId': ventaId},
      );
    }

    return TransmissionResult(
      status: TransmissionStatus.notConfigured,
      message: 'Transmisión bloqueada: no hay un cliente DIAN/PTA real configurado. El documento NO fue enviado a la DIAN.',
      details: {'ventaId': ventaId, 'cufe': cufe, 'sent': false},
    );
  }

  @override
  Future<EnablementResult> sendEnablementPackage({required String packageContent, Map<String, dynamic>? metadata}) async {
    return EnablementResult(
      status: EnablementStatus.notImplemented,
      message: 'NoOp: envío de paquete de habilitación no implementado en NoOp.',
    );
  }
}
