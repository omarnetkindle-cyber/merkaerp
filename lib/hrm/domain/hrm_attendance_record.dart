class HrmAttendanceRecord {
  const HrmAttendanceRecord({
    this.id,
    required this.companyId,
    required this.employeeId,
    this.punchIn,
    this.punchOut,
    this.state = 'IN_PROGRESS',
  });
  final int? id;
  final int companyId;
  final int employeeId;
  final DateTime? punchIn;
  final DateTime? punchOut;
  final String state;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'employee_id': employeeId,
    'punch_in': punchIn?.toIso8601String(),
    'punch_out': punchOut?.toIso8601String(),
    'state': state,
  };
  factory HrmAttendanceRecord.fromMap(Map<String, dynamic> m) =>
      HrmAttendanceRecord(
        id: (m['id'] as num?)?.toInt(),
        companyId: (m['company_id'] as num).toInt(),
        employeeId: (m['employee_id'] as num).toInt(),
        punchIn: DateTime.tryParse(m['punch_in']?.toString() ?? ''),
        punchOut: DateTime.tryParse(m['punch_out']?.toString() ?? ''),
        state: m['state']?.toString() ?? 'IN_PROGRESS',
      );
}
