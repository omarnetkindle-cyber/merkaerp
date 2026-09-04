import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_leave_entitlement.dart';

abstract class HrmLeaveEntitlementRepository {
  Future<List<HrmLeaveEntitlement>> findForEmployee(int employeeId);
  Future<int> save(HrmLeaveEntitlement value);
}

class SqliteHrmLeaveEntitlementRepository
    implements HrmLeaveEntitlementRepository {
  SqliteHrmLeaveEntitlementRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<List<HrmLeaveEntitlement>> findForEmployee(int employeeId) async =>
      (await _tenant.query(
        'hrm_leave_entitlements',
        query: TenantQuery(
          where: 'employee_id = ?',
          whereArgs: [employeeId],
          orderBy: 'period_from DESC',
        ),
      )).map(HrmLeaveEntitlement.fromMap).toList();
  @override
  Future<int> save(HrmLeaveEntitlement value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_leave_entitlements', data);
    data.remove('id');
    return _tenant.update(
      'hrm_leave_entitlements',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
