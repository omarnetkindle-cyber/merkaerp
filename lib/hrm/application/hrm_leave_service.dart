import '../../db_helper.dart';
import '../data/hrm_leave_repository.dart';
import '../domain/hrm_leave.dart';
import 'package:sqflite/sqflite.dart';

class HrmLeaveService {
  HrmLeaveService({HrmLeaveRepository? repository})
    : _repository = repository ?? SqliteHrmLeaveRepository();

  final HrmLeaveRepository _repository;

  Future<int> create(HrmLeave value) async {
    if (value.companyId <= 0 ||
        value.employeeId <= 0 ||
        value.leaveTypeId <= 0) {
      throw ArgumentError(
        'La ausencia requiere empresa, empleado y tipo validos.',
      );
    }
    if (value.lengthDays <= 0) {
      throw ArgumentError(
        'La ausencia debe tener una duracion mayor que cero.',
      );
    }
    if (value.status != 'pendiente') {
      throw ArgumentError('Una ausencia nueva debe iniciar como pendiente.');
    }
    return _repository.save(value);
  }

  Future<List<HrmLeave>> listForEmployee(int employeeId) {
    if (employeeId <= 0) {
      throw ArgumentError('El empleado debe tener un identificador valido.');
    }
    return _repository.findForEmployee(employeeId);
  }

  /// Aprueba de forma atomica. Los tipos sin entitlement no descuentan saldo.
  Future<void> approve({required int leaveId, required int approvedBy}) async {
    _validateActor(approvedBy);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.transaction((txn) async {
      final leave = await _pendingLeave(txn, companyId, leaveId);
      final leaveTypeRows = await txn.query(
        'hrm_leave_types',
        where: 'company_id = ? AND id = ?',
        whereArgs: [companyId, leave['leave_type_id']],
        limit: 1,
      );
      if (leaveTypeRows.isEmpty) {
        throw StateError('El tipo de ausencia no existe en la empresa activa.');
      }
      final requiresEntitlement =
          (leaveTypeRows.single['requires_entitlement'] as num?)?.toInt() != 0;

      if (requiresEntitlement) {
        await _consumeEntitlement(txn, companyId, leave);
      }
      await _rejectOverlap(txn, companyId, leave);

      final reviewedAt = DateTime.now().toIso8601String();
      await txn.update(
        'hrm_leaves',
        {
          'status': 'aprobado',
          'approved_by': approvedBy,
          'reviewed_by': approvedBy,
          'reviewed_at': reviewedAt,
          'rejection_reason': null,
        },
        where: 'id = ? AND company_id = ?',
        whereArgs: [leaveId, companyId],
      );
      await txn.update(
        'hrm_leave_requests',
        {'status': 'aprobado'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [leave['leave_request_id'], companyId],
      );
    });
  }

  Future<void> reject({
    required int leaveId,
    required int rejectedBy,
    required String reason,
  }) async {
    _validateActor(rejectedBy);
    if (reason.trim().isEmpty) {
      throw ArgumentError('Debe indicar el motivo del rechazo.');
    }
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.transaction((txn) async {
      final leave = await _pendingLeave(txn, companyId, leaveId);
      final reviewedAt = DateTime.now().toIso8601String();
      await txn.update(
        'hrm_leaves',
        {
          'status': 'rechazado',
          'approved_by': null,
          'reviewed_by': rejectedBy,
          'reviewed_at': reviewedAt,
          'rejection_reason': reason.trim(),
        },
        where: 'id = ? AND company_id = ?',
        whereArgs: [leaveId, companyId],
      );
      await txn.update(
        'hrm_leave_requests',
        {'status': 'rechazado'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [leave['leave_request_id'], companyId],
      );
    });
  }

  /// Consulta local consumible por nomina y por futuros reportes DIAN.
  Future<List<Map<String, dynamic>>> approvedForPeriod({
    required DateTime from,
    required DateTime to,
    int? employeeId,
    DatabaseExecutor? executor,
    int? companyId,
  }) async {
    final db = executor ?? await DatabaseHelper.instance.database;
    final activeCompanyId =
        companyId ?? await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final employeeFilter = employeeId == null ? '' : ' AND l.employee_id = ?';
    final employeeArgs = employeeId == null
        ? const <dynamic>[]
        : <dynamic>[employeeId];
    final args = <dynamic>[
      activeCompanyId,
      from.toIso8601String(),
      to.toIso8601String(),
      ...employeeArgs,
    ];
    return db.rawQuery('''
      SELECT l.employee_id, MIN(l.date) AS date,
             SUM(l.length_days) AS length_days,
             COUNT(l.id) AS leave_count,
             e.nombre AS employee_name, e.documento AS employee_document,
             t.code AS leave_code, t.name AS leave_name,
             t.requires_entitlement
      FROM hrm_leaves l
      JOIN empleados e ON e.id = l.employee_id AND e.company_id = l.company_id
      JOIN hrm_leave_types t ON t.id = l.leave_type_id AND t.company_id = l.company_id
      WHERE l.company_id = ? AND l.status = 'aprobado'
        AND l.date >= ? AND l.date < ?$employeeFilter
      GROUP BY l.employee_id, e.nombre, e.documento,
               t.code, t.name, t.requires_entitlement
      ORDER BY MIN(l.date), e.nombre
    ''', args);
  }

  Future<List<Map<String, dynamic>>> pendingForApproval() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return db.rawQuery(
      '''
      SELECT l.*, e.nombre AS employee_name, t.code AS leave_code, t.name AS leave_name
      FROM hrm_leaves l
      JOIN empleados e ON e.id = l.employee_id AND e.company_id = l.company_id
      JOIN hrm_leave_types t ON t.id = l.leave_type_id AND t.company_id = l.company_id
      WHERE l.company_id = ? AND l.status = 'pendiente'
      ORDER BY l.date, e.nombre
    ''',
      [companyId],
    );
  }

  Future<Map<String, dynamic>> _pendingLeave(
    dynamic txn,
    int companyId,
    int leaveId,
  ) async {
    final rows = await txn.query(
      'hrm_leaves',
      where: 'id = ? AND company_id = ?',
      whereArgs: [leaveId, companyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('La ausencia no existe en la empresa activa.');
    }
    final leave = rows.single;
    if (leave['status'] != 'pendiente') {
      throw StateError('Solo se puede revisar una ausencia pendiente.');
    }
    return leave;
  }

  Future<void> _consumeEntitlement(
    dynamic txn,
    int companyId,
    Map<String, dynamic> leave,
  ) async {
    final entitlements = await txn.query(
      'hrm_leave_entitlements',
      where:
          'company_id = ? AND employee_id = ? AND leave_type_id = ? AND period_from <= ? AND period_to >= ?',
      whereArgs: [
        companyId,
        leave['employee_id'],
        leave['leave_type_id'],
        leave['date'],
        leave['date'],
      ],
      limit: 1,
    );
    if (entitlements.isEmpty) {
      throw StateError(
        'No existe saldo asignado para el periodo de la ausencia.',
      );
    }
    final entitlement = entitlements.single;
    final used = (entitlement['days_used'] as num).toDouble();
    final total = (entitlement['days_total'] as num).toDouble();
    final length = (leave['length_days'] as num).toDouble();
    if (used + length > total) {
      throw StateError(
        'Saldo insuficiente: days_used + length_days excede days_total.',
      );
    }
    await txn.update(
      'hrm_leave_entitlements',
      {'days_used': used + length},
      where: 'id = ? AND company_id = ?',
      whereArgs: [entitlement['id'], companyId],
    );
  }

  Future<void> _rejectOverlap(
    dynamic txn,
    int companyId,
    Map<String, dynamic> leave,
  ) async {
    final start = DateTime.parse(leave['date'].toString());
    final end = _endDate(start, (leave['length_days'] as num).toDouble());
    final approved = await txn.query(
      'hrm_leaves',
      where: 'company_id = ? AND employee_id = ? AND status = ? AND id != ?',
      whereArgs: [companyId, leave['employee_id'], 'aprobado', leave['id']],
    );
    for (final existing in approved) {
      final existingStart = DateTime.parse(existing['date'].toString());
      final existingEnd = _endDate(
        existingStart,
        (existing['length_days'] as num).toDouble(),
      );
      if (start.isBefore(existingEnd) && existingStart.isBefore(end)) {
        throw StateError(
          'La ausencia se solapa con otra ausencia aprobada del empleado.',
        );
      }
    }
  }

  DateTime _endDate(DateTime start, double lengthDays) {
    return start.add(
      Duration(
        microseconds: (lengthDays * Duration.microsecondsPerDay).round(),
      ),
    );
  }

  void _validateActor(int actorId) {
    if (actorId <= 0) {
      throw ArgumentError('El aprobador debe tener un usuario valido.');
    }
  }
}
