import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_leave_request.dart';

abstract class HrmLeaveRequestRepository {
  Future<int> save(HrmLeaveRequest value);
  Future<List<HrmLeaveRequest>> findForEmployee(int employeeId);
}

class SqliteHrmLeaveRequestRepository implements HrmLeaveRequestRepository {
  SqliteHrmLeaveRequestRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<int> save(HrmLeaveRequest value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_leave_requests', data);
    data.remove('id');
    return _tenant.update(
      'hrm_leave_requests',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<List<HrmLeaveRequest>> findForEmployee(int employeeId) async =>
      (await _tenant.query(
        'hrm_leave_requests',
        query: TenantQuery(
          where: 'employee_id = ?',
          whereArgs: [employeeId],
          orderBy: 'date_applied DESC',
        ),
      )).map(HrmLeaveRequest.fromMap).toList();
}
