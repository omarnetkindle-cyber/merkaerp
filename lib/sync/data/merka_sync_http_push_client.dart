import 'dart:convert';

import 'package:dio/dio.dart';

import '../application/merka_sync_push_service.dart';

class MerkaSyncHttpResponse {
  const MerkaSyncHttpResponse({required this.statusCode, this.data});

  final int statusCode;
  final Object? data;
}

abstract class MerkaSyncJsonPoster {
  Future<MerkaSyncHttpResponse> postJson({
    required String path,
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

class DioMerkaSyncJsonPoster implements MerkaSyncJsonPoster {
  DioMerkaSyncJsonPoster({required String serverBaseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBaseUrl(serverBaseUrl),
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;

  @override
  Future<MerkaSyncHttpResponse> postJson({
    required String path,
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.post(
      path,
      data: body,
      options: Options(headers: headers),
    );
    return MerkaSyncHttpResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'serverBaseUrl',
        'No puede estar vacío.',
      );
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class MerkaSyncHttpPushClient implements MerkaSyncPushClient {
  MerkaSyncHttpPushClient({
    required MerkaSyncJsonPoster poster,
    required Future<String?> Function() authTokenProvider,
    this.pushPath = '/api/sync/events',
  }) : _poster = poster,
       _authTokenProvider = authTokenProvider;

  final MerkaSyncJsonPoster _poster;
  final Future<String?> Function() _authTokenProvider;
  final String pushPath;

  @override
  Future<MerkaSyncPushAck> push(MerkaSyncOutboundEvent event) async {
    final authToken = (await _authTokenProvider())?.trim();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Idempotency-Key': event.idempotencyKey,
      'X-Merka-Tenant-Kind': event.tenantKind,
      'X-Merka-Tenant-Id': event.tenantId,
      'X-Merka-Device-Id': event.sourceDeviceId,
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'Bearer $authToken',
    };

    final response = await _poster.postJson(
      path: pushPath,
      body: event.toTransportJson(),
      headers: headers,
    );
    final data = _responseMap(response.data);
    final duplicate =
        _boolValue(data['duplicate']) ||
        data['status']?.toString().toLowerCase() == 'duplicate';
    final acceptedByStatus =
        response.statusCode >= 200 && response.statusCode < 300;
    final acceptedByBody = data.isEmpty || data['accepted'] != false;

    if ((acceptedByStatus && acceptedByBody) || duplicate) {
      return MerkaSyncPushAck(
        accepted: true,
        duplicate: duplicate,
        remoteEventId: _firstString(data, const [
          'remote_event_id',
          'remoteEventId',
          'event_id',
          'eventId',
        ]),
        remoteCursor: _firstString(data, const [
          'remote_cursor',
          'remoteCursor',
          'cursor',
        ]),
      );
    }

    throw MerkaSyncHttpPushException(
      statusCode: response.statusCode,
      message:
          _firstString(data, const ['message', 'error']) ??
          'El servidor rechazó el evento ${event.eventId}.',
      body: data,
    );
  }

  static Map<String, Object?> _responseMap(Object? data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return {};
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  static String? _firstString(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class MerkaSyncHttpPushException implements Exception {
  const MerkaSyncHttpPushException({
    required this.statusCode,
    required this.message,
    required this.body,
  });

  final int statusCode;
  final String message;
  final Map<String, Object?> body;

  @override
  String toString() => 'MerkaSyncHttpPushException($statusCode): $message';
}
