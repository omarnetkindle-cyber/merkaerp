import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/hrm/database/schema_hrm.dart';
import 'package:merka_erp/sector_publico/nomina/database/schema_nomina.dart';
import 'package:merka_erp/sector_publico/nomina/services/nomina_service.dart';
import 'package:merka_erp/sector_publico/nomina/models/liquidacion_nomina.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/core/currency/money_currency_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('nomina publica usa ausencias HRM', () {
    late Database db;
    late NominaService service;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE entidades_territoriales (id TEXT PRIMARY KEY)',
      );
      await db.execute('''
        CREATE TABLE configuracion_entidad (
          entidad_id TEXT NOT NULL,
          parametro TEXT NOT NULL,
          valor TEXT NOT NULL,
          vigente INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE auditoria_registros (
          id TEXT PRIMARY KEY, entidad_id TEXT NOT NULL, usuario_id TEXT NOT NULL,
          usuario_nombre TEXT, ip_direccion TEXT, fecha_hora TEXT NOT NULL,
          tipo_evento TEXT NOT NULL, modulo TEXT NOT NULL, accion TEXT NOT NULL,
          valor_anterior TEXT NOT NULL, valor_nuevo TEXT NOT NULL,
          hash_anterior TEXT, hash_actual TEXT NOT NULL, referencia_id TEXT,
          observaciones TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE empleados (
          id INTEGER PRIMARY KEY, company_id INTEGER NOT NULL,
          nombre TEXT NOT NULL, documento TEXT NOT NULL
        )
      ''');
      await db.insert('entidades_territoriales', {'id': 'ENT-001'});
      await db.insert('configuracion_entidad', {
        'entidad_id': 'ENT-001',
        'parametro': 'configuracion_legal',
        'valor': '{"smmlv":1750905,"auxilio_transporte":249095}',
      });
      await SchemaHrm.crearTablas(db);
      await SchemaNomina.crearTablas(db);
      service = NominaService(db: db, auditoriaService: AuditoriaService(db));
    });

    tearDown(() => db.close());

    test('vacaciones y permisos aplican el mapeo aprobado', () async {
      await _insertPublicEmployee(db, hrmEmployeeId: 1);
      await db.insert('empleados', {
        'id': 1,
        'company_id': 1,
        'nombre': 'Funcionario vinculado',
        'documento': 'HRM-1',
      });
      final types = await db.query('hrm_leave_types');
      final vacation = _typeId(types, 'vacaciones');
      final paid = _typeId(types, 'permiso_remunerado');
      final unpaid = _typeId(types, 'permiso_no_remunerado');
      await _approvedLeave(
        db,
        employeeId: 1,
        typeId: vacation,
        day: 2,
        days: 2,
      );
      await _approvedLeave(db, employeeId: 1, typeId: paid, day: 5, days: 1);
      await _approvedLeave(db, employeeId: 1, typeId: unpaid, day: 8, days: 3);

      final rows = await db.query('hrm_leaves');
      expect(rows, hasLength(3));
      final liquidacion = await _liquidarPublica(service, 'PUB-1');

      expect(liquidacion.diasTrabajados, 27);
      expect(liquidacion.salarioDevengado, publicMoneyFromMajor('2700000'));
      expect(liquidacion.observaciones, isNot(contains('sin procesar')));
    });

    test('incapacidad EPS liquida pagador desde el dia 3', () async {
      await _insertPublicEmployee(db, hrmEmployeeId: 1);
      await db.insert('empleados', {
        'id': 1,
        'company_id': 1,
        'nombre': 'Funcionario vinculado',
        'documento': 'HRM-1',
      });
      final types = await db.query('hrm_leave_types');
      await _approvedLeave(
        db,
        employeeId: 1,
        typeId: _typeId(types, 'incapacidad_eps'),
        day: 2,
        days: 5,
      );

      final liquidacion = await _liquidarPublica(service, 'PUB-1');

      expect(liquidacion.diasTrabajados, 27);
      expect(liquidacion.salarioDevengado, publicMoneyFromMajor('2900000'));
      expect(liquidacion.observaciones, contains('pagador EPS/ARL'));
      expect(liquidacion.observaciones, isNot(contains('requiere')));
    });

    test('sin ausencias conserva el calculo anterior', () async {
      await _insertPublicEmployee(db, hrmEmployeeId: null);
      final liquidacion = await _liquidarPublica(service, 'PUB-1');

      expect(liquidacion.diasTrabajados, 30);
      expect(liquidacion.salarioDevengado, publicMoneyFromMajor('3000000'));
      expect(liquidacion.observaciones, isNot(contains('sin procesar')));
    });

    test('hrm_employee_id nulo liquida con cero ausencias', () async {
      await _insertPublicEmployee(db, hrmEmployeeId: null);

      final liquidacion = await _liquidarPublica(service, 'PUB-1');

      expect(liquidacion.diasTrabajados, 30);
      expect(liquidacion.salarioDevengado, publicMoneyFromMajor('3000000'));
    });
  });

  group('nomina comercial usa ausencias HRM', () {
    late Directory dbDir;
    late Database db;
    late int companyId;

    setUpAll(() async {
      await DatabaseHelper.resetForTests();
      CompanyConfigurationService.instance.resetForTests();
      dbDir = await Directory.systemTemp.createTemp('merkaerp_hrm_payroll_');
      await databaseFactory.setDatabasesPath(dbDir.path);
      db = await DatabaseHelper.instance.database;
      companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      await db.insert('payroll_parameters', {
        'company_id': companyId,
        'year': 2026,
        'smmlv': 142350000,
        'uvt': 5237400,
        'transportation_allowance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final leaveType = await db.query(
        'hrm_leave_types',
        where: 'company_id = ? AND code = ?',
        whereArgs: [companyId, 'permiso_no_remunerado'],
      );
      if (leaveType.isEmpty) {
        await db.insert('hrm_leave_types', {
          'company_id': companyId,
          'code': 'permiso_no_remunerado',
          'name': 'Permiso no remunerado',
          'requires_entitlement': 0,
          'active': 1,
        });
      }
      await _ensureLeaveType(db, companyId, 'licencia_maternidad');
      for (final account in const [
        ('510506', 'Sueldos', 'gasto', 'debito'),
        ('510527', 'Auxilio transporte', 'gasto', 'debito'),
        ('237005', 'Aportes salud', 'pasivo', 'credito'),
        ('238030', 'Aportes pension', 'pasivo', 'credito'),
        ('110505', 'Caja general', 'activo', 'debito'),
      ]) {
        await db.insert('cuentas_contables', {
          'company_id': companyId,
          'codigo': account.$1,
          'nombre': account.$2,
          'tipo': account.$3,
          'naturaleza': account.$4,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });

    tearDownAll(() async {
      await DatabaseHelper.resetForTests();
      CompanyConfigurationService.instance.resetForTests();
      await dbDir.delete(recursive: true);
    });

    test('permiso no remunerado reduce solo el periodo vinculado', () async {
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      final absentEmployee = await DatabaseHelper.instance.guardarEmpleado(
        nombre: 'Con permiso no remunerado',
        salarioBase: MoneyValue(minorUnits: 300000000, currency: currency),
      );
      await _linkEmployeeToCompany(db, absentEmployee, companyId);
      final type = (await db.query(
        'hrm_leave_types',
        where: 'company_id = ? AND code = ?',
        whereArgs: [companyId, 'permiso_no_remunerado'],
      )).single;
      final year = 2026;
      final month = 8;
      await _approvedLeave(
        db,
        employeeId: absentEmployee,
        typeId: type['id'] as int,
        day: 2,
        days: 2,
        companyId: companyId,
        date: DateTime(year, month, 2),
      );

      final absentId = await DatabaseHelper.instance.liquidarNomina(
        empleadoId: absentEmployee,
        anio: year,
        mes: month,
      );
      final rows = await db.query(
        'nomina_liquidaciones',
        columns: ['id', 'total_devengado', 'calculo_json'],
        where: 'id = ?',
        whereArgs: [absentId],
      );
      expect(rows.single['total_devengado'] as num, greaterThan(0));
      expect(rows.single['calculo_json'], contains('dias_no_remunerados'));
    });

    test('licencia de maternidad queda registrada como pagador EPS', () async {
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      final employeeId = await DatabaseHelper.instance.guardarEmpleado(
        nombre: 'Con licencia maternidad',
        salarioBase: MoneyValue(minorUnits: 300000000, currency: currency),
      );
      await _linkEmployeeToCompany(db, employeeId, companyId);
      final type = (await db.query(
        'hrm_leave_types',
        where: 'company_id = ? AND code = ?',
        whereArgs: [companyId, 'licencia_maternidad'],
      )).single;
      await _approvedLeave(
        db,
        employeeId: employeeId,
        typeId: type['id'] as int,
        day: 1,
        days: 30,
        companyId: companyId,
        date: DateTime(2026, 8),
      );

      final liquidationId = await DatabaseHelper.instance.liquidarNomina(
        empleadoId: employeeId,
        anio: 2026,
        mes: 8,
      );
      final rows = await db.query(
        'nomina_liquidaciones',
        columns: ['calculo_json', 'novedades_hrm'],
        where: 'id = ?',
        whereArgs: [liquidationId],
      );

      expect(rows.single['calculo_json'], contains('maternidad_dias: 30.0'));
      expect(rows.single['calculo_json'], contains('valor_eps'));
      expect(rows.single['novedades_hrm'], isNull);
    });
  });
}

Future<void> _linkEmployeeToCompany(
  Database db,
  int employeeId,
  int companyId,
) async {
  await db.update(
    'empleados',
    {'company_id': companyId, 'documento': 'HRM-$employeeId'},
    where: 'id = ?',
    whereArgs: [employeeId],
  );
}

Future<void> _ensureLeaveType(Database db, int companyId, String code) async {
  final existing = await db.query(
    'hrm_leave_types',
    where: 'company_id = ? AND code = ?',
    whereArgs: [companyId, code],
    limit: 1,
  );
  if (existing.isNotEmpty) return;
  await db.insert('hrm_leave_types', {
    'company_id': companyId,
    'code': code,
    'name': code,
    'requires_entitlement': 0,
    'active': 1,
  });
}

int _typeId(List<Map<String, dynamic>> types, String code) {
  return types.singleWhere((row) => row['code'] == code)['id'] as int;
}

Future<void> _insertPublicEmployee(Database db, {required int? hrmEmployeeId}) {
  return db.insert('empleados_sp', {
    'id': 'PUB-1',
    'entidad_id': 'ENT-001',
    'numero_identificacion': 'PUB-1',
    'nombre_completo': 'Funcionario publico',
    'cargo': 'Profesional',
    'dependencia': 'Administrativa',
    'tipo_contrato': 'indefinido',
    'tipo_vinculacion': 'carrera',
    'regimen_nomina': 'carreraAdministrativa',
    'clase_riesgo_arl': 1,
    'salario_basico': publicMoneyFromMajor('3000000').toSql(),
    'fecha_ingreso': '2026-01-01',
    'activo': 1,
    'hrm_employee_id': hrmEmployeeId,
  });
}

Future<LiquidacionNomina> _liquidarPublica(
  NominaService service,
  String employeeId,
) {
  return service.liquidarNomina(
    entidadId: 'ENT-001',
    usuarioId: 'USR-001',
    empleadoId: employeeId,
    periodo: '2026-08',
    diasTrabajados: 30,
  );
}

Future<void> _approvedLeave(
  Database db, {
  required int employeeId,
  required int typeId,
  required int day,
  required int days,
  int companyId = 1,
  DateTime? date,
}) async {
  final leaveDate = date ?? DateTime(2026, 8, day);
  final requestId = await db.insert('hrm_leave_requests', {
    'company_id': companyId,
    'employee_id': employeeId,
    'leave_type_id': typeId,
    'date_applied': leaveDate.toIso8601String(),
    'status': 'aprobado',
  });
  await db.insert('hrm_leaves', {
    'company_id': companyId,
    'leave_request_id': requestId,
    'employee_id': employeeId,
    'leave_type_id': typeId,
    'date': leaveDate.toIso8601String(),
    'length_days': days,
    'status': 'aprobado',
    'approved_by': 99,
  });
}
