// ============================================================
// logging_service.dart
// Servicio de logging centralizado
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'log_entry.dart';
import '../../services/health_reporter.dart';
import '../../agent/agent_error_reporter.dart';

class LoggingService {
  static final LoggingService instance = LoggingService._internal();

  final List<LogEntry> _buffer = [];
  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();

  static const int _maxBufferSize = 100;
  static const int _maxLogSize = 1000;

  String? _userId;
  String? _companyId;
  LogLevel _minLevel = LogLevel.debug;
  bool _enableConsole = true;
  bool _enableFile = true;

  LoggingService._internal();

  /// Stream de logs para suscriptores
  Stream<LogEntry> get logStream => _logController.stream;

  /// Inicializa el servicio
  Future<void> initialize({
    String? userId,
    String? companyId,
    LogLevel minLevel = LogLevel.debug,
    bool enableConsole = true,
    bool enableFile = true,
  }) async {
    _userId = userId;
    _companyId = companyId;
    _minLevel = minLevel;
    _enableConsole = enableConsole;
    _enableFile = enableFile;

    // Cargar logs persistentes si están habilitados
    if (_enableFile) {
      await _loadPersistedLogs();
    }
  }

  /// Establece el contexto del usuario actual
  void setUserContext(String? userId, String? companyId) {
    _userId = userId;
    _companyId = companyId;
  }

  /// Establece el nivel mínimo de log
  void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Registra un log de nivel DEBUG
  void debug(String message, {String? module, Map<String, dynamic>? metadata}) {
    _log(LogLevel.debug, message, module: module, metadata: metadata);
  }

  /// Registra un log de nivel INFO
  void info(String message, {String? module, Map<String, dynamic>? metadata}) {
    _log(LogLevel.info, message, module: module, metadata: metadata);
  }

  /// Registra un log de nivel WARNING
  void warning(
    String message, {
    String? module,
    Map<String, dynamic>? metadata,
  }) {
    _log(LogLevel.warning, message, module: module, metadata: metadata);
  }

  /// Registra un log de nivel ERROR
  void error(
    String message, {
    String? module,
    String? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      LogLevel.error,
      message,
      module: module,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Registra un log de nivel CRITICAL
  void critical(
    String message, {
    String? module,
    String? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      LogLevel.critical,
      message,
      module: module,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Método interno de logging
  void _log(
    LogLevel level,
    String message, {
    String? module,
    String? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    // Verificar nivel mínimo
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      id: const Uuid().v4(),
      level: level,
      message: message,
      module: module,
      userId: _userId,
      companyId: _companyId,
      timestamp: DateTime.now(),
      metadata: metadata,
      stackTrace: stackTrace,
    );

    // Agregar al buffer
    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    // Agregar a logs en memoria
    _logs.add(entry);
    if (_logs.length > _maxLogSize) {
      _logs.removeAt(0);
    }

    // Emitir al stream
    _logController.add(entry);

    // Imprimir a consola si está habilitado
    if (_enableConsole) {
      _printToConsole(entry);
    }

    // Guardar a archivo si está habilitado
    if (_enableFile) {
      _persistLog(entry);
    }

    // Alerta para errores críticos
    if (level == LogLevel.critical) {
      _handleCriticalLog(entry);
    }
  }

  /// Imprime log a consola
  void _printToConsole(LogEntry entry) {
    final timestamp = entry.timestamp.toIso8601String();
    final level = entry.levelString.padRight(8);
    final module = entry.module != null ? '[${entry.module}] ' : '';

    final message = '$timestamp $level $module${entry.message}';

    switch (entry.level) {
      case LogLevel.debug:
        print('\x1B[36m$message\x1B[0m'); // Cyan
        break;
      case LogLevel.info:
        print('\x1B[32m$message\x1B[0m'); // Green
        break;
      case LogLevel.warning:
        print('\x1B[33m$message\x1B[0m'); // Yellow
        break;
      case LogLevel.error:
        print('\x1B[31m$message\x1B[0m'); // Red
        break;
      case LogLevel.critical:
        print('\x1B[35m$message\x1B[0m'); // Magenta
        break;
    }

    if (entry.stackTrace != null) {
      print(entry.stackTrace);
    }
  }

  /// Persiste log a archivo
  Future<void> _persistLog(LogEntry entry) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final logFile = File('${logDir.path}/app.log');

      final logLine = '${jsonEncode(entry.toJson())}\n';
      await logFile.writeAsString(logLine, mode: FileMode.append, flush: true);
    } catch (e) {
      // Silenciar error para evitar loop infinito
    }
  }

  /// Carga logs persistidos
  Future<void> _loadPersistedLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logFile = File('${directory.path}/logs/app.log');

      if (await logFile.exists()) {
        final lines = await logFile.readAsLines();
        for (final line in lines) {
          if (line.isNotEmpty) {
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              final entry = LogEntry.fromJson(json);
              _logs.add(entry);
            } catch (e) {
              // Ignorar líneas corruptas
            }
          }
        }
      }
    } catch (e) {
      // Silenciar error
    }
  }

  /// Propaga los eventos críticos al centro de salud. El reporter decide
  /// cómo persistir/notificar la alerta sin bloquear el flujo que generó el log.
  void _handleCriticalLog(LogEntry entry) {
    if (_enableConsole) {
      print('CRITICAL ERROR: ${entry.message}');
    }
    unawaited(
      HealthReporter.instance.reportarErrorCritico(
        entry.message,
        stackTrace: entry.stackTrace,
      ),
    );
    unawaited(
      AgentErrorReporter.instance.queue(
        message: entry.message,
        module: entry.module ?? 'core',
        severity: 'critical',
        stackTrace: entry.stackTrace,
      ),
    );
  }

  /// Obtiene logs por nivel
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Obtiene logs por módulo
  List<LogEntry> getLogsByModule(String module) {
    return _logs.where((log) => log.module == module).toList();
  }

  /// Obtiene logs por usuario
  List<LogEntry> getLogsByUser(String userId) {
    return _logs.where((log) => log.userId == userId).toList();
  }

  /// Obtiene logs por empresa
  List<LogEntry> getLogsByCompany(String companyId) {
    return _logs.where((log) => log.companyId == companyId).toList();
  }

  /// Obtiene logs en un rango de fechas
  List<LogEntry> getLogsByDateRange(DateTime start, DateTime end) {
    return _logs.where((log) {
      return log.timestamp.isAfter(start) && log.timestamp.isBefore(end);
    }).toList();
  }

  /// Obtiene logs recientes
  List<LogEntry> getRecentLogs({int count = 50}) {
    return _logs.reversed.take(count).toList();
  }

  /// Limpia todos los logs
  void clearLogs() {
    _logs.clear();
    _buffer.clear();
  }

  /// Limpia logs anteriores a una fecha
  void clearLogsBefore(DateTime date) {
    _logs.removeWhere((log) => log.timestamp.isBefore(date));
  }

  /// Exporta logs a archivo
  Future<File> exportLogsToFile({String? filename}) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/${filename ?? 'logs_export_${DateTime.now().millisecondsSinceEpoch}.json'}',
    );

    final logsJson = _logs.map((log) => log.toJson()).toList();
    await file.writeAsString(jsonEncode(logsJson));

    return file;
  }

  /// Obtiene estadísticas de logs
  Map<String, dynamic> getLogStatistics() {
    final stats = <String, dynamic>{};

    for (final level in LogLevel.values) {
      stats[level.name] = _logs.where((log) => log.level == level).length;
    }

    stats['total'] = _logs.length;
    stats['buffer_size'] = _buffer.length;

    return stats;
  }

  /// Busca logs por mensaje
  List<LogEntry> searchLogs(String query) {
    final lowerQuery = query.toLowerCase();
    return _logs.where((log) {
      return log.message.toLowerCase().contains(lowerQuery) ||
          (log.module?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// Dispose del servicio
  void dispose() {
    _logController.close();
  }
}
