import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';
import 'agent_data_sanitizer.dart';

final class AgentRestartRequestException implements Exception {
  const AgentRestartRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentRestartExecutionException implements Exception {
  const AgentRestartExecutionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentRestartService {
  AgentRestartService({
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? restartScheduler,
    String Function()? executableProvider,
  }) : _clock = clock ?? DateTime.now,
       _restartScheduler = restartScheduler ?? _scheduleSelfRestart,
       _executableProvider =
           executableProvider ?? (() => Platform.resolvedExecutable);

  static final AgentRestartService instance = AgentRestartService();

  final DateTime Function() _clock;
  final Future<void> Function(Duration delay) _restartScheduler;
  final String Function() _executableProvider;

  Future<Map<String, dynamic>> requestRestart(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {
      'reason',
      'delay_seconds',
      'request_id',
    });
    final reason = _normalizeReason(params['reason']);
    final delay = _normalizeDelay(params['delay_seconds']);
    final executable = _executableProvider().trim();
    if (executable.isEmpty || executable.contains(RegExp(r'[\r\n]'))) {
      throw const AgentRestartExecutionException(
        'RESTART_EXECUTABLE_UNAVAILABLE',
        'No se pudo identificar el ejecutable actual para relanzar la app',
      );
    }

    final requestedAt = _clock().toUtc().toIso8601String();
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': 'cc_restart_requested_at',
      'valor': requestedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('app_config', {
      'clave': 'cc_restart_reason',
      'valor': reason,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('app_config', {
      'clave': 'cc_restart_delay_seconds',
      'valor': delay.inSeconds.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_COMANDO_REINICIAR',
      entidad: 'control_center',
      detalle: 'restart_scheduled=true; delay_seconds=${delay.inSeconds}',
    );

    await _restartScheduler(delay);

    return {
      'format': 'MERKAERP_AGENT_RESTART_1',
      'restart_scheduled': true,
      'delay_seconds': delay.inSeconds,
      'requested_at': requestedAt,
      'local_path_disclosed': false,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentRestartRequestException(
        'UNSUPPORTED_RESTART_PARAMETER',
        'Parametro de reinicio no permitido: ${unsupported.first}',
      );
    }
  }

  String _normalizeReason(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return 'Reinicio remoto Control Center';
    if (value.length > 200) {
      throw const AgentRestartRequestException(
        'INVALID_RESTART_REASON',
        'reason debe tener máximo 200 caracteres',
      );
    }
    final sanitized = AgentDataSanitizer.sanitizeText(value);
    if (sanitized.contains(RegExp(r'[;`]|--|/\*|\*/'))) {
      throw const AgentRestartRequestException(
        'INVALID_RESTART_REASON',
        'reason contiene caracteres no permitidos',
      );
    }
    return sanitized;
  }

  Duration _normalizeDelay(dynamic raw) {
    if (raw == null) return const Duration(seconds: 3);
    final seconds = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    if (seconds == null || seconds < 2 || seconds > 60) {
      throw const AgentRestartRequestException(
        'INVALID_RESTART_DELAY',
        'delay_seconds debe estar entre 2 y 60',
      );
    }
    return Duration(seconds: seconds);
  }

  static Future<void> _scheduleSelfRestart(Duration delay) async {
    final executable = Platform.resolvedExecutable;
    Timer(delay, () async {
      try {
        await Process.start(
          executable,
          const [],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } finally {
        exit(0);
      }
    });
  }
}
