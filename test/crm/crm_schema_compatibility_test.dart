import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/crm/database/schema_crm.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/sales/application/create_sale_use_case.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late int companyId;
  final cop = Currency(
    code: 'COP',
    name: 'Colombian Peso',
    symbol: r'$',
    decimalPlaces: 2,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_crm_compat_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
    });

    // La prueba ejecuta explícitamente la migración CRM sobre una base
    // existente, antes de verificar los flujos comerciales ya publicados.
    await SchemaCrm.crearTablas(db);
  });

  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dbDir.delete(recursive: true);
  });

  test('la migracion CRM conserva ventas, cartera y sincronizacion', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final clientId = await DatabaseHelper.instance.insertarCliente({
      'nombre': 'Cliente compatibilidad $suffix',
      'documento': 'CRM-$suffix',
      'estado': 'activo',
      'fecha': DateTime.now().toIso8601String(),
    });
    final productId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto compatibilidad $suffix',
      'unidad_base': 'unid.',
      'stock': 3,
      'costo': 100000,
      'precio': 250000,
      'impuesto_pct': 0,
      'codigo_barras': 'CRM-$suffix',
    });

    final sale = await CreateSaleUseCase().execute(
      CreateSaleRequest(
        items: [
          SaleItemInput(
            productId: productId,
            productName: 'Producto compatibilidad $suffix',
            quantity: 1,
            unitPrice: MoneyValue.fromMajorUnits('2500', currency: cop),
            unitCost: MoneyValue.fromMajorUnits('1000', currency: cop),
            subtotal: MoneyValue.fromMajorUnits('2500', currency: cop),
            taxRate: 0,
            taxTotal: MoneyValue(minorUnits: 0, currency: cop),
          ),
        ],
        paymentMethodId: 1,
        paymentMethodName: 'EFECTIVO',
        clientId: clientId,
        clientName: 'Cliente compatibilidad $suffix',
        efectivo: MoneyValue.fromMajorUnits('2500', currency: cop),
        transferencia: MoneyValue(minorUnits: 0, currency: cop),
        credito: MoneyValue(minorUnits: 0, currency: cop),
        retefuente: MoneyValue(minorUnits: 0, currency: cop),
        reteiva: MoneyValue(minorUnits: 0, currency: cop),
        reteica: MoneyValue(minorUnits: 0, currency: cop),
      ),
    );

    final cxcId = await db.insert('cuentas_por_cobrar', {
      'company_id': companyId,
      'cliente_id': clientId,
      'cliente': 'Cliente compatibilidad $suffix',
      'venta_id': sale.saleId,
      'total': 250000,
      'saldo': 250000,
      'estado': 'pendiente',
      'fecha': DateTime.now().toIso8601String(),
      'descripcion': 'Prueba de compatibilidad CRM',
    });

    final clients = await DatabaseHelper.instance.obtenerClientes();
    final receivables = await DatabaseHelper.instance.obtenerCuentasPorCobrar();
    final syncEvents = await db.query(
      'local_changes',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: ['clientes', clientId.toString()],
    );

    expect(clients.any((row) => row['id'] == clientId), isTrue);
    expect(
      receivables.any(
        (row) => row['id'] == cxcId && row['cliente_id'] == clientId,
      ),
      isTrue,
    );
    expect(syncEvents, isNotEmpty);
    expect(sale.saleId, greaterThan(0));
  });
}
