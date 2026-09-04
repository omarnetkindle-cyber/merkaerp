class IntegrationProfile {
  const IntegrationProfile({
    required this.providerKey,
    required this.enabled,
    required this.config,
    required this.status,
    this.lastCheckedAt,
    this.lastMessage,
  });

  final String providerKey;
  final bool enabled;
  final Map<String, String> config;
  final String status;
  final DateTime? lastCheckedAt;
  final String? lastMessage;
}

class IntegrationCheckResult {
  const IntegrationCheckResult(this.ok, this.message);
  final bool ok;
  final String message;
}
