import '../core/app/app_version.dart';
import 'agent_data_sanitizer.dart';
import 'agent_store.dart';

final class AgentErrorReporter {
  AgentErrorReporter({MerkaAgentStore? store})
    : _store = store ?? MerkaAgentStore.instance;

  static final AgentErrorReporter instance = AgentErrorReporter();

  final MerkaAgentStore _store;

  Future<void> queue({
    required String message,
    String module = 'core',
    String severity = 'error',
    String? stackTrace,
    Map<String, Object?> context = const {},
  }) async {
    final normalizedSeverity =
        const {
          'warning',
          'error',
          'critical',
          'fatal',
        }.contains(severity.toLowerCase())
        ? severity.toLowerCase()
        : 'error';
    final sanitized =
        AgentDataSanitizer.sanitize({
              'message': message,
              'module': module,
              'severity': normalizedSeverity,
              'stack': stackTrace ?? '',
              'version': AppVersion.display,
              'context': context,
            })
            as Map<String, dynamic>;
    await _store.enqueueError(sanitized.cast<String, Object?>());
  }
}
