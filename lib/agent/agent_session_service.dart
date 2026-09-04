import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';
import 'agent_data_sanitizer.dart';

final class AgentSessionRequestException implements Exception {
  const AgentSessionRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentSessionService {
  AgentSessionService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static final AgentSessionService instance = AgentSessionService();

  final DateTime Function() _clock;

  Future<Map<String, dynamic>> restartSessions(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'reason', 'request_id'});
    final reason = _normalizeReason(params['reason']);
    final db = await DatabaseHelper.instance.database;
    final tablePresent = await _tableExists(db, 'caja_sesiones');
    if (!tablePresent) {
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CC_REINICIAR_SESIONES_SIN_TABLA',
        entidad: 'control_center',
        detalle: 'caja_sesiones no existe; closed_sessions=0',
      );
      return {
        'format': 'MERKAERP_AGENT_SESSIONS_1',
        'closed_sessions': 0,
        'table_present': false,
        'completed_at': _clock().toUtc().toIso8601String(),
      };
    }

    final now = _clock().toUtc().toIso8601String();
    final values = <String, Object?>{'estado': 'cerrada', 'cerrada_en': now};
    if (await _columnExists(db, 'caja_sesiones', 'justificacion')) {
      values['justificacion'] = reason;
    }
    final closed = await db.update(
      'caja_sesiones',
      values,
      where: 'LOWER(estado) = ?',
      whereArgs: const ['abierta'],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_COMANDO_REINICIAR_SESIONES',
      entidad: 'control_center',
      detalle: 'closed_sessions=$closed',
    );

    return {
      'format': 'MERKAERP_AGENT_SESSIONS_1',
      'closed_sessions': closed,
      'table_present': true,
      'completed_at': now,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentSessionRequestException(
        'UNSUPPORTED_SESSION_PARAMETER',
        'Parametro de sesiones no permitido: ${unsupported.first}',
      );
    }
  }

  String _normalizeReason(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return 'Cierre remoto Control Center';
    if (value.length > 200) {
      throw const AgentSessionRequestException(
        'INVALID_SESSION_REASON',
        'reason debe tener máximo 200 caracteres',
      );
    }
    final sanitized = AgentDataSanitizer.sanitizeText(value);
    if (sanitized.contains(RegExp(r'[;`]|--|/\*|\*/'))) {
      throw const AgentSessionRequestException(
        'INVALID_SESSION_REASON',
        'reason contiene caracteres no permitidos',
      );
    }
    return sanitized;
  }

  Future<bool> _tableExists(Database db, String table) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      ),
    );
    return count == 1;
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name']?.toString() == column);
  }
}
