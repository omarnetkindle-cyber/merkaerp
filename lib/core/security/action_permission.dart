enum AppAction {
  view,
  create,
  update,
  delete,
  cancel,
  receive,
  collect,
  overrideLimit,
  schedulePayment,
  transfer,
  approvePayment,
  reconcile,
  depreciate,
  managePipeline,
  post,
  reverse,
  approve,
  export,
  configure,
  close,
  reopen,
  viewCost,
}

class PermissionRule {
  const PermissionRule({
    required this.role,
    required this.moduleId,
    required this.actions,
  });

  final String role;
  final String moduleId;
  final Set<AppAction> actions;
}

class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  static const _allActions = {
    AppAction.view,
    AppAction.create,
    AppAction.update,
    AppAction.delete,
    AppAction.cancel,
    AppAction.receive,
    AppAction.collect,
    AppAction.overrideLimit,
    AppAction.schedulePayment,
    AppAction.transfer,
    AppAction.approvePayment,
    AppAction.reconcile,
    AppAction.depreciate,
    AppAction.managePipeline,
    AppAction.post,
    AppAction.reverse,
    AppAction.approve,
    AppAction.export,
    AppAction.configure,
    AppAction.close,
    AppAction.reopen,
    AppAction.viewCost,
  };

  static const _rules = <PermissionRule>[
    PermissionRule(role: 'administrador', moduleId: '*', actions: _allActions),
    PermissionRule(role: 'sistema', moduleId: '*', actions: _allActions),
    PermissionRule(
      role: 'contador',
      moduleId: '*',
      actions: {
        AppAction.view,
        AppAction.create,
        AppAction.update,
        AppAction.cancel,
        AppAction.receive,
        AppAction.collect,
        AppAction.overrideLimit,
        AppAction.schedulePayment,
        AppAction.transfer,
        AppAction.approvePayment,
        AppAction.reconcile,
        AppAction.depreciate,
        AppAction.managePipeline,
        AppAction.post,
        AppAction.reverse,
        AppAction.export,
        AppAction.close,
        AppAction.reopen,
        AppAction.viewCost,
      },
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'cash',
      actions: {
        AppAction.view,
        AppAction.create,
        AppAction.export,
        AppAction.close,
      },
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'sales',
      actions: {AppAction.view, AppAction.create, AppAction.cancel},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'inventory',
      actions: {AppAction.view},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'clients',
      actions: {AppAction.view, AppAction.create, AppAction.update},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'reports',
      actions: {AppAction.view, AppAction.export},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'cash_closings',
      actions: {AppAction.view, AppAction.create, AppAction.close},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'receipts',
      actions: {AppAction.view, AppAction.create, AppAction.export},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'manual',
      actions: {AppAction.view},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'purchases',
      actions: {
        AppAction.view,
        AppAction.create,
        AppAction.update,
        AppAction.approve,
        AppAction.receive,
      },
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'inventory',
      actions: {
        AppAction.view,
        AppAction.create,
        AppAction.update,
        AppAction.viewCost,
      },
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'sales',
      actions: {AppAction.view, AppAction.create},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'cash',
      actions: {AppAction.view, AppAction.create},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'clients',
      actions: {AppAction.view, AppAction.create, AppAction.update},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'suppliers',
      actions: {AppAction.view, AppAction.create, AppAction.update},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'receipts',
      actions: {AppAction.view, AppAction.create},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'manual',
      actions: {AppAction.view},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'accounts_receivable',
      actions: {AppAction.view, AppAction.collect},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'accounts_payable',
      actions: {AppAction.view, AppAction.schedulePayment},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'treasury',
      actions: {AppAction.view, AppAction.transfer},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'bank_reconciliation',
      actions: {AppAction.view, AppAction.reconcile},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'crm',
      actions: {AppAction.view, AppAction.managePipeline},
    ),
    PermissionRule(
      role: 'cajero',
      moduleId: 'document_management',
      actions: {AppAction.view, AppAction.create, AppAction.export},
    ),
    PermissionRule(
      role: 'operador',
      moduleId: 'document_management',
      actions: {AppAction.view, AppAction.create, AppAction.update, AppAction.export},
    ),
    PermissionRule(
      role: 'consulta',
      moduleId: '*',
      actions: {AppAction.view, AppAction.export},
    ),
  ];

  bool can({
    required String? role,
    required String moduleId,
    required AppAction action,
  }) {
    if (role == null || role.trim().isEmpty || role == 'sin_sesion') {
      return false;
    }
    final normalizedRole = role.toLowerCase().trim();
    final normalizedModule = moduleId.toLowerCase().trim();
    return _rules.any(
      (rule) =>
          rule.role == normalizedRole &&
          (rule.moduleId == '*' || rule.moduleId == normalizedModule) &&
          rule.actions.contains(action),
    );
  }
}
