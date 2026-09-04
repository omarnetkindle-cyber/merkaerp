import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_employee.dart';

abstract class HrmEmployeeRepository {
  Future<List<HrmEmployee>> findAll();
  Future<HrmEmployee?> findById(int id);
  Future<int> save(HrmEmployee value);
}

class SqliteHrmEmployeeRepository implements HrmEmployeeRepository {
  SqliteHrmEmployeeRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<List<HrmEmployee>> findAll() async => (await _tenant.query(
    'empleados',
    query: const TenantQuery(orderBy: 'activo DESC, nombre ASC'),
  )).map(HrmEmployee.fromMap).toList();
  @override
  Future<HrmEmployee?> findById(int id) async {
    final row = await _tenant.findById('empleados', id);
    return row == null ? null : HrmEmployee.fromMap(row);
  }

  @override
  Future<int> save(HrmEmployee value) async {
    final data = value.toMap();
    if (value.id == null) return _tenant.insert('empleados', data);
    data.remove('company_id');
    data.remove('id');
    return _tenant.update(
      'empleados',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
