import 'dart:convert';

import '../core/app/app_version.dart';
import '../core/logging/log_entry.dart';
import '../core/logging/logging_service.dart';
import '../db_helper.dart';
import '../services/control_center_endpoint.dart';
import '../services/control_center_license_client.dart';
import '../services/licencia_service.dart';
import 'agent_data_sanitizer.dart';

final class AgentLogRequestException implements Exception {
  const AgentLogRequestException(this.code);

  final String code;
}

final class AgentSupportService {
  AgentSupportService({
    List<LogEntry> Function()? logProvider,
    Future<ControlCenterLicenseClient> Function()? clientProvider,
    Future<String?> Function()? tokenProvider,
    DateTime Function()? clock,
  }) : _logProvider =
           logProvider ??
           (() => LoggingService.instance.getRecentLogs(count: 1000)),
       _clientProvider = clientProvider ?? _productionClient,
       _tokenProvider =
           tokenProvider ??
           (() async => (await LicenciaService.instance.obtenerLicencia())
               ?.offlineToken),
       _clock = clock ?? DateTime.now;

  static final AgentSupportService instance = AgentSupportService();
  static const int maximumArtifactBytes = 2 * 1024 * 1024;

  final List<LogEntry> Function() _logProvider;
  final Future<ControlCenterLicenseClient> Function() _clientProvider;
  final Future<String?> Function() _tokenProvider;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> collectAndUploadLogs(
    Map<String, dynamic> params,
  ) async {
    const allowed = {
      'request_id',
      'periodo_inicio',
      'periodo_fin',
      'max_bytes',
      'module',
      'nivel',
      'level',
      'limit',
    };
    if (params.keys.toSet().difference(allowed).isNotEmpty) {
      throw const AgentLogRequestException('UNSUPPORTED_LOG_PARAMETER');
    }
    final requestId = params['request_id']?.toString() ?? '';
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(requestId)) {
      throw const AgentLogRequestException('INVALID_ARTIFACT_REQUEST_ID');
    }
    final now = _clock().toUtc();
    final from =
        DateTime.tryParse(
          params['periodo_inicio']?.toString() ?? '',
        )?.toUtc() ??
        now.subtract(const Duration(minutes: 30));
    final to =
        DateTime.tryParse(params['periodo_fin']?.toString() ?? '')?.toUtc() ??
        now;
    if (from.isAfter(to) || to.difference(from) > const Duration(days: 7)) {
      throw const AgentLogRequestException('INVALID_LOG_PERIOD');
    }
    final requestedBytes = int.tryParse(params['max_bytes']?.toString() ?? '');
    final maxBytes = requestedBytes == null
        ? maximumArtifactBytes
        : requestedBytes.clamp(1024, maximumArtifactBytes);
    final limit = (int.tryParse(params['limit']?.toString() ?? '') ?? 1000)
        .clamp(1, 1000);
    final requestedModule = params['module']?.toString().trim();
    final requestedLevel = (params['nivel'] ?? params['level'])
        ?.toString()
        .trim()
        .toUpperCase();

    final selected =
        _logProvider()
            .where(
              (entry) =>
                  !entry.timestamp.toUtc().isBefore(from) &&
                  !entry.timestamp.toUtc().isAfter(to) &&
                  (requestedModule == null ||
                      requestedModule.isEmpty ||
                      entry.module == requestedModule) &&
                  (requestedLevel == null ||
                      requestedLevel.isEmpty ||
                      entry.levelString == requestedLevel),
            )
            .take(limit)
            .map(_safeLog)
            .toList()
          ..sort(
            (a, b) =>
                (a['timestamp'] as String).compareTo(b['timestamp'] as String),
          );

    var omitted = 0;
    String encodeContent() => jsonEncode({
      'format': 'MERKAERP_LOGS_1',
      'generated_at': now.toIso8601String(),
      'period': {'from': from.toIso8601String(), 'to': to.toIso8601String()},
      'entries': selected,
      'omitted_for_size': omitted,
      'privacy': const {
        'sanitized': true,
        'user_ids_included': false,
        'company_ids_included': false,
        'credentials_included': false,
      },
    });

    var content = encodeContent();
    while (utf8.encode(content).length > maxBytes && selected.isNotEmpty) {
      selected.removeAt(0);
      omitted++;
      content = encodeContent();
    }
    if (utf8.encode(content).length > maxBytes) {
      throw const AgentLogRequestException('LOG_ARTIFACT_LIMIT_TOO_SMALL');
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AgentLogRequestException('LICENSE_TOKEN_UNAVAILABLE');
    }
    final response = await (await _clientProvider()).uploadTextArtifact(
      authorizationToken: token,
      requestId: requestId,
      artifactType: 'logs',
      name: 'merkaerp-logs-$requestId.json',
      content: content,
      metadata: {
        'format': 'MERKAERP_LOGS_1',
        'app_version': AppVersion.display,
        'entries': selected.length,
        'omitted_for_size': omitted,
      },
    );
    return {
      'artifact_id': response['artifact_id']?.toString(),
      'request_id': requestId,
      'sha256': response['sha256']?.toString(),
      'size_bytes': response['size_bytes'] ?? utf8.encode(content).length,
      'entries': selected.length,
      'omitted_for_size': omitted,
      'sanitized': true,
    };
  }

  Future<Map<String, dynamic>> uploadDiagnosticArtifact(
    Map<String, dynamic> diagnostic,
    Map<String, dynamic> params,
  ) async {
    final requestId = params['request_id']?.toString() ?? '';
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(requestId)) {
      throw const AgentLogRequestException('INVALID_ARTIFACT_REQUEST_ID');
    }
    final safeDiagnostic =
        AgentDataSanitizer.sanitize(diagnostic) as Map<String, dynamic>;
    final content = jsonEncode(safeDiagnostic);
    final size = utf8.encode(content).length;
    if (size > maximumArtifactBytes) {
      throw const AgentLogRequestException('DIAGNOSTIC_ARTIFACT_TOO_LARGE');
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AgentLogRequestException('LICENSE_TOKEN_UNAVAILABLE');
    }
    final response = await (await _clientProvider()).uploadTextArtifact(
      authorizationToken: token,
      requestId: requestId,
      artifactType: 'diagnostic',
      name: 'merkaerp-diagnostic-$requestId.json',
      content: content,
      metadata: {
        'format': safeDiagnostic['format']?.toString(),
        'app_version': AppVersion.display,
        'overall_status': safeDiagnostic['overall_status']?.toString(),
        'checks': (safeDiagnostic['checks'] as List?)?.length ?? 0,
      },
    );
    return {
      'artifact_uploaded': true,
      'artifact_type': 'diagnostic',
      'artifact_id': response['artifact_id']?.toString(),
      'request_id': requestId,
      'artifact_sha256': response['sha256']?.toString(),
      'artifact_size_bytes': response['size_bytes'] ?? size,
      'sanitized': true,
    };
  }

  Map<String, dynamic> _safeLog(LogEntry entry) {
    return AgentDataSanitizer.sanitize({
          'level': entry.levelString,
          'module': entry.module,
          'timestamp': entry.timestamp.toUtc().toIso8601String(),
          'message': entry.message,
          'stack_trace': entry.stackTrace,
        })
        as Map<String, dynamic>;
  }

  static Future<ControlCenterLicenseClient> _productionClient() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['control_center_endpoint'],
      limit: 1,
    );
    final endpoint = rows.isEmpty
        ? ControlCenterEndpoint.defaultEndpoint
        : rows.single['valor']?.toString();
    return ControlCenterLicenseClient(
      endpoint: ControlCenterEndpoint.normalize(
        endpoint ?? ControlCenterEndpoint.defaultEndpoint,
      ),
    );
  }
}
