import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_attendance_record.dart';

abstract class HrmAttendanceRecordRepository {
  Future<int> save(HrmAttendanceRecord value);
  Future<List<HrmAttendanceRecord>> findForEmployee(int employeeId);
}

class SqliteHrmAttendanceRecordRepository
    implements HrmAttendanceRecordRepository {
  SqliteHrmAttendanceRecordRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<int> save(HrmAttendanceRecord value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_attendance_records', data);
    data.remove('id');
    return _tenant.update(
      'hrm_attendance_records',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<List<HrmAttendanceRecord>> findForEmployee(int employeeId) async =>
      (await _tenant.query(
        'hrm_attendance_records',
        query: TenantQuery(
          where: 'employee_id = ?',
          whereArgs: [employeeId],
          orderBy: 'punch_in DESC',
        ),
      )).map(HrmAttendanceRecord.fromMap).toList();
}
