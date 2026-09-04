import 'package:sqflite/sqflite.dart';
import '../../db_helper.dart';
import '../data/hrm_leave_type_repository.dart';
import '../database/schema_hrm.dart';
import '../domain/hrm_leave_type.dart';

class HrmLeaveTypeService {
  HrmLeaveTypeService({HrmLeaveTypeRepository? repository})
    : _repository = repository ?? SqliteHrmLeaveTypeRepository();
  final HrmLeaveTypeRepository _repository;
  Future<int> create(HrmLeaveType value) => _repository.save(value);
  Future<List<HrmLeaveType>> list() async {
    await seedDefaults();
    return _repository.findAll();
  }

  Future<void> seedDefaults() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    for (final item in SchemaHrm.leaveTypes) {
      await db.insert('hrm_leave_types', {
        'company_id': companyId,
        ...item,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
