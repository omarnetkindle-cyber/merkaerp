class HrmLeave {
  const HrmLeave({
    this.id,
    required this.companyId,
    required this.leaveRequestId,
    required this.employeeId,
    required this.leaveTypeId,
    required this.date,
    required this.lengthDays,
    this.durationType = 'dia_completo',
    this.status = 'pendiente',
    this.approvedBy,
    this.comments,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });
  final int? id;
  final int companyId;
  final int leaveRequestId;
  final int employeeId;
  final int leaveTypeId;
  final DateTime date;
  final double lengthDays;
  final String durationType;
  final String status;
  final int? approvedBy;
  final String? comments;
  final int? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'leave_request_id': leaveRequestId,
    'employee_id': employeeId,
    'leave_type_id': leaveTypeId,
    'date': date.toIso8601String(),
    'length_days': lengthDays,
    'duration_type': durationType,
    'status': status,
    'approved_by': approvedBy,
    'comments': comments,
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt?.toIso8601String(),
    'rejection_reason': rejectionReason,
  };
  factory HrmLeave.fromMap(Map<String, dynamic> m) => HrmLeave(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    leaveRequestId: (m['leave_request_id'] as num).toInt(),
    employeeId: (m['employee_id'] as num).toInt(),
    leaveTypeId: (m['leave_type_id'] as num).toInt(),
    date: DateTime.parse(m['date'].toString()),
    lengthDays: (m['length_days'] as num).toDouble(),
    durationType: m['duration_type']?.toString() ?? 'dia_completo',
    status: m['status']?.toString() ?? 'pendiente',
    approvedBy: (m['approved_by'] as num?)?.toInt(),
    comments: m['comments']?.toString(),
    reviewedBy: (m['reviewed_by'] as num?)?.toInt(),
    reviewedAt: DateTime.tryParse(m['reviewed_at']?.toString() ?? ''),
    rejectionReason: m['rejection_reason']?.toString(),
  );
}
