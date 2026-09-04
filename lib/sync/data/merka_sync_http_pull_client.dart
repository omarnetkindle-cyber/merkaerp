import 'dart:convert';

import 'package:dio/dio.dart';

import '../application/merka_sync_pull_service.dart';
import 'merka_sync_http_push_client.dart';

abstract class MerkaSyncJsonGetter {
  Future<MerkaSyncHttpResponse> getJson({
    required String path,
    required Map<String, Object?> query,
    required Map<String, String> headers,
  });
}

class DioMerkaSyncJsonGetter implements MerkaSyncJsonGetter {
  DioMerkaSyncJsonGetter({required String serverBaseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBaseUrl(serverBaseUrl),
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;

  @override
  Future<MerkaSyncHttpResponse> getJson({
    required String path,
    required Map<String, Object?> query,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.get(
      path,
      queryParameters: query,
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

class MerkaSyncHttpPullClient implements MerkaSyncPullClient {
  MerkaSyncHttpPullClient({
    required MerkaSyncJsonGetter getter,
    required Future<String?> Function() authTokenProvider,
    this.pullPath = '/api/sync/events',
    this.includeSelf = false,
  }) : _getter = getter,
       _authTokenProvider = authTokenProvider;

  final MerkaSyncJsonGetter _getter;
  final Future<String?> Function() _authTokenProvider;
  final String pullPath;
  final bool includeSelf;

  @override
  Future<MerkaSyncPullPage> pull({
    required String cursor,
    required int limit,
  }) async {
    final authToken = (await _authTokenProvider())?.trim();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'Bearer $authToken',
    };
    final response = await _getter.getJson(
      path: pullPath,
      query: {'cursor': cursor, 'limit': limit, 'include_self': includeSelf},
      headers: headers,
    );
    final data = _responseMap(response.data);
    final acceptedByStatus =
        response.statusCode >= 200 && response.statusCode < 300;
    if (!acceptedByStatus || data['accepted'] == false) {
      throw MerkaSyncHttpPullException(
        statusCode: response.statusCode,
        message:
            _firstString(data, const ['message', 'error']) ??
            'El servidor rechazó el pull de eventos.',
        body: data,
      );
    }

    final rawEvents = data['events'];
    if (rawEvents is! List) {
      throw const FormatException('Respuesta sync sin lista events.');
    }

    return MerkaSyncPullPage(
      cursor: _firstString(data, const ['cursor', 'next_cursor']) ?? cursor,
      hasMore: _boolValue(data['has_more'] ?? data['hasMore']),
      events: rawEvents.map((raw) {
        if (raw is Map<String, dynamic>) {
          return MerkaSyncRemoteEvent.fromJson(raw);
        }
        if (raw is Map) {
          return MerkaSyncRemoteEvent.fromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
        throw const FormatException('Evento remoto inválido.');
      }).toList(),
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

class MerkaSyncHttpPullException implements Exception {
  const MerkaSyncHttpPullException({
    required this.statusCode,
    required this.message,
    required this.body,
  });

  final int statusCode;
  final String message;
  final Map<String, Object?> body;

  @override
  String toString() => 'MerkaSyncHttpPullException($statusCode): $message';
}
