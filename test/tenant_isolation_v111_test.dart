import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_currency_resolver.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/services/api_auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late DatabaseHelper helper;
  late int companyA;
  late int companyB;

  Future<void> activate(int id) async {
    await db.insert('app_config', {
      'clave': 'company_active_id',
      'valor': id.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    CompanyConfigurationService.instance.resetForTests();
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_tenant_v111_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    helper = DatabaseHelper.instance;
    db = await helper.database;
    companyA = await helper.obtenerEmpresaActivaId();
    companyB = await db.insert('companies', {
      'name': 'Tenant B',
      'tax_id': 'B-1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test(
    'usuarios y empleados quedan aislados y admiten nombres repetidos',
    () async {
      await activate(companyA);
      await helper.guardarUsuario(
        nombre: 'Admin A',
        usuario: 'admin.tenant',
        rol: 'administrador',
        pin: '123456',
      );
      final currencyA = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyA,
      );
      await helper.guardarEmpleado(
        nombre: 'Empleado compartido',
        salarioBase: MoneyValue(minorUnits: 100000000, currency: currencyA),
      );

      await activate(companyB);
      await helper.guardarUsuario(
        nombre: 'Admin B',
        usuario: 'admin.tenant',
        rol: 'administrador',
        pin: '654321',
      );
      final currencyB = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyB,
      );
      await helper.guardarEmpleado(
        nombre: 'Empleado compartido',
        salarioBase: MoneyValue(minorUnits: 200000000, currency: currencyB),
      );

      expect(await helper.obtenerUsuarios(), hasLength(1));
      expect((await helper.obtenerUsuarios()).single['nombre'], 'Admin B');
      expect(await helper.obtenerEmpleados(), hasLength(1));
      expect(
        (await helper.obtenerEmpleados()).single['salario_base'],
        200000000,
      );

      await activate(companyA);
      expect((await helper.obtenerUsuarios()).single['nombre'], 'Admin A');
      expect(
        (await helper.obtenerEmpleados()).single['salario_base'],
        100000000,
      );
    },
  );

  test('API key conserva su tenant aunque cambie la empresa activa', () async {
    await activate(companyA);
    final created = await ApiAuthService.instance.crearApiKey(
      nombre: 'Integración A',
      permisos: const ['products:read'],
    );
    final stored =
        (await db.query(
              'api_keys',
              where: 'id = ?',
              whereArgs: [created.id],
            )).single['key']
            as String;
    expect(stored, isNot(created.key));
    expect(stored, hasLength(64));

    await activate(companyB);
    final validated = await ApiAuthService.instance.validarApiKey(created.key);
    expect(validated, isNotNull);
    expect(validated!.companyId, companyA);
  });

  test(
    'consecutivos electrónicos pueden repetirse sin cruzar empresas',
    () async {
      Future<int> sale(int companyId, String product) => db.insert('ventas', {
        'company_id': companyId,
        'producto': product,
        'cantidad': 1,
        'total': 100000,
        'fecha': DateTime.now().toIso8601String(),
      });

      await activate(companyA);
      final invoiceA = await helper.crearFacturaElectronicaBorrador(
        ventaId: await sale(companyA, 'A'),
      );
      await activate(companyB);
      final invoiceB = await helper.crearFacturaElectronicaBorrador(
        ventaId: await sale(companyB, 'B'),
      );
      final rows = await db.query(
        'facturas_electronicas',
        where: 'id IN (?, ?)',
        whereArgs: [invoiceA, invoiceB],
        orderBy: 'company_id',
      );
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['company_id']).toSet(), {
        companyA,
        companyB,
      });
      expect(rows.map((row) => row['numero']).toList(), everyElement(1));
    },
  );
}
