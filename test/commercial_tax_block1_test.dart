import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/sales/application/create_sale_use_case.dart';
import 'package:merka_erp/taxes/retention_policy.dart';
import 'package:merka_erp/taxes/retention_rule_service.dart';

void main() {
  final cop = Currency(
    code: 'COP',
    name: 'Colombian Peso',
    symbol: r'$',
    decimalPlaces: 2,
  );
  late Directory dbDir;
  late Database db;
  late DatabaseHelper helper;
  late int companyId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_tax_block1_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    helper = DatabaseHelper.instance;
    db = await helper.database;
    companyId = await helper.obtenerEmpresaActivaId();
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('usa UVT 2026 y bases legales por concepto sin pasar por double', () {
    expect(
      RetentionPolicy.currentUvt(currency: cop).toMajorUnitsString(),
      '52374.00',
    );
    expect(
      RetentionPolicy.baseForConcept(
        concept: 'servicios',
        currency: cop,
      ).toMajorUnitsString(),
      '104748.00',
    );
    expect(
      RetentionPolicy.baseForConcept(
        concept: 'otros_ingresos',
        currency: cop,
      ).toMajorUnitsString(),
      '523740.00',
    );
    expect(
      RetentionPolicy.baseForConcept(
        concept: 'honorarios',
        currency: cop,
      ).toMajorUnitsString(),
      '0.00',
    );
    expect(
      RetentionPolicy.baseForConcept(
        concept: 'arrendamientos',
        currency: cop,
      ).toMajorUnitsString(),
      '523740.00',
    );
    expect(
      RetentionPolicy.baseForConcept(
        concept: 'rendimientos_financieros',
        currency: cop,
      ).toMajorUnitsString(),
      '0.00',
    );
  });

  test(
    'la semilla de compras usa 10 UVT sin pisar una base configurada',
    () async {
      final rows = await db.query(
        'reglas_retenciones_empresa',
        columns: ['base_minima'],
        where: 'company_id = ? AND codigo = ?',
        whereArgs: [companyId, 'RTFTE_COMPRAS_25'],
        limit: 1,
      );
      expect(rows.single['base_minima'], 52374000);
    },
  );

  test('F350 conserva concepto, base y tarifa de cada transacción', () async {
    final date = DateTime(2026, 8, 9, 10).toIso8601String();
    final saleId = await db.insert('ventas', {
      'company_id': companyId,
      'producto': 'Venta otros ingresos',
      'cantidad': 1,
      'subtotal': 50000000,
      'total': 50000000,
      'fecha': date,
      'estado': 'emitida',
      'retefuente': 1250000,
      'retefuente_concepto': 'otros_ingresos',
      'retefuente_base': 50000000,
      'retefuente_tasa': 2.5,
    });
    final servicePurchaseId = await db.insert('compras', {
      'company_id': companyId,
      'proveedor': 'Proveedor servicios',
      'total': 10000000,
      'subtotal': 10000000,
      'fecha': date,
      'estado': 'pagada',
      'retefuente': 400000,
      'retefuente_concepto': 'servicios',
      'retefuente_base': 10000000,
      'retefuente_tasa': 4.0,
    });
    final honorariesPurchaseId = await db.insert('compras', {
      'company_id': companyId,
      'proveedor': 'Profesional independiente',
      'total': 20000000,
      'subtotal': 20000000,
      'fecha': date,
      'estado': 'pagada',
      'retefuente': 2000000,
      'retefuente_concepto': 'honorarios',
      'retefuente_base': 20000000,
      'retefuente_tasa': 10.0,
    });

    final details = await helper.obtenerDetalleFormulario350(
      anio: 2026,
      mes: 8,
    );
    expect(details, hasLength(3));
    Map<String, dynamic> rowFor(String origin, int id) => details.singleWhere(
      (row) => row['origen'] == origin && row['documento_id'] == id,
    );
    final sale = rowFor('venta', saleId);
    final servicePurchase = rowFor('compra', servicePurchaseId);
    final honorariesPurchase = rowFor('compra', honorariesPurchaseId);
    expect(sale['concepto'], 'otros_ingresos');
    expect(sale['base'], 50000000);
    expect(sale['tasa'], 2.5);
    expect(servicePurchase['concepto'], 'servicios');
    expect(servicePurchase['base'], 10000000);
    expect(servicePurchase['tasa'], 4.0);
    expect(honorariesPurchase['concepto'], 'honorarios');
    expect(honorariesPurchase['base'], 20000000);
    expect(honorariesPurchase['tasa'], 10.0);

    final draft = await helper.obtenerBorradorFormulario350(anio: 2026, mes: 8);
    expect(draft['retefuente_servicios']!.toMajorUnitsString(), '4000.00');
    expect(draft['retefuente_honorarios']!.toMajorUnitsString(), '20000.00');
    expect(
      draft['retefuente_otros_ingresos']!.toMajorUnitsString(),
      '12500.00',
    );
    expect(draft['total_retenciones']!.toMajorUnitsString(), '36500.00');
  });

  test('POS aplica base de servicios de 2 UVT y tarifa configurable', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final productName = 'Servicio UVT $suffix';
    final productId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': productName,
      'unidad_base': 'servicio',
      'stock': 1,
      'costo': 1000000,
      'precio': 20000000,
    });
    final result = await CreateSaleUseCase().execute(
      CreateSaleRequest(
        items: [
          SaleItemInput(
            productId: productId,
            productName: productName,
            quantity: 1,
            unitPrice: MoneyValue.fromMajorUnits('200000', currency: cop),
            unitCost: MoneyValue.fromMajorUnits('10000', currency: cop),
            subtotal: MoneyValue.fromMajorUnits('200000', currency: cop),
            taxRate: 0,
            taxTotal: MoneyValue(minorUnits: 0, currency: cop),
          ),
        ],
        paymentMethodId: 1,
        paymentMethodName: 'EFECTIVO',
        clientName: 'Cliente servicios',
        efectivo: MoneyValue(minorUnits: 0, currency: cop),
        transferencia: MoneyValue(minorUnits: 0, currency: cop),
        credito: MoneyValue(minorUnits: 0, currency: cop),
        retefuente: MoneyValue(minorUnits: 0, currency: cop),
        reteiva: MoneyValue(minorUnits: 0, currency: cop),
        reteica: MoneyValue(minorUnits: 0, currency: cop),
        retefuenteConcepto: 'servicios',
      ),
    );
    final sale = (await db.query(
      'ventas',
      columns: ['retefuente', 'retefuente_base', 'retefuente_tasa'],
      where: 'id = ?',
      whereArgs: [result.saleId],
    )).single;
    expect(sale['retefuente'], 800000);
    expect(sale['retefuente_base'], 20000000);
    expect(sale['retefuente_tasa'], 4.0);
  });

  test(
    'usuario puede ajustar tarifa/base de ReteFuente por concepto',
    () async {
      const service = RetentionRuleService();
      final rules = await service.listRules(
        db: db,
        companyId: companyId,
        currency: cop,
      );
      final servicesRule = rules.singleWhere(
        (rule) => rule.code == 'RTFTE_SERVICIOS_DECLARANTE',
      );
      await service.updateRule(
        db: db,
        rule: RetentionRule(
          id: servicesRule.id,
          companyId: companyId,
          code: servicesRule.code,
          name: servicesRule.name,
          ratePercent: 5,
          minimumBase: RetentionPolicy.currentUvt(currency: cop) * 2,
          appliesSales: true,
          appliesPurchases: true,
          active: true,
        ),
      );

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final productId = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Servicio editable $suffix',
        'unidad_base': 'servicio',
        'stock': 1,
        'costo': 1000000,
        'precio': 20000000,
      });
      final result = await CreateSaleUseCase().execute(
        CreateSaleRequest(
          items: [
            SaleItemInput(
              productId: productId,
              productName: 'Servicio editable $suffix',
              quantity: 1,
              unitPrice: MoneyValue.fromMajorUnits('200000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('10000', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('200000', currency: cop),
              taxRate: 0,
              taxTotal: MoneyValue(minorUnits: 0, currency: cop),
            ),
          ],
          paymentMethodId: 1,
          paymentMethodName: 'EFECTIVO',
          clientName: 'Cliente servicios editable',
          efectivo: MoneyValue(minorUnits: 0, currency: cop),
          transferencia: MoneyValue(minorUnits: 0, currency: cop),
          credito: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          retefuenteConcepto: 'servicios',
        ),
      );
      final sale = (await db.query(
        'ventas',
        columns: ['retefuente', 'retefuente_tasa'],
        where: 'id = ?',
        whereArgs: [result.saleId],
      )).single;

      expect(sale['retefuente'], 1000000);
      expect(sale['retefuente_tasa'], 5.0);
    },
  );
}
