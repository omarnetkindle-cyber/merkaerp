import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../db_helper.dart';
import '../domain/integration_definition.dart';
import 'integration_settings_service.dart';

class InstitutionalResponse {
  const InstitutionalResponse({
    required this.ok,
    required this.statusCode,
    required this.message,
    this.data,
  });

  final bool ok;
  final int statusCode;
  final String message;
  final Object? data;
}

/// Conector HTTP institucional de uso controlado.
///
/// No presupone que SECOP, CHIP, SIIF o un portal externo tengan un contrato
/// técnico único. La organización configura URL, autenticación y rutas según
/// el servicio/autorización que realmente posea. Todas las operaciones son
/// fail-closed: un 2xx real es requisito mínimo para declarar transporte OK.
class InstitutionalConnectorService {
  InstitutionalConnectorService._();
  static final InstitutionalConnectorService instance =
      InstitutionalConnectorService._();

  final IntegrationSettingsService _settings =
      IntegrationSettingsService.instance;

  Future<InstitutionalResponse> get(
    String providerKey, {
    String? pathField,
    Map<String, String>? query,
  }) => _request(
        providerKey,
        method: 'GET',
        pathField: pathField,
        query: query,
      );

  Future<InstitutionalResponse> postJson(
    String providerKey, {
    required Object payload,
    String pathField = 'submission_path',
  }) => _request(
        providerKey,
        method: 'POST',
        pathField: pathField,
        payload: payload,
      );


  Future<InstitutionalResponse> getPath(
    String providerKey, {
    required String path,
    Map<String, String>? query,
  }) => _request(
        providerKey,
        method: 'GET',
        literalPath: path,
        query: query,
      );

  Future<InstitutionalResponse> postPath(
    String providerKey, {
    required String path,
    required Object payload,
  }) => _request(
        providerKey,
        method: 'POST',
        literalPath: path,
        payload: payload,
      );

  Future<InstitutionalResponse> putJson(
    String providerKey, {
    required Object payload,
    required String path,
  }) => _request(
        providerKey,
        method: 'PUT',
        literalPath: path,
        payload: payload,
      );

  Future<InstitutionalResponse> _request(
    String providerKey, {
    required String method,
    String? pathField,
    String? literalPath,
    Map<String, String>? query,
    Object? payload,
  }) async {
    final definition = IntegrationRegistry.byKey(providerKey);
    if (!await _settings.isConfigured(providerKey)) {
      return InstitutionalResponse(
        ok: false,
        statusCode: 0,
        message: '${definition.name} no está configurado o habilitado.',
      );
    }
    final values = await _settings.loadValues(definition);
    final base = (values['base_url'] ?? values['endpoint'] ?? '').trim();
    final baseUri = Uri.tryParse(base);
    if (!_allowed(baseUri)) {
      return const InstitutionalResponse(
        ok: false,
        statusCode: 0,
        message: 'El endpoint debe usar HTTPS y no puede contener credenciales en la URL.',
      );
    }
    final path = literalPath ??
        (pathField == null ? '' : (values[pathField] ?? '').trim());
    var uri = path.isEmpty ? baseUri! : baseUri!.resolve(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final request = http.Request(method, uri);
    request.headers.addAll(_headers(values));
    if (payload != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(payload);
    }

    try {
      final client = http.Client();
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      client.close();
      Object? decoded;
      if (body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(body);
        } catch (_) {
          decoded = body;
        }
      }
      final ok = streamed.statusCode >= 200 && streamed.statusCode < 300;
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: ok ? 'INTEGRACION_EXTERNA_OK' : 'INTEGRACION_EXTERNA_ERROR',
        entidad: 'integration_$providerKey',
        detalle: '$method ${uri.host}${uri.path}; http=${streamed.statusCode}',
      );
      return InstitutionalResponse(
        ok: ok,
        statusCode: streamed.statusCode,
        message: ok
            ? 'Operación aceptada por ${definition.name}.'
            : '${definition.name} respondió HTTP ${streamed.statusCode}.',
        data: decoded,
      );
    } catch (_) {
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'INTEGRACION_EXTERNA_ERROR',
        entidad: 'integration_$providerKey',
        detalle: '$method ${uri.host}${uri.path}; error de transporte',
      );
      return InstitutionalResponse(
        ok: false,
        statusCode: 0,
        message: 'No fue posible completar la operación con ${definition.name}.',
      );
    }
  }

  Map<String, String> _headers(Map<String, String> values) {
    final headers = <String, String>{'Accept': 'application/json'};
    final type = (values['auth_type'] ?? '').trim().toUpperCase();
    final credential = (values['credential'] ?? values['api_key'] ?? '').trim();
    final username = (values['username'] ?? '').trim();
    if (type == 'BASIC') {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$username:$credential'))}';
    } else if (type == 'API_KEY' && credential.isNotEmpty) {
      headers[username.isEmpty ? 'X-API-Key' : username] = credential;
    } else if ((type == 'BEARER' || type.isEmpty) && credential.isNotEmpty) {
      headers['Authorization'] = 'Bearer $credential';
    } else if (type.isEmpty) {
      final clientId = (values['client_id'] ?? '').trim();
      final clientSecret = (values['client_secret'] ?? '').trim();
      if (clientId.isNotEmpty && clientSecret.isNotEmpty) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';
      }
    }
    final xroad = (values['xroad_client_id'] ?? '').trim();
    if (xroad.isNotEmpty) headers['X-Road-Client'] = xroad;
    return headers;
  }

  bool _allowed(Uri? uri) {
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme.toLowerCase() == 'https') return true;
    return uri.scheme.toLowerCase() == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
  }
}
