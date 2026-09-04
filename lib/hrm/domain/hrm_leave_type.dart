class HrmLeaveType {
  const HrmLeaveType({
    this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.requiresEntitlement = true,
    this.excludeInReportsIfNoEntitlement = false,
    this.active = true,
  });
  final int? id;
  final int companyId;
  final String code;
  final String name;
  final bool requiresEntitlement;
  final bool excludeInReportsIfNoEntitlement;
  final bool active;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'code': code,
    'name': name,
    'requires_entitlement': requiresEntitlement ? 1 : 0,
    'exclude_in_reports_if_no_entitlement': excludeInReportsIfNoEntitlement
        ? 1
        : 0,
    'active': active ? 1 : 0,
  };
  factory HrmLeaveType.fromMap(Map<String, dynamic> m) => HrmLeaveType(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    code: m['code'].toString(),
    name: m['name'].toString(),
    requiresEntitlement: m['requires_entitlement'] != 0,
    excludeInReportsIfNoEntitlement:
        m['exclude_in_reports_if_no_entitlement'] == 1,
    active: m['active'] != 0,
  );
}
