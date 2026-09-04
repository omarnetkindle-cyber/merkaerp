import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../integrations/application/integration_settings_service.dart';
import '../../integrations/domain/integration_definition.dart';
import 'dian_transmission_client.dart';

/// Transporte REST parametrizable para PTA/DIAN.
///
/// No presume que un HTTP 2xx equivale a aceptación DIAN: si el proveedor no
/// devuelve un estado explícito de aceptación el resultado queda `submitted`.
class ConfiguredDianTransmissionClient implements DianTransmissionClient {
  ConfiguredDianTransmissionClient({IntegrationSettingsService? settings})
      : _settings = settings ?? IntegrationSettingsService.instance;

  final IntegrationSettingsService _settings;

  Future<Map<String, String>> _values() =>
      _settings.loadValues(IntegrationRegistry.byKey('dian'));

  @override
  Future<ConfigStatus> checkConfiguration() async {
    final configured = await _settings.isConfigured('dian');
    if (configured) return ConfigStatus.configuredComplete;
    final values = await _values();
    final any = values.values.any((value) => value.trim().isNotEmpty);
    return any ? ConfigStatus.configuredPartial : ConfigStatus.notConfigured;
  }

  @override
  Future<ConnectionCheckResult> checkConnectivity() async {
    if (await checkConfiguration() != ConfigStatus.configuredComplete) {
      return ConnectionCheckResult(
        status: ConnectivityStatus.notConfigured,
        message: 'Completa la integración DIAN/PTA en Configuración → Integraciones.',
      );
    }
    final result = await _settings.testConnection(IntegrationRegistry.byKey('dian'));
    return ConnectionCheckResult(
      status: result.ok ? ConnectivityStatus.connected : ConnectivityStatus.notConnected,
      message: result.message,
    );
  }

  @override
  Future<TransmissionResult> transmitInvoice({
    required int ventaId,
    required String xml,
    required String cufe,
    Map<String, dynamic>? metadata,
  }) async {
    if (await checkConfiguration() != ConfigStatus.configuredComplete) {
      return TransmissionResult(
        status: TransmissionStatus.notConfigured,
        message: 'Transmisión bloqueada: la integración DIAN/PTA no está completa.',
        details: {'sent': false, 'ventaId': ventaId},
      );
    }
    try {
      final values = await _values();
      final uri = _endpoint(values, values['invoice_path'] ?? '/invoices');
      final response = await http
          .post(
            uri,
            headers: _headers(values),
            body: jsonEncode({
              'venta_id': ventaId,
              'cufe': cufe,
              'xml_base64': base64Encode(utf8.encode(xml)),
              'software_id': values['software_id'],
              'test_set_id': values['test_set_id'],
              'metadata': metadata ?? const <String, dynamic>{},
            }),
          )
          .timeout(const Duration(seconds: 45));
      final decoded = _json(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return TransmissionResult(
          status: response.statusCode == 401 || response.statusCode == 403
              ? TransmissionStatus.rejectedByPta
              : TransmissionStatus.error,
          message: 'El proveedor DIAN/PTA respondió HTTP ${response.statusCode}.',
          details: {'sent': true, 'httpStatus': response.statusCode, 'response': decoded},
        );
      }
      final providerStatus = _status(decoded).toLowerCase();
      final status = providerStatus.contains('accept') || providerStatus.contains('aprob') || providerStatus == 'success'
          ? TransmissionStatus.acceptedByPta
          : providerStatus.contains('reject') || providerStatus.contains('rechaz') || providerStatus.contains('error')
              ? TransmissionStatus.rejectedByPta
              : TransmissionStatus.submitted;
      return TransmissionResult(
        status: status,
        message: status == TransmissionStatus.acceptedByPta
            ? 'El proveedor reportó aceptación del documento.'
            : status == TransmissionStatus.rejectedByPta
                ? 'El proveedor reportó rechazo del documento.'
                : 'Documento enviado al proveedor. La aceptación definitiva no fue inferida.',
        externalId: _externalId(decoded),
        details: {'sent': true, 'httpStatus': response.statusCode, 'response': decoded},
      );
    } catch (_) {
      return TransmissionResult(
        status: TransmissionStatus.error,
        message: 'No fue posible transmitir el documento. No se registró como aceptado.',
        details: {'sent': false},
      );
    }
  }

  @override
  Future<EnablementResult> sendEnablementPackage({
    required String packageContent,
    Map<String, dynamic>? metadata,
  }) async {
    if (await checkConfiguration() != ConfigStatus.configuredComplete) {
      return EnablementResult(status: EnablementStatus.failed, message: 'Integración DIAN/PTA incompleta.');
    }
    try {
      final values = await _values();
      final uri = _endpoint(values, values['enablement_path'] ?? '/enablement');
      final response = await http.post(
        uri,
        headers: _headers(values),
        body: jsonEncode({
          'package_base64': base64Encode(utf8.encode(packageContent)),
          'software_id': values['software_id'],
          'test_set_id': values['test_set_id'],
          'metadata': metadata ?? const <String, dynamic>{},
        }),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return EnablementResult(status: EnablementStatus.failed, message: 'El proveedor respondió HTTP ${response.statusCode}.');
      }
      final decoded = _json(response.body);
      final providerStatus = _status(decoded).toLowerCase();
      final success = providerStatus.contains('success') || providerStatus.contains('accept') || providerStatus.contains('aprob');
      return EnablementResult(
        status: success ? EnablementStatus.success : EnablementStatus.queued,
        message: success ? 'El proveedor confirmó el paquete de habilitación.' : 'Paquete enviado; la aprobación definitiva está pendiente.',
        details: decoded is Map<String, dynamic> ? decoded : {'response': decoded},
      );
    } catch (_) {
      return EnablementResult(status: EnablementStatus.failed, message: 'No fue posible enviar el paquete de habilitación.');
    }
  }

  Uri _endpoint(Map<String, String> values, String path) {
    final base = Uri.parse((values['base_url'] ?? '').trim());
    final local = base.host == 'localhost' || base.host == '127.0.0.1' || base.host == '::1';
    if (!local && base.scheme != 'https') throw StateError('DIAN/PTA exige HTTPS.');
    return base.resolve(path.trim().isEmpty ? '/' : path.trim());
  }

  Map<String, String> _headers(Map<String, String> values) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Software-Id': values['software_id'] ?? '',
      'X-Software-Pin': values['software_pin'] ?? '',
    };
    final token = (values['api_token'] ?? '').trim();
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  dynamic _json(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try { return jsonDecode(body); } catch (_) { return {'raw': body.length > 1000 ? body.substring(0, 1000) : body}; }
  }

  String _status(dynamic data) {
    if (data is Map) {
      for (final key in ['status', 'estado', 'result', 'resultado']) {
        if (data[key] != null) return data[key].toString();
      }
    }
    return '';
  }

  String? _externalId(dynamic data) {
    if (data is Map) {
      for (final key in ['id', 'trackId', 'track_id', 'documentId', 'document_id']) {
        final value = data[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }
}
