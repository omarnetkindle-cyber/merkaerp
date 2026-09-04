import '../../db_helper.dart';
import '../data/hrm_leave_repository.dart';
import '../data/hrm_leave_request_repository.dart';
import '../domain/hrm_leave.dart';
import '../domain/hrm_leave_request.dart';

class HrmLeaveRequestService {
  HrmLeaveRequestService({
    HrmLeaveRequestRepository? requestRepository,
    HrmLeaveRepository? leaveRepository,
  })  : _requests = requestRepository ?? SqliteHrmLeaveRequestRepository(),
        _leaves = leaveRepository ?? SqliteHrmLeaveRepository();

  final HrmLeaveRequestRepository _requests;
  final HrmLeaveRepository _leaves;

  /// Crea una solicitud nueva en estado 'pendiente' y genera automáticamente
  /// el registro HrmLeave correspondiente (también pendiente de aprobación).
  /// Retorna el id de la solicitud creada.
  Future<int> create(HrmLeaveRequest value) async {
    if (value.companyId <= 0 ||
        value.employeeId <= 0 ||
        value.leaveTypeId <= 0) {
      throw ArgumentError(
        'La solicitud requiere empresa, empleado y tipo válidos.',
      );
    }
    if (value.status != 'pendiente') {
      throw ArgumentError('Una solicitud nueva debe iniciar como pendiente.');
    }
    if (value.endDate.isBefore(value.startDate)) {
      throw ArgumentError(
        'La fecha de fin no puede ser anterior a la fecha de inicio.',
      );
    }
    if (value.lengthDays <= 0) {
      throw ArgumentError('La solicitud debe abarcar al menos un día.');
    }

    // 1. Persistir la solicitud.
    final requestId = await _requests.save(value);

    // 2. Crear el HrmLeave (entrada en el calendario/aprobaciones).
    final leave = HrmLeave(
      companyId: value.companyId,
      leaveRequestId: requestId,
      employeeId: value.employeeId,
      leaveTypeId: value.leaveTypeId,
      date: value.startDate,
      lengthDays: value.lengthDays,
      status: 'pendiente',
      comments: value.comments,
    );
    await _leaves.save(leave);

    return requestId;
  }

  Future<List<HrmLeaveRequest>> listForEmployee(int employeeId) =>
      _requests.findForEmployee(employeeId);

  /// Lista solicitudes pendientes junto con datos del empleado y tipo de ausencia.
  Future<List<Map<String, dynamic>>> pendingWithDetails() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return db.rawQuery('''
      SELECT r.*, e.nombre AS employee_name, t.name AS leave_type_name
      FROM hrm_leave_requests r
      JOIN empleados e ON e.id = r.employee_id AND e.company_id = r.company_id
      JOIN hrm_leave_types t ON t.id = r.leave_type_id AND t.company_id = r.company_id
      WHERE r.company_id = ? AND r.status = 'pendiente'
      ORDER BY r.date_applied DESC
    ''', [companyId]);
  }
}
