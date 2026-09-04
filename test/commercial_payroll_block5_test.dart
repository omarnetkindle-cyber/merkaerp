import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_currency_resolver.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/taxes/payroll_withholding.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late DatabaseHelper helper;
  late int companyId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_payroll_block5_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    helper = DatabaseHelper.instance;
    db = await helper.database;
    companyId = await helper.obtenerEmpresaActivaId();
    await db.insert('payroll_parameters', {
      'company_id': companyId,
      'year': 2026,
      'smmlv': 142350000,
      'uvt': 5237400,
      'transportation_allowance': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  Future<int> employee(String name, int salaryMinorUnits) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    return helper.guardarEmpleado(
      nombre: name,
      salarioBase: MoneyValue(minorUnits: salaryMinorUnits, currency: currency),
    );
  }

  Future<Map<String, dynamic>> liquidation(int id) async {
    return (await db.query(
      'nomina_liquidaciones',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    )).single;
  }

  test('novedades variables entran al IBC y excluyen auxilio', () async {
    final id = await employee('Variable block5', 100000000);
    await db.insert('payroll_novelties', {
      'company_id': companyId,
      'empleado_id': id,
      'periodo': '2026-08',
      'tipo_novedad': 'horas_extra',
      'valor': 20000000,
      'fecha': DateTime(2026, 8, 1).toIso8601String(),
    });
    await db.insert('payroll_novelties', {
      'company_id': companyId,
      'empleado_id': id,
      'periodo': '2026-08',
      'tipo_novedad': 'bonificacion_salarial',
      'valor': 30000000,
      'fecha': DateTime(2026, 8, 1).toIso8601String(),
    });

    final payrollId = await helper.liquidarNomina(
      empleadoId: id,
      anio: 2026,
      mes: 8,
    );
    final row = await liquidation(payrollId);

    expect(row['total_devengado'], 150000000);
    expect(row['salud_empleado'], 6000000);
    expect(row['pension_empleado'], 6000000);
    expect(row['salud_empleador'], 12750000);
    expect(row['parafiscal_sena'], 3000000);
    expect(row['parafiscal_icbf'], 4500000);
    expect(row['parafiscal_caja'], 6000000);
  });

  test(
    'health_exonerated elimina salud empleador, SENA e ICBF, no caja',
    () async {
      await db.update(
        'payroll_parameters',
        {'health_exonerated': 1},
        where: 'company_id = ? AND year = ?',
        whereArgs: [companyId, 2026],
      );
      final id = await employee('Exonerado block5', 100000000);
      final payrollId = await helper.liquidarNomina(
        empleadoId: id,
        anio: 2026,
        mes: 8,
      );
      final row = await liquidation(payrollId);

      expect(row['salud_empleador'], 0);
      expect(row['parafiscal_sena'], 0);
      expect(row['parafiscal_icbf'], 0);
      expect(row['parafiscal_caja'], 4000000);
    },
  );

  test(
    'retefuente laboral aplica la tabla progresiva del articulo 383',
    () async {
      await db.update(
        'payroll_parameters',
        {'health_exonerated': 0},
        where: 'company_id = ? AND year = ?',
        whereArgs: [companyId, 2026],
      );
      final id = await employee('Retefuente block5', 2000000000);
      final payrollId = await helper.liquidarNomina(
        empleadoId: id,
        anio: 2026,
        mes: 8,
      );
      final row = await liquidation(payrollId);
      expect(row['retefuente'], 347603200);

      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      final expected = PayrollWithholding.calculate(
        taxableBase: MoneyValue(minorUnits: 1840000000, currency: currency),
        uvt: MoneyValue(minorUnits: 5237400, currency: currency),
        zero: MoneyValue(minorUnits: 0, currency: currency),
      );
      expect(row['retefuente'], expected.minorUnits);
    },
  );

  test(
    'deducciones laborales aplican embargos prestamos y cuota sindical',
    () async {
      await db.update(
        'payroll_parameters',
        {'health_exonerated': 0},
        where: 'company_id = ? AND year = ?',
        whereArgs: [companyId, 2026],
      );
      final id = await employee('Deducciones legales block5', 500000000);
      for (final novelty in [
        ('embargo_alimentos', 100000000),
        ('cuota_sindical', 8000000),
        ('prestamo_empresa', 20000000),
      ]) {
        await db.insert('payroll_novelties', {
          'company_id': companyId,
          'empleado_id': id,
          'periodo': '2026-10',
          'tipo_novedad': novelty.$1,
          'valor': novelty.$2,
          'fecha': DateTime(2026, 10, 1).toIso8601String(),
        });
      }

      final payrollId = await helper.liquidarNomina(
        empleadoId: id,
        anio: 2026,
        mes: 10,
      );
      final row = await liquidation(payrollId);

      expect(row['total_devengado'], 500000000);
      expect(row['salud_empleado'], 20000000);
      expect(row['pension_empleado'], 20000000);
      expect(row['total_deducciones'], 168000000);
      expect(row['neto_pagar'], 332000000);
      final detalle = row['calculo_json'].toString();
      expect(detalle, contains('childSupportGarnishment'));
      expect(detalle, contains('unionFee'));
      expect(detalle, contains('employerLoan'));
    },
  );

  test(
    'prelacion limita embargo ordinario libranza y prestamo si no alcanza',
    () async {
      await db.update(
        'payroll_parameters',
        {'health_exonerated': 0},
        where: 'company_id = ? AND year = ?',
        whereArgs: [companyId, 2026],
      );
      final id = await employee('Prelacion block5', 300000000);
      for (final novelty in [
        ('embargo_judicial', 100000000),
        ('libranza', 150000000),
        ('prestamo_empresa', 100000000),
      ]) {
        await db.insert('payroll_novelties', {
          'company_id': companyId,
          'empleado_id': id,
          'periodo': '2026-11',
          'tipo_novedad': novelty.$1,
          'valor': novelty.$2,
          'fecha': DateTime(2026, 11, 1).toIso8601String(),
        });
      }

      final payrollId = await helper.liquidarNomina(
        empleadoId: id,
        anio: 2026,
        mes: 11,
      );
      final row = await liquidation(payrollId);

      expect(row['total_devengado'], 300000000);
      expect(row['salud_empleado'], 12000000);
      expect(row['pension_empleado'], 12000000);
      expect(row['total_deducciones'], 162000000);
      expect(row['neto_pagar'], 138000000);
      expect(
        row['novedades_hrm'].toString(),
        contains('Deducciones laborales limitadas por topes legales'),
      );
      final detalle = row['calculo_json'].toString();
      expect(detalle, contains('ordinaryGarnishment'));
      expect(detalle, contains('payrollLoan'));
      expect(detalle, contains('employerLoan'));
    },
  );

  test('fallo al registrar asiento revierte caja y liquidacion', () async {
    await helper.cerrarPeriodoContable(anio: 2026, mes: 9);
    final id = await employee('Rollback block5', 100000000);
    final beforeMovements = await db.query(
      'movimientos_caja',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );

    await expectLater(
      helper.liquidarNomina(empleadoId: id, anio: 2026, mes: 9),
      throwsA(isA<Exception>()),
    );

    final afterMovements = await db.query(
      'movimientos_caja',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    final liquidations = await db.query(
      'nomina_liquidaciones',
      where: 'company_id = ? AND empleado_id = ?',
      whereArgs: [companyId, id],
    );
    expect(afterMovements, hasLength(beforeMovements.length));
    expect(liquidations, isEmpty);
  });
}
