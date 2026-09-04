enum TelemetrySeverity { debug, info, warning, error, critical }

class TraceContext {
  const TraceContext({
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
    this.correlationId,
  });

  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final String? correlationId;

  Map<String, Object?> toMap() => {
    'trace_id': traceId,
    'span_id': spanId,
    'parent_span_id': parentSpanId,
    'correlation_id': correlationId,
  };
}

class TelemetryEvent {
  const TelemetryEvent({
    required this.name,
    required this.severity,
    required this.occurredAt,
    required this.trace,
    this.attributes = const {},
  });

  final String name;
  final TelemetrySeverity severity;
  final DateTime occurredAt;
  final TraceContext trace;
  final Map<String, Object?> attributes;

  Map<String, Object?> toMap() => {
    'name': name,
    'severity': severity.name,
    'occurred_at': occurredAt.toIso8601String(),
    'trace': trace.toMap(),
    'attributes': attributes,
  };
}

class HealthCheckResult {
  const HealthCheckResult({
    required this.name,
    required this.healthy,
    required this.detail,
    required this.checkedAt,
  });

  final String name;
  final bool healthy;
  final String detail;
  final DateTime checkedAt;

  Map<String, Object?> toMap() => {
    'name': name,
    'healthy': healthy,
    'detail': detail,
    'checked_at': checkedAt.toIso8601String(),
  };
}
