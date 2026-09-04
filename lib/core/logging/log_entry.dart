// ============================================================
// log_entry.dart
// Modelo para entradas de log
// ============================================================

enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

class LogEntry {
  final String id;
  final LogLevel level;
  final String message;
  final String? module;
  final String? userId;
  final String? companyId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final String? stackTrace;

  LogEntry({
    required this.id,
    required this.level,
    required this.message,
    this.module,
    this.userId,
    this.companyId,
    required this.timestamp,
    this.metadata,
    this.stackTrace,
  });

  String get levelString => level.name.toUpperCase();

  LogEntry copyWith({
    String? id,
    LogLevel? level,
    String? message,
    String? module,
    String? userId,
    String? companyId,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    String? stackTrace,
  }) {
    return LogEntry(
      id: id ?? this.id,
      level: level ?? this.level,
      message: message ?? this.message,
      module: module ?? this.module,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'level': levelString,
      'message': message,
      'module': module,
      'user_id': userId,
      'company_id': companyId,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'stack_trace': stackTrace,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String,
      level: LogLevel.values.firstWhere(
        (e) => e.name == (json['level'] as String).toLowerCase(),
        orElse: () => LogLevel.info,
      ),
      message: json['message'] as String,
      module: json['module'] as String?,
      userId: json['user_id'] as String?,
      companyId: json['company_id'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      stackTrace: json['stack_trace'] as String?,
    );
  }
}
