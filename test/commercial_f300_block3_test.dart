import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/sales/application/create_sale_use_case.dart';

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
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_f300_block3_');
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

  test(
    'F300 separa bases 0/5/19 e IVA generado/descontable por origen',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final products = <int>[];
      for (final rate in [0, 5, 19]) {
        products.add(
          await db.insert('productos', {
            'company_id': companyId,
            'nombre': 'Producto IVA $rate $suffix',
            'unidad_base': 'unidad',
            'stock': 1,
            'costo': 100000,
            'precio': 10000000,
          }),
        );
      }
      final date = DateTime(2026, 8, 9, 12);
      final sale = await CreateSaleUseCase().execute(
        CreateSaleRequest(
          items: [
            SaleItemInput(
              productId: products[0],
              productName: 'Producto IVA 0 $suffix',
              quantity: 1,
              unitPrice: MoneyValue.fromMajorUnits('100000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('1000', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('100000', currency: cop),
              taxRate: 0,
              taxTotal: MoneyValue(minorUnits: 0, currency: cop),
            ),
            SaleItemInput(
              productId: products[1],
              productName: 'Producto IVA 5 $suffix',
              quantity: 1,
              unitPrice: MoneyValue.fromMajorUnits('200000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('1000', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('200000', currency: cop),
              taxRate: 5,
              taxTotal: MoneyValue.fromMajorUnits('10000', currency: cop),
            ),
            SaleItemInput(
              productId: products[2],
              productName: 'Producto IVA 19 $suffix',
              quantity: 1,
              unitPrice: MoneyValue.fromMajorUnits('300000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('1000', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('300000', currency: cop),
              taxRate: 19,
              taxTotal: MoneyValue.fromMajorUnits('57000', currency: cop),
            ),
          ],
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          clientName: 'Cliente F300',
          date: date,
          efectivo: MoneyValue(minorUnits: 0, currency: cop),
          transferencia: MoneyValue(minorUnits: 0, currency: cop),
          credito: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
        ),
      );
      expect(sale.saleId, greaterThan(0));

      final purchaseId = await db.insert('compras', {
        'company_id': companyId,
        'proveedor': 'Proveedor F300',
        'total': 11900000,
        'subtotal': 10000000,
        'impuesto_pct': 19,
        'impuesto_total': 1900000,
        'fecha': date.toIso8601String(),
        'estado': 'pagada',
      });
      await db.insert('compras_detalle', {
        'company_id': companyId,
        'compra_id': purchaseId,
        'producto_id': products[0],
        'producto': 'Insumo F300',
        'cantidad': 1,
        'costo_unitario': 10000000,
        'subtotal': 10000000,
        'impuesto_pct': 19,
        'impuesto_total': 1900000,
      });

      final detail = await helper.obtenerDetalleFormulario300(
        anio: 2026,
        mes: 8,
      );
      expect(detail, hasLength(4));
      final report = await helper.obtenerBorradorFormulario300(
        anio: 2026,
        mes: 8,
      );
      expect(report['base_gravada_0']!.toMajorUnitsString(), '100000.00');
      expect(report['base_gravada_5']!.toMajorUnitsString(), '200000.00');
      expect(report['base_gravada_19']!.toMajorUnitsString(), '300000.00');
      expect(report['iva_generado_0']!.toMajorUnitsString(), '0.00');
      expect(report['iva_generado_5']!.toMajorUnitsString(), '10000.00');
      expect(report['iva_generado_19']!.toMajorUnitsString(), '57000.00');
      expect(report['iva_generado']!.toMajorUnitsString(), '67000.00');
      expect(report['iva_descontable']!.toMajorUnitsString(), '19000.00');
      expect(report['saldo_pagar']!.toMajorUnitsString(), '48000.00');
    },
  );
}
