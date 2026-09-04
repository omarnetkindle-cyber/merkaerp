import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_leave.dart';

abstract class HrmLeaveRepository {
  Future<int> save(HrmLeave value);
  Future<List<HrmLeave>> findForEmployee(int employeeId);
}

class SqliteHrmLeaveRepository implements HrmLeaveRepository {
  SqliteHrmLeaveRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<int> save(HrmLeave value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_leaves', data);
    data.remove('id');
    return _tenant.update(
      'hrm_leaves',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<List<HrmLeave>> findForEmployee(int employeeId) async =>
      (await _tenant.query(
        'hrm_leaves',
        query: TenantQuery(
          where: 'employee_id = ?',
          whereArgs: [employeeId],
          orderBy: 'date ASC',
        ),
      )).map(HrmLeave.fromMap).toList();
}
