import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/hrm/database/schema_hrm.dart';
import 'package:merka_erp/hrm/application/hrm_employee_service.dart';
import 'package:merka_erp/hrm/domain/hrm_employee.dart';

void main() {
  late Directory dir;
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    dir = await Directory.systemTemp.createTemp('merkaerp_hrm_compat_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await DatabaseHelper.instance.database;
  });
  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dir.delete(recursive: true);
  });

  test(
    'la migracion HRM conserva empleados y filas consumibles por nomina',
    () async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      await SchemaHrm.crearTablas(db);
      final id = await HrmEmployeeService().create(
        HrmEmployee(
          companyId: companyId,
          name: 'Empleado compatibilidad',
          document: 'COMP-1',
        ),
      );
      await db.insert('nomina_liquidaciones', {
        'company_id': companyId,
        'empleado_id': id,
        'empleado': 'Empleado compatibilidad',
        'periodo': '2026-08',
        'salario_base': 100000,
        'total_devengado': 100000,
        'total_deducciones': 0,
        'neto_pagar': 100000,
        'aportes_empleador': 0,
        'salud_empleado': 0,
        'salud_empleador': 0,
        'pension_empleado': 0,
        'pension_empleador': 0,
        'fsp': 0,
        'arl': 0,
        'parafiscal_sena': 0,
        'parafiscal_icbf': 0,
        'parafiscal_caja': 0,
        'cesantias': 0,
        'prima_servicios': 0,
        'intereses_cesantias': 0,
        'vacaciones': 0,
        'retefuente': 0,
        'estado': 'liquidada',
        'fecha': DateTime.now().toIso8601String(),
      });
      final employee = (await HrmEmployeeService().findById(id))!;
      final payroll = await db.query(
        'nomina_liquidaciones',
        where: 'empleado_id = ?',
        whereArgs: [id],
      );
      expect(employee.name, 'Empleado compatibilidad');
      expect(payroll.single['neto_pagar'], 100000);
      await DatabaseHelper.instance.migrarDBForTesting(db, 85, 86);
      final employeeColumns = await db.rawQuery('PRAGMA table_info(empleados)');
      expect(
        employeeColumns.map((row) => row['name']),
        containsAll(['salary_grade', 'manager_id', 'fecha_nacimiento']),
      );
      final leaveTypeColumns = await db.rawQuery(
        'PRAGMA table_info(hrm_leave_types)',
      );
      expect(
        leaveTypeColumns.map((row) => row['name']),
        contains('exclude_in_reports_if_no_entitlement'),
      );
      final jobTitleColumns = await db.rawQuery(
        'PRAGMA table_info(hrm_job_titles)',
      );
      expect(
        jobTitleColumns.map((row) => row['name']),
        containsAll(['contractual_hours_per_day', 'mrp_workstation_id']),
      );
    },
  );
}
