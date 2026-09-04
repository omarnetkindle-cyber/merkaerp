// Solicitud de ausencia creada por el empleado (o HR en su nombre).
// startDate/endDate definen el rango solicitado.
// Al aprobarse, el motor crea uno o más HrmLeave con los días
// correspondientes dentro de ese rango.
class HrmLeaveRequest {
  const HrmLeaveRequest({
    this.id,
    required this.companyId,
    required this.employeeId,
    required this.leaveTypeId,
    required this.dateApplied,
    required this.startDate,
    required this.endDate,
    this.comments,
    this.status = 'pendiente',
  });

  final int? id;
  final int companyId;
  final int employeeId;
  final int leaveTypeId;
  final DateTime dateApplied;
  /// Primer día de la ausencia solicitada (inclusive).
  final DateTime startDate;
  /// Último día de la ausencia solicitada (inclusive).
  final DateTime endDate;
  final String? comments;
  final String status;

  /// Días hábiles totales solicitados (cálculo simple calendario).
  double get lengthDays {
    if (endDate.isBefore(startDate)) return 0;
    return endDate.difference(startDate).inDays + 1;
  }

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'employee_id': employeeId,
    'leave_type_id': leaveTypeId,
    'date_applied': dateApplied.toIso8601String(),
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'comments': comments,
    'status': status,
  };

  factory HrmLeaveRequest.fromMap(Map<String, dynamic> m) => HrmLeaveRequest(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    employeeId: (m['employee_id'] as num).toInt(),
    leaveTypeId: (m['leave_type_id'] as num).toInt(),
    dateApplied: DateTime.parse(m['date_applied'].toString()),
    startDate: DateTime.tryParse(m['start_date']?.toString() ?? '') ??
        DateTime.parse(m['date_applied'].toString()),
    endDate: DateTime.tryParse(m['end_date']?.toString() ?? '') ??
        DateTime.parse(m['date_applied'].toString()),
    comments: m['comments']?.toString(),
    status: m['status']?.toString() ?? 'pendiente',
  );
}
