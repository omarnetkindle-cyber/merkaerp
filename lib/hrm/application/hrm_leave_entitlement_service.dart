import '../data/hrm_leave_entitlement_repository.dart';
import '../domain/hrm_leave_entitlement.dart';

class HrmLeaveEntitlementService {
  HrmLeaveEntitlementService({HrmLeaveEntitlementRepository? repository})
    : _repository = repository ?? SqliteHrmLeaveEntitlementRepository();
  final HrmLeaveEntitlementRepository _repository;
  Future<int> create(HrmLeaveEntitlement value) {
    if (value.companyId <= 0 ||
        value.employeeId <= 0 ||
        value.leaveTypeId <= 0) {
      throw ArgumentError('El saldo requiere referencias validas.');
    }
    if (value.daysTotal < 0 || value.daysUsed < 0) {
      throw ArgumentError('Los dias de saldo no pueden ser negativos.');
    }
    if (value.daysUsed > value.daysTotal) {
      throw ArgumentError('Los dias usados no pueden exceder el total.');
    }
    if (value.periodTo.isBefore(value.periodFrom)) {
      throw ArgumentError('El periodo de saldo tiene fechas invalidas.');
    }
    return _repository.save(value);
  }

  Future<List<HrmLeaveEntitlement>> listForEmployee(int employeeId) =>
      _repository.findForEmployee(employeeId);
}
