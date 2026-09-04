import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'control_center_endpoint.dart';

class ControlCenterNetworkException implements Exception {
  const ControlCenterNetworkException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ControlCenterHttpException implements HttpException {
  const ControlCenterHttpException(
    this.statusCode, {
    required this.message,
    this.uri,
  });

  final int statusCode;

  @override
  final String message;

  @override
  final Uri? uri;

  @override
  String toString() => message;
}

class ControlCenterLicenseClient {
  const ControlCenterLicenseClient({
    this.endpoint,
    ControlCenterHttpTransport? transport,
  }) : _transport = transport;

  final String? endpoint;
  final ControlCenterHttpTransport? _transport;

  ControlCenterHttpTransport get transport =>
      _transport ?? const DartIoControlCenterTransport();

  Future<Map<String, dynamic>> activate({
    required String email,
    required String password,
    required String hardwareFingerprint,
  }) {
    return transport.postJson(
      ControlCenterEndpoint.buildUrl(
        endpoint ?? ControlCenterEndpoint.defaultEndpoint,
        'licenses/activate',
      ),
      {
        'email': email,
        'password': password,
        'hardware_fingerprint': hardwareFingerprint,
      },
    );
  }

  Future<Map<String, dynamic>> validate({
    required String licenseToken,
    required String hardwareFingerprint,
    required String installationId,
  }) {
    return transport.postJson(
      ControlCenterEndpoint.buildUrl(
        endpoint ?? ControlCenterEndpoint.defaultEndpoint,
        'licenses/validate',
      ),
      {
        'license_token': licenseToken,
        'hardware_fingerprint': hardwareFingerprint,
        'installation_id': installationId,
      },
    );
  }

  Future<void> heartbeat(
    Map<String, Object?> payload, {
    String? authorizationToken,
  }) async {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'installations/heartbeat',
    );
    final t = transport;
    if (authorizationToken != null && t is DartIoControlCenterTransport) {
      await t.postJsonWithBearer(url, payload, authorizationToken);
    } else {
      await t.postJson(url, payload);
    }
  }

  Future<Map<String, dynamic>> bootstrap({required String authorizationToken}) {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'agent/bootstrap',
    );
    final t = transport;
    return t is DartIoControlCenterTransport
        ? t.getJsonWithBearer(url, authorizationToken)
        : t.getJson(url);
  }

  Future<void> publishCapabilities({
    required List<String> capabilities,
    required String agentVersion,
    required String architecture,
    required String authorizationToken,
  }) async {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'agent/capabilities',
    );
    final payload = <String, Object?>{
      'capabilities': capabilities,
      'agent_version': agentVersion,
      'architecture': architecture,
    };
    final t = transport;
    if (t is DartIoControlCenterTransport) {
      await t.postJsonWithBearer(url, payload, authorizationToken);
    } else {
      await t.postJson(url, payload);
    }
  }

  Future<List<Map<String, dynamic>>> commands(
    String installationId, {
    String? authorizationToken,
  }) async {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'installations/$installationId/commands',
    );
    final t = transport;
    final response =
        authorizationToken != null && t is DartIoControlCenterTransport
        ? await t.getJsonWithBearer(url, authorizationToken)
        : await t.getJson(url);
    final raw = response['commands'] ?? response['data'] ?? response;
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  Future<void> ackCommand({
    required String commandId,
    required String installationId,
    required String status,
    String? message,
    Map<String, dynamic> result = const {},
    String? authorizationToken,
  }) async {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'commands/$commandId/ack',
    );
    final payload = <String, Object?>{
      'installation_id': installationId,
      'installationId': installationId,
      'status': status,
      'message': ?message,
      'result': result,
    };
    final t = transport;
    if (authorizationToken != null && t is DartIoControlCenterTransport) {
      await t.postJsonWithBearer(url, payload, authorizationToken);
    } else {
      await t.postJson(url, payload);
    }
  }

  Future<Map<String, dynamic>> uploadTextArtifact({
    required String authorizationToken,
    required String requestId,
    required String artifactType,
    required String name,
    required String content,
    Map<String, Object?> metadata = const {},
  }) {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'agent/artifacts',
    );
    final payload = <String, Object?>{
      'request_id': requestId,
      'artifact_type': artifactType,
      'name': name,
      'mime_type': 'application/json',
      'content': content,
      'metadata': metadata,
    };
    final t = transport;
    return t is DartIoControlCenterTransport
        ? t.postJsonWithBearer(url, payload, authorizationToken)
        : t.postJson(url, payload);
  }

  Future<Map<String, dynamic>> reportError({
    required String authorizationToken,
    required Map<String, Object?> payload,
  }) {
    final url = ControlCenterEndpoint.buildUrl(
      endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      'errors/report',
    );
    final t = transport;
    return t is DartIoControlCenterTransport
        ? t.postJsonWithBearer(url, payload, authorizationToken)
        : t.postJson(url, payload);
  }
}

abstract class ControlCenterHttpTransport {
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  );

  Future<Map<String, dynamic>> getJson(String url);
}

class DartIoControlCenterTransport implements ControlCenterHttpTransport {
  const DartIoControlCenterTransport({
    this.connectionTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 25),
  });

  final Duration connectionTimeout;
  final Duration responseTimeout;

  Future<Map<String, dynamic>> postJsonWithBearer(
    String url,
    Map<String, Object?> payload,
    String bearerToken,
  ) async {
    return _postJson(url, payload, bearerToken: bearerToken);
  }

  Future<Map<String, dynamic>> getJsonWithBearer(
    String url,
    String bearerToken,
  ) async {
    return _getJson(url, bearerToken: bearerToken);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) => _postJson(url, payload);

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, Object?> payload, {
    String? bearerToken,
  }) async {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(responseTimeout);
      final result = await _decodeResponse(response, url);
      client.close();
      return result;
    } on SocketException catch (error) {
      client.close(force: true);
      throw ControlCenterNetworkException(error.message);
    } on TimeoutException catch (_) {
      client.close(force: true);
      throw const ControlCenterNetworkException('Tiempo de espera agotado');
    } catch (error) {
      client.close(force: true);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) => _getJson(url);

  Future<Map<String, dynamic>> _getJson(
    String url, {
    String? bearerToken,
  }) async {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      final response = await request.close().timeout(responseTimeout);
      if (response.statusCode == 404) {
        client.close();
        return {'commands': <Object?>[]};
      }
      final result = await _decodeResponse(response, url);
      client.close();
      return result;
    } on SocketException catch (error) {
      client.close(force: true);
      throw ControlCenterNetworkException(error.message);
    } on TimeoutException catch (_) {
      client.close(force: true);
      throw const ControlCenterNetworkException('Tiempo de espera agotado');
    } catch (error) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _decodeResponse(
    HttpClientResponse response,
    String url,
  ) async {
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ControlCenterHttpException(
        response.statusCode,
        message: 'HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return {'data': decoded};
  }
}
