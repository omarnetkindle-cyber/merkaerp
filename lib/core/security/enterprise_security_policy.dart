import 'action_permission.dart';

class RoleCapabilityProfile {
  const RoleCapabilityProfile({required this.role, required this.modules});

  final String role;
  final Map<String, List<String>> modules;

  Map<String, Object?> toMap() => {'role': role, 'modules': modules};
}

class SensitiveActionRule {
  const SensitiveActionRule({
    required this.moduleId,
    required this.action,
    required this.reason,
    this.requiresAudit = true,
    this.recommendApproval = true,
  });

  final String moduleId;
  final AppAction action;
  final String reason;
  final bool requiresAudit;
  final bool recommendApproval;

  Map<String, Object?> toMap() => {
    'module': moduleId,
    'action': action.name,
    'reason': reason,
    'requires_audit': requiresAudit,
    'recommend_approval': recommendApproval,
  };
}

class EnterpriseSecurityPolicyService {
  EnterpriseSecurityPolicyService({PermissionService? permissionService})
    : _permissionService = permissionService ?? PermissionService.instance;

  final PermissionService _permissionService;

  static const roles = [
    'administrador',
    'contador',
    'cajero',
    'operador',
    'consulta',
  ];

  static const modules = [
    'cash',
    'sales',
    'purchases',
    'inventory',
    'clients',
    'suppliers',
    'accounting',
    'reports',
    'users',
    'audit',
    'settings',
    'backups',
  ];

  static const trackedActions = [
    AppAction.view,
    AppAction.create,
    AppAction.update,
    AppAction.cancel,
    AppAction.approve,
    AppAction.export,
    AppAction.configure,
    AppAction.close,
    AppAction.reopen,
    AppAction.viewCost,
  ];

  List<RoleCapabilityProfile> matrix() {
    return [
      for (final role in roles)
        RoleCapabilityProfile(
          role: role,
          modules: {
            for (final module in modules)
              module: [
                for (final action in trackedActions)
                  if (_permissionService.can(
                    role: role,
                    moduleId: module,
                    action: action,
                  ))
                    action.name,
              ],
          },
        ),
    ];
  }

  List<SensitiveActionRule> sensitiveActions() => const [
    SensitiveActionRule(
      moduleId: 'purchases',
      action: AppAction.cancel,
      reason: 'Anular compras impacta inventario, CXP, caja/banco y asientos.',
    ),
    SensitiveActionRule(
      moduleId: 'sales',
      action: AppAction.cancel,
      reason: 'Anular ventas impacta inventario, cartera, impuestos y caja.',
    ),
    SensitiveActionRule(
      moduleId: 'accounting',
      action: AppAction.reopen,
      reason: 'Reabrir periodos permite modificar estados ya cerrados.',
    ),
    SensitiveActionRule(
      moduleId: 'backups',
      action: AppAction.configure,
      reason: 'Restaurar respaldos reemplaza la base operativa.',
    ),
    SensitiveActionRule(
      moduleId: 'users',
      action: AppAction.configure,
      reason: 'Cambios de roles modifican segregacion de funciones.',
    ),
  ];

  Map<String, Object?> toMap() => {
    'roles': matrix().map((profile) => profile.toMap()).toList(),
    'sensitive_actions': sensitiveActions()
        .map((rule) => rule.toMap())
        .toList(),
  };
}
