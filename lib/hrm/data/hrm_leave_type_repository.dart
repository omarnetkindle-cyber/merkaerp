import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_leave_type.dart';

abstract class HrmLeaveTypeRepository {
  Future<List<HrmLeaveType>> findAll();
  Future<int> save(HrmLeaveType value);
}

class SqliteHrmLeaveTypeRepository implements HrmLeaveTypeRepository {
  SqliteHrmLeaveTypeRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<List<HrmLeaveType>> findAll() async => (await _tenant.query(
    'hrm_leave_types',
    query: const TenantQuery(where: 'active = 1', orderBy: 'name ASC'),
  )).map(HrmLeaveType.fromMap).toList();
  @override
  Future<int> save(HrmLeaveType value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_leave_types', data);
    data.remove('id');
    return _tenant.update(
      'hrm_leave_types',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
