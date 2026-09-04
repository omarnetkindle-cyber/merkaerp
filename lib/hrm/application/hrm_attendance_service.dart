import '../data/hrm_attendance_record_repository.dart';
import '../domain/hrm_attendance_record.dart';
import 'hrm_employee_service.dart';

class HrmAttendanceService {
  HrmAttendanceService({HrmAttendanceRecordRepository? repository})
    : _repository = repository ?? SqliteHrmAttendanceRecordRepository();
  final HrmAttendanceRecordRepository _repository;
  Future<int> record(HrmAttendanceRecord value) async {
    if (value.employeeId <= 0) {
      throw ArgumentError('La asistencia requiere un empleado valido.');
    }
    if (value.punchIn == null && value.punchOut != null) {
      throw ArgumentError('No puede existir salida sin entrada.');
    }
    if (value.punchIn != null &&
        value.punchOut != null &&
        value.punchOut!.isBefore(value.punchIn!)) {
      throw ArgumentError('La salida no puede ser anterior a la entrada.');
    }
    final employee = await HrmEmployeeService().findById(value.employeeId);
    if (employee == null) {
      throw StateError('El empleado no existe en la empresa activa.');
    }
    return _repository.save(value);
  }

  Future<List<HrmAttendanceRecord>> listForEmployee(int employeeId) =>
      _repository.findForEmployee(employeeId);
}
