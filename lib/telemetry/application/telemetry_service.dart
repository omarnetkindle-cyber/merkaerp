import '../domain/telemetry_models.dart';

class InMemoryTelemetrySink {
  final List<TelemetryEvent> _events = [];

  List<TelemetryEvent> get events => List.unmodifiable(_events);

  void record(TelemetryEvent event) {
    _events.add(event);
  }
}

class TelemetryService {
  TelemetryService({InMemoryTelemetrySink? sink})
    : _sink = sink ?? InMemoryTelemetrySink();

  final InMemoryTelemetrySink _sink;

  List<TelemetryEvent> get events => _sink.events;

  void log({
    required String name,
    TelemetrySeverity severity = TelemetrySeverity.info,
    Map<String, Object?> attributes = const {},
    TraceContext? trace,
  }) {
    _sink.record(
      TelemetryEvent(
        name: name,
        severity: severity,
        occurredAt: DateTime.now(),
        trace: trace ?? _newTrace(),
        attributes: attributes,
      ),
    );
  }

  List<HealthCheckResult> healthChecks() {
    final now = DateTime.now();
    return [
      HealthCheckResult(
        name: 'app_runtime',
        healthy: true,
        detail: 'Flutter runtime activo.',
        checkedAt: now,
      ),
      HealthCheckResult(
        name: 'offline_first',
        healthy: true,
        detail: 'SQLite local disponible como fuente operativa offline.',
        checkedAt: now,
      ),
      HealthCheckResult(
        name: 'sync_transport',
        healthy: false,
        detail: 'Transporte SaaS pendiente de configurar.',
        checkedAt: now,
      ),
    ];
  }

  Map<String, Object?> healthSummary() {
    final checks = healthChecks();
    return {
      'healthy': checks.every((check) => check.healthy),
      'checks': checks.map((check) => check.toMap()).toList(),
      'events_buffered': events.length,
    };
  }

  TraceContext _newTrace() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    return TraceContext(traceId: 'trace-$now', spanId: 'span-$now');
  }
}
