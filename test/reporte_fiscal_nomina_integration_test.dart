import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_currency_resolver.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late final Directory dbDir;
  late final Database db;
  late final int companyId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp(
      'merkaerp_fiscal_payroll_db_',
    );
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    await dbDir.delete(recursive: true);
  });

  test(
    'reporte fiscal usa neto_pagar e intereses de cesantias al 12% anual',
    () async {
      final now = DateTime.now();
      await db.insert('payroll_parameters', {
        'company_id': companyId,
        'year': now.year,
        'smmlv': 142350000,
        'uvt': 5237400,
        'transportation_allowance': 0,
        'created_at': now.toIso8601String(),
      });

      for (final account in const [
        ('510506', 'Sueldos', 'gasto', 'debito'),
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

      final employeeId = await DatabaseHelper.instance.guardarEmpleado(
        nombre: 'Empleado reporte fiscal',
        salarioBase: MoneyValue(
          minorUnits: 100000000,
          currency: await MoneyCurrencyResolver.resolve(
            db,
            companyId: companyId,
          ),
        ),
      );
      final payrollId = await DatabaseHelper.instance.liquidarNomina(
        empleadoId: employeeId,
        anio: now.year,
        mes: now.month,
      );

      final payrollRows = await db.query(
        'nomina_liquidaciones',
        columns: ['neto_pagar', 'cesantias', 'intereses_cesantias'],
        where: 'id = ?',
        whereArgs: [payrollId],
      );
      expect(payrollRows.single['neto_pagar'], 92000000);
      expect(payrollRows.single['cesantias'], 8330000);
      expect(payrollRows.single['intereses_cesantias'], 999600);

      final report = await DatabaseHelper.instance.obtenerReporteFiscal(
        anio: now.year,
        mes: now.month,
      );
      expect(report['nomina']?.minorUnits, 92000000);

      final payrollHistory = await DatabaseHelper.instance.obtenerNomina();
      expect(
        payrollHistory.single['periodo'],
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
      );
      expect(payrollHistory.single['total_devengado'], 100000000);
      expect(payrollHistory.single['total_deducciones'], 8000000);
      expect(payrollHistory.single['neto_pagar'], 92000000);
    },
  );
}
