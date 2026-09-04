import '../domain/license_models.dart';

class LicensePolicyService {
  const LicensePolicyService();

  LicenseEvaluation evaluate(TenantLicense license) {
    final messages = <String>[];
    var allowed = true;

    if (license.status == LicenseStatus.suspended) {
      allowed = false;
      messages.add('La licencia esta suspendida.');
    }
    if (license.expired || license.status == LicenseStatus.expired) {
      allowed = false;
      messages.add('La licencia expiro.');
    }
    if (license.activeDevices > license.plan.maxDevices) {
      allowed = false;
      messages.add('Limite de dispositivos superado.');
    }
    if (license.activeBranches > license.plan.maxBranches) {
      allowed = false;
      messages.add('Limite de sucursales superado.');
    }
    if (messages.isEmpty) {
      messages.add('Licencia valida para operacion.');
    }

    return LicenseEvaluation(
      allowed: allowed,
      status: license.expired ? LicenseStatus.expired : license.status,
      messages: messages,
      modules: license.plan.enabledModules,
    );
  }

  LicenseEvaluation localTrial() {
    return evaluate(
      TenantLicense(
        tenantId: 'local',
        plan: const SaaSPlan(
          id: 'enterprise-local',
          name: 'Enterprise Local',
          maxCompanies: 5,
          maxBranches: 20,
          maxDevices: 50,
          enabledModules: {
            'sales',
            'purchases',
            'inventory',
            'accounting',
            'reports',
            'sync',
            'workflows',
          },
        ),
        status: LicenseStatus.trial,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        activeDevices: 1,
        activeBranches: 1,
      ),
    );
  }
}
