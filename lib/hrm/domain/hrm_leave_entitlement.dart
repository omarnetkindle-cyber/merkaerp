class HrmLeaveEntitlement {
  const HrmLeaveEntitlement({
    this.id,
    required this.companyId,
    required this.employeeId,
    required this.leaveTypeId,
    required this.daysTotal,
    this.daysUsed = 0,
    required this.periodFrom,
    required this.periodTo,
  });
  final int? id;
  final int companyId;
  final int employeeId;
  final int leaveTypeId;
  final double daysTotal;
  final double daysUsed;
  final DateTime periodFrom;
  final DateTime periodTo;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'employee_id': employeeId,
    'leave_type_id': leaveTypeId,
    'days_total': daysTotal,
    'days_used': daysUsed,
    'period_from': periodFrom.toIso8601String(),
    'period_to': periodTo.toIso8601String(),
  };
  factory HrmLeaveEntitlement.fromMap(Map<String, dynamic> m) =>
      HrmLeaveEntitlement(
        id: (m['id'] as num?)?.toInt(),
        companyId: (m['company_id'] as num).toInt(),
        employeeId: (m['employee_id'] as num).toInt(),
        leaveTypeId: (m['leave_type_id'] as num).toInt(),
        daysTotal: (m['days_total'] as num).toDouble(),
        daysUsed: (m['days_used'] as num?)?.toDouble() ?? 0,
        periodFrom: DateTime.parse(m['period_from'].toString()),
        periodTo: DateTime.parse(m['period_to'].toString()),
      );
}
