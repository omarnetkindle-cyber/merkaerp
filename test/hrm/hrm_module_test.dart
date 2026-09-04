import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/hrm/application/hrm_attendance_service.dart';
import 'package:merka_erp/hrm/application/hrm_employee_service.dart';
import 'package:merka_erp/hrm/application/hrm_job_title_service.dart';
import 'package:merka_erp/hrm/application/hrm_leave_entitlement_service.dart';
import 'package:merka_erp/hrm/application/hrm_leave_request_service.dart';
import 'package:merka_erp/hrm/application/hrm_leave_service.dart';
import 'package:merka_erp/hrm/application/hrm_leave_type_service.dart';
import 'package:merka_erp/hrm/domain/hrm_attendance_record.dart';
import 'package:merka_erp/hrm/domain/hrm_employee.dart';
import 'package:merka_erp/hrm/domain/hrm_job_title.dart';
import 'package:merka_erp/hrm/domain/hrm_leave.dart';
import 'package:merka_erp/hrm/domain/hrm_leave_entitlement.dart';
import 'package:merka_erp/hrm/domain/hrm_leave_request.dart';
import 'package:merka_erp/hrm/domain/hrm_leave_type.dart';

void main() {
  late Directory dir;
  late int companyId;
  late int employeeId;
  late int leaveTypeId;
  late int noEntitlementTypeId;
  late int noBalanceTypeId;
  late DateTime periodFrom;
  late DateTime periodTo;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    dir = await Directory.systemTemp.createTemp('merkaerp_hrm_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final jobId = await HrmJobTitleService().create(
      HrmJobTitle(
        companyId: companyId,
        title: 'Analista HRM',
        contractualHoursPerDay: 8,
      ),
    );
    employeeId = await HrmEmployeeService().create(
      HrmEmployee(
        companyId: companyId,
        name: 'Empleado HRM',
        document: 'HRM-001',
        jobTitleId: jobId,
        jobTitle: 'Analista HRM',
      ),
    );
    final types = await HrmLeaveTypeService().list();
    expect(types, hasLength(8));
    leaveTypeId = types.first.id!;
    noEntitlementTypeId = types
        .singleWhere((type) => type.code == 'permiso_no_remunerado')
        .id!;
    noBalanceTypeId = types.firstWhere((type) => type.id != leaveTypeId).id!;
    periodFrom = DateTime(DateTime.now().year, 1, 1);
    periodTo = DateTime(DateTime.now().year, 12, 31, 23, 59, 59);
    await HrmLeaveEntitlementService().create(
      HrmLeaveEntitlement(
        companyId: companyId,
        employeeId: employeeId,
        leaveTypeId: leaveTypeId,
        daysTotal: 5,
        periodFrom: periodFrom,
        periodTo: periodTo,
      ),
    );
    expect(
      await db.query('empleados', where: 'id = ?', whereArgs: [employeeId]),
      isNotEmpty,
    );
    final job = (await HrmJobTitleService().list()).single;
    expect(job.contractualHoursPerDay, 8);
  });

  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dir.delete(recursive: true);
  });

  test('crea solicitud, ausencia, saldo y asistencia', () async {
    final requestId = await HrmLeaveRequestService().create(
      HrmLeaveRequest(
        companyId: companyId,
        employeeId: employeeId,
        leaveTypeId: leaveTypeId,
        dateApplied: DateTime.now(),
        startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
          comments: 'Descanso',
      ),
    );
    final leaveId = await HrmLeaveService().create(
      HrmLeave(
        companyId: companyId,
        leaveRequestId: requestId,
        employeeId: employeeId,
        leaveTypeId: leaveTypeId,
        date: DateTime(DateTime.now().year, 2, 3),
        lengthDays: 2,
      ),
    );
    await HrmLeaveService().approve(leaveId: leaveId, approvedBy: 99);
    final approved = await HrmLeaveService().approvedForPeriod(
      from: DateTime(DateTime.now().year, 2, 1),
      to: DateTime(DateTime.now().year, 3, 1),
    );
    expect(approved.single['length_days'], 2);
    expect(approved.single['employee_name'], 'Empleado HRM');
    final entitlement = (await HrmLeaveEntitlementService().listForEmployee(
      employeeId,
    )).single;
    expect(entitlement.daysUsed, 2);
    final attendanceId = await HrmAttendanceService().record(
      HrmAttendanceRecord(
        companyId: companyId,
        employeeId: employeeId,
        punchIn: DateTime.now(),
        state: 'IN_PROGRESS',
      ),
    );
    expect(attendanceId, greaterThan(0));
    final attendance = await db.query(
      'hrm_attendance_records',
      where: 'id = ?',
      whereArgs: [attendanceId],
    );
    expect(attendance.single['state'], 'IN_PROGRESS');
    expect(attendance.single['punch_out'], isNull);
  });

  test(
    'conserva metadatos OrangeHRM y valida jefe de la misma empresa',
    () async {
      final subordinateId = await HrmEmployeeService().create(
        HrmEmployee(
          companyId: companyId,
          name: 'Empleado subordinado',
          document: 'HRM-002',
          birthdate: DateTime(1990, 4, 5),
          gender: 'F',
          maritalStatus: 'soltero',
          salaryGrade: 'G-5',
          managerId: employeeId,
        ),
      );
      final subordinate = await HrmEmployeeService().findById(subordinateId);
      expect(subordinate?.salaryGrade, 'G-5');
      expect(subordinate?.managerId, employeeId);
      expect(subordinate?.birthdate, DateTime(1990, 4, 5));
      await expectLater(
        () => HrmEmployeeService().create(
          HrmEmployee(
            companyId: companyId,
            name: 'Jefe invalido',
            managerId: employeeId + 999999,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('LeaveType conserva bandera de reporte sin entitlement', () async {
    final type = HrmLeaveType(
      companyId: companyId,
      code: 'tipo_reporte_hrm',
      name: 'Tipo reporte HRM',
      requiresEntitlement: false,
      excludeInReportsIfNoEntitlement: true,
    );
    final id = await HrmLeaveTypeService().create(type);
    final stored = (await HrmLeaveTypeService().list()).singleWhere(
      (item) => item.id == id,
    );
    expect(stored.requiresEntitlement, isFalse);
    expect(stored.excludeInReportsIfNoEntitlement, isTrue);
  });

  test('un cargo productivo exige jornada contractual', () async {
    await expectLater(
      () => HrmJobTitleService().create(
        HrmJobTitle(
          companyId: companyId,
          title: 'Cargo productivo sin jornada',
          mrpWorkstationId: 1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'bloquea aprobación cuando days_used + length_days excede days_total',
    () async {
      final requestId = await HrmLeaveRequestService().create(
        HrmLeaveRequest(
          companyId: companyId,
          employeeId: employeeId,
          leaveTypeId: leaveTypeId,
          dateApplied: DateTime.now(),
        startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
      );
      final leaveId = await HrmLeaveService().create(
        HrmLeave(
          companyId: companyId,
          leaveRequestId: requestId,
          employeeId: employeeId,
          leaveTypeId: leaveTypeId,
          date: DateTime(DateTime.now().year, 3, 3),
          lengthDays: 4,
        ),
      );
      await expectLater(
        () => HrmLeaveService().approve(leaveId: leaveId, approvedBy: 99),
        throwsStateError,
      );
    },
  );

  test(
    'aprueba un tipo que no requiere entitlement sin descontar saldo',
    () async {
      final requestId = await HrmLeaveRequestService().create(
        HrmLeaveRequest(
          companyId: companyId,
          employeeId: employeeId,
          leaveTypeId: noEntitlementTypeId,
          dateApplied: DateTime.now(),
        startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
      );
      final leaveId = await HrmLeaveService().create(
        HrmLeave(
          companyId: companyId,
          leaveRequestId: requestId,
          employeeId: employeeId,
          leaveTypeId: noEntitlementTypeId,
          date: DateTime(DateTime.now().year, 4, 4),
          lengthDays: 3,
        ),
      );
      await HrmLeaveService().approve(leaveId: leaveId, approvedBy: 101);
      final row = (await db.query(
        'hrm_leaves',
        where: 'id = ?',
        whereArgs: [leaveId],
      )).single;
      expect(row['status'], 'aprobado');
      expect(row['reviewed_by'], 101);
      expect(
        await db.query(
          'hrm_leave_entitlements',
          where: 'employee_id = ? AND leave_type_id = ?',
          whereArgs: [employeeId, noEntitlementTypeId],
        ),
        isEmpty,
      );
    },
  );

  test('bloquea ausencia solapada con otra ya aprobada', () async {
    Future<int> createLeave(DateTime date) async {
      final requestId = await HrmLeaveRequestService().create(
        HrmLeaveRequest(
          companyId: companyId,
          employeeId: employeeId,
          leaveTypeId: leaveTypeId,
          dateApplied: DateTime.now(),
        startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
      );
      return HrmLeaveService().create(
        HrmLeave(
          companyId: companyId,
          leaveRequestId: requestId,
          employeeId: employeeId,
          leaveTypeId: leaveTypeId,
          date: date,
          lengthDays: 1,
        ),
      );
    }

    final firstId = await createLeave(DateTime(DateTime.now().year, 5, 5));
    await HrmLeaveService().approve(leaveId: firstId, approvedBy: 102);
    final overlappingId = await createLeave(
      DateTime(DateTime.now().year, 5, 5),
    );
    await expectLater(
      () => HrmLeaveService().approve(leaveId: overlappingId, approvedBy: 102),
      throwsStateError,
    );
    expect(
      (await db.query(
        'hrm_leaves',
        where: 'id = ?',
        whereArgs: [overlappingId],
      )).single['status'],
      'pendiente',
    );
  });

  test('bloquea aprobacion sin entitlement configurado', () async {
    final requestId = await HrmLeaveRequestService().create(
      HrmLeaveRequest(
        companyId: companyId,
        employeeId: employeeId,
        leaveTypeId: noBalanceTypeId,
        dateApplied: DateTime.now(),
      startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
    );
    final leaveId = await HrmLeaveService().create(
      HrmLeave(
        companyId: companyId,
        leaveRequestId: requestId,
        employeeId: employeeId,
        leaveTypeId: noBalanceTypeId,
        date: DateTime(DateTime.now().year, 6, 6),
        lengthDays: 1,
      ),
    );
    await expectLater(
      () => HrmLeaveService().approve(leaveId: leaveId, approvedBy: 103),
      throwsStateError,
    );
    expect(
      (await db.query(
        'hrm_leaves',
        where: 'id = ?',
        whereArgs: [leaveId],
      )).single['status'],
      'pendiente',
    );
  });

  test('rechazo deja responsable, fecha y motivo auditables', () async {
    final requestId = await HrmLeaveRequestService().create(
      HrmLeaveRequest(
        companyId: companyId,
        employeeId: employeeId,
        leaveTypeId: noEntitlementTypeId,
        dateApplied: DateTime.now(),
      startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
    );
    final leaveId = await HrmLeaveService().create(
      HrmLeave(
        companyId: companyId,
        leaveRequestId: requestId,
        employeeId: employeeId,
        leaveTypeId: noEntitlementTypeId,
        date: DateTime(DateTime.now().year, 7, 7),
        lengthDays: 1,
      ),
    );
    await HrmLeaveService().reject(
      leaveId: leaveId,
      rejectedBy: 104,
      reason: 'Soporte incompleto',
    );
    final row = (await db.query(
      'hrm_leaves',
      where: 'id = ?',
      whereArgs: [leaveId],
    )).single;
    expect(row['status'], 'rechazado');
    expect(row['reviewed_by'], 104);
    expect(row['reviewed_at'], isNotNull);
    expect(row['rejection_reason'], 'Soporte incompleto');
  });

  test('no permite terminar empleado con ausencias pendientes', () async {
    final requestId = await HrmLeaveRequestService().create(
      HrmLeaveRequest(
        companyId: companyId,
        employeeId: employeeId,
        leaveTypeId: noEntitlementTypeId,
        dateApplied: DateTime.now(),
      startDate: DateTime.now().add(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 3)),
        ),
    );
    await HrmLeaveService().create(
      HrmLeave(
        companyId: companyId,
        leaveRequestId: requestId,
        employeeId: employeeId,
        leaveTypeId: noEntitlementTypeId,
        date: DateTime(DateTime.now().year, 8, 8),
        lengthDays: 1,
      ),
    );
    await expectLater(
      () => HrmEmployeeService().terminate(
        employeeId: employeeId,
        terminationDate: DateTime(DateTime.now().year, 12, 31),
      ),
      throwsStateError,
    );
    expect((await HrmEmployeeService().findById(employeeId))?.status, 'activo');
  });
}
