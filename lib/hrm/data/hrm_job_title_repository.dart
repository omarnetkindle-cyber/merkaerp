import 'package:sqflite/sqflite.dart';
import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/hrm_job_title.dart';

abstract class HrmJobTitleRepository {
  Future<List<HrmJobTitle>> findAll();
  Future<int> save(HrmJobTitle value);
}

class SqliteHrmJobTitleRepository implements HrmJobTitleRepository {
  SqliteHrmJobTitleRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );
  final TenantDatabaseGateway _tenant;
  @override
  Future<List<HrmJobTitle>> findAll() async => (await _tenant.query(
    'hrm_job_titles',
    query: const TenantQuery(where: 'is_deleted = 0', orderBy: 'title ASC'),
  )).map(HrmJobTitle.fromMap).toList();
  @override
  Future<int> save(HrmJobTitle value) async {
    final data = value.toMap()..remove('company_id');
    if (value.id == null) return _tenant.insert('hrm_job_titles', data);
    data.remove('id');
    return _tenant.update(
      'hrm_job_titles',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [value.id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
