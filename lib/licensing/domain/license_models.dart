enum LicenseStatus { active, trial, expired, suspended }

class SaaSPlan {
  const SaaSPlan({
    required this.id,
    required this.name,
    required this.maxCompanies,
    required this.maxBranches,
    required this.maxDevices,
    required this.enabledModules,
  });

  final String id;
  final String name;
  final int maxCompanies;
  final int maxBranches;
  final int maxDevices;
  final Set<String> enabledModules;
}

class TenantLicense {
  const TenantLicense({
    required this.tenantId,
    required this.plan,
    required this.status,
    required this.expiresAt,
    required this.activeDevices,
    required this.activeBranches,
  });

  final String tenantId;
  final SaaSPlan plan;
  final LicenseStatus status;
  final DateTime expiresAt;
  final int activeDevices;
  final int activeBranches;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

class LicenseEvaluation {
  const LicenseEvaluation({
    required this.allowed,
    required this.status,
    required this.messages,
    required this.modules,
  });

  final bool allowed;
  final LicenseStatus status;
  final List<String> messages;
  final Set<String> modules;

  Map<String, Object?> toMap() => {
    'allowed': allowed,
    'status': status.name,
    'messages': messages,
    'modules': modules.toList()..sort(),
  };
}
