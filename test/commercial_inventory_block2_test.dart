import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/inventory/application/inventory_movement_service.dart';
import 'package:merka_erp/inventory/application/inventory_reconciliation_service.dart';
import 'package:merka_erp/inventory/domain/stock_ledger.dart';
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
    dbDir = await Directory.systemTemp.createTemp('merkaerp_inventory_block2_');
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

  test('el dominio de costeo no expone LIFO', () {
    expect(InventoryCostMethod.values, [
      InventoryCostMethod.fifo,
      InventoryCostMethod.average,
    ]);
  });

  test(
    'compra, venta y ajuste dejan productos y Kardex reconciliados',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final productId = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Producto Kardex $suffix',
        'unidad_base': 'unidad',
        'stock': 0,
        'costo': 0,
        'precio': 200000,
      });
      final date = DateTime(2026, 8, 9, 11);
      final purchaseId = await db.insert('compras', {
        'company_id': companyId,
        'proveedor': 'Proveedor Kardex',
        'numero_factura': 'KARDEX-$suffix',
        'subtotal': 300000,
        'total': 300000,
        'fecha': date.toIso8601String(),
        'estado': 'pagada',
      });
      await db.insert('compras_detalle', {
        'company_id': companyId,
        'compra_id': purchaseId,
        'producto_id': productId,
        'producto': 'Producto Kardex $suffix',
        'cantidad': 3,
        'costo_unitario': 100000,
        'subtotal': 300000,
      });
      await db.update(
        'productos',
        {'stock': 3, 'costo': 100000},
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
      );
      await db.transaction((txn) async {
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productId,
          type: 'entrada',
          quantity: 3,
          stockBefore: 0,
          stockAfter: 3,
          costAfterMinor: 100000,
          costTotalMinor: 300000,
          reason: 'COMPRA #$purchaseId',
          date: date.toIso8601String(),
          documentType: 'compra',
          documentId: purchaseId,
        );
      });
      final saleResult = await CreateSaleUseCase().execute(
        CreateSaleRequest(
          items: [
            SaleItemInput(
              productId: productId,
              productName: 'Producto Kardex $suffix',
              quantity: 1,
              unitPrice: MoneyValue.fromMajorUnits('2000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('999', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('2000', currency: cop),
              taxRate: 0,
              taxTotal: MoneyValue(minorUnits: 0, currency: cop),
            ),
          ],
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          clientName: 'Cliente Kardex',
          date: date,
          efectivo: MoneyValue(minorUnits: 0, currency: cop),
          transferencia: MoneyValue(minorUnits: 0, currency: cop),
          credito: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
        ),
      );
      expect(saleResult.costOfSale.toMajorUnitsString(), '1000.00');

      await db.transaction((txn) async {
        final product = (await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
          limit: 1,
        )).single;
        final before = (product['stock'] as num).toDouble();
        final cost = MoneyValue.fromSql(product['costo'], currency: cop);
        await txn.update(
          'productos',
          {'stock': before + 1},
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productId,
          type: 'ajuste_entrada',
          quantity: 1,
          stockBefore: before,
          stockAfter: before + 1,
          costBeforeMinor: cost.toSql(),
          costAfterMinor: cost.toSql(),
          costTotalMinor: cost.toSql(),
          reason: 'AJUSTE KARDEX',
          date: date.toIso8601String(),
          documentType: 'ajuste',
        );
      });

      final product = (await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
      )).single;
      final kardex = await db.query(
        'kardex_inventario',
        where: 'company_id = ? AND producto_id = ?',
        whereArgs: [companyId, productId],
        orderBy: 'id ASC',
      );
      expect(kardex, hasLength(3));
      final signedQuantity = kardex.fold<double>(
        0,
        (sum, row) =>
            sum +
            ((row['tipo'] == 'salida' ? -1 : 1) *
                (row['cantidad'] as num).toDouble()),
      );
      expect(signedQuantity, 3);
      expect((product['stock'] as num).toDouble(), 3);
      expect(kardex.map((row) => row['documento_tipo']), [
        'compra',
        'venta',
        'ajuste',
      ]);
    },
  );

  test(
    'compra, venta, ajuste y traslado reconcilian stock, Kardex y lotes',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final productName = 'Producto Reconciliado $suffix';
      final productId = await db.insert('productos', {
        'company_id': companyId,
        'nombre': productName,
        'unidad_base': 'unidad',
        'stock': 0,
        'costo': 0,
        'precio': 200000,
      });
      final date = DateTime(2026, 8, 13, 9);
      final purchaseId = await db.insert('compras', {
        'company_id': companyId,
        'proveedor': 'Proveedor reconciliacion',
        'numero_factura': 'INV-$suffix',
        'subtotal': 1000000,
        'total': 1000000,
        'fecha': date.toIso8601String(),
        'estado': 'pagada',
      });
      await db.insert('compras_detalle', {
        'company_id': companyId,
        'compra_id': purchaseId,
        'producto_id': productId,
        'producto': productName,
        'cantidad': 10,
        'costo_unitario': 100000,
        'subtotal': 1000000,
      });
      await db.update(
        'productos',
        {'stock': 10, 'costo': 100000},
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
      );
      await db.transaction((txn) async {
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productId,
          type: 'entrada',
          quantity: 10,
          stockBefore: 0,
          stockAfter: 10,
          costAfterMinor: 100000,
          costTotalMinor: 1000000,
          reason: 'COMPRA #$purchaseId',
          date: date.toIso8601String(),
          documentType: 'compra',
          documentId: purchaseId,
        );
      });

      await CreateSaleUseCase().execute(
        CreateSaleRequest(
          items: [
            SaleItemInput(
              productId: productId,
              productName: productName,
              quantity: 3,
              unitPrice: MoneyValue.fromMajorUnits('2000', currency: cop),
              unitCost: MoneyValue.fromMajorUnits('1000', currency: cop),
              subtotal: MoneyValue.fromMajorUnits('6000', currency: cop),
              taxRate: 0,
              taxTotal: MoneyValue(minorUnits: 0, currency: cop),
            ),
          ],
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          clientName: 'Cliente reconciliacion',
          date: date,
          efectivo: MoneyValue(minorUnits: 0, currency: cop),
          transferencia: MoneyValue(minorUnits: 0, currency: cop),
          credito: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
        ),
      );

      await db.transaction((txn) async {
        final product = (await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
          limit: 1,
        )).single;
        final before = (product['stock'] as num).toDouble();
        final cost = MoneyValue.fromSql(product['costo'], currency: cop);
        await txn.update(
          'productos',
          {'stock': before + 2},
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productId,
          type: 'ajuste_entrada',
          quantity: 2,
          stockBefore: before,
          stockAfter: before + 2,
          costBeforeMinor: cost.toSql(),
          costAfterMinor: cost.toSql(),
          costTotalMinor: cost.multiplyDecimal('2').toSql(),
          reason: 'AJUSTE RECONCILIACION',
          date: date.toIso8601String(),
          documentType: 'ajuste',
        );
      });

      await db.insert('bodegas', {
        'id': 1,
        'company_id': companyId,
        'codigo': 'BG-ORIGEN',
        'nombre': 'Bodega origen',
        'updated_at': date.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('bodegas', {
        'id': 2,
        'company_id': companyId,
        'codigo': 'BG-DESTINO',
        'nombre': 'Bodega destino',
        'updated_at': date.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('stock_bodega', {
        'company_id': companyId,
        'producto_id': productId,
        'bodega_id': 1,
        'cantidad': 9,
        'costo': MoneyValue.fromMajorUnits('1000', currency: cop).toSql(),
        'actualizado_en': date.toIso8601String(),
      });
      final transferId = await db.insert('traslados_bodega', {
        'company_id': companyId,
        'producto_id': productId,
        'bodega_origen_id': 1,
        'bodega_destino_id': 2,
        'cantidad': 2,
        'estado': 'registrado',
        'fecha': date.toIso8601String(),
      });
      await helper.procesarTrasladoBodega(
        trasladoId: transferId,
        usuario: 'tester',
      );

      final report = await const InventoryReconciliationService().forProduct(
        db: db,
        companyId: companyId,
        productId: productId,
      );

      expect(report.productStock, 9);
      expect(report.kardexStock, 9);
      expect(report.legacyLotStock, 9);
      expect(report.advancedLotStock, 9);
      expect(report.isReconciled, isTrue);
    },
  );
}
