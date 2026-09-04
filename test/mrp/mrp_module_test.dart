import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/mrp/application/mrp_services.dart';
import 'package:merka_erp/mrp/database/schema_mrp.dart';
import 'package:merka_erp/mrp/domain/mrp_bom.dart';
import 'package:merka_erp/mrp/domain/mrp_bom_item.dart';
import 'package:merka_erp/mrp/domain/mrp_operation.dart';
import 'package:merka_erp/mrp/domain/mrp_routing.dart';
import 'package:merka_erp/mrp/domain/mrp_work_order.dart';
import 'package:merka_erp/mrp/domain/mrp_workstation.dart';

void main() {
  late Directory dir;
  late Database db;
  late int companyId;
  late Currency cop;
  late int rawProductId;
  late int finishedProductId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    dir = await Directory.systemTemp.createTemp('merkaerp_mrp_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    cop = Currency(
      code: 'COP',
      name: 'Peso colombiano',
      symbol: r'$',
      decimalPlaces: 2,
    );
    await SchemaMrp.crearTablas(db);
    rawProductId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Acero MRP',
      'unidad_base': 'KG',
      'stock': 10,
      'costo': 1000,
      'precio': 1000,
      'impuesto_pct': 0,
    });
    finishedProductId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto terminado MRP',
      'unidad_base': 'UND',
      'stock': 0,
      'costo': 0,
      'precio': 5000,
      'impuesto_pct': 0,
    });
    for (final warehouseId in [1, 2, 3]) {
      await db.insert('stock_bodega', {
        'company_id': companyId,
        'producto_id': rawProductId,
        'bodega_id': warehouseId,
        'cantidad': warehouseId == 1 ? 10 : 0,
        'costo': 1000,
        'actualizado_en': DateTime.now().toIso8601String(),
      });
      await db.insert('stock_bodega', {
        'company_id': companyId,
        'producto_id': finishedProductId,
        'bodega_id': warehouseId,
        'cantidad': 0,
        'costo': 0,
        'actualizado_en': DateTime.now().toIso8601String(),
      });
    }
  });

  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dir.delete(recursive: true);
  });

  test('MRP crea entidades, calcula costos, explota BOM y mueve stock', () async {
    final workstationId = await MrpWorkstationService().create(
      MrpWorkstation(
        companyId: companyId,
        name: 'Corte',
        hourRate: MoneyValue.fromMajorUnits('10', currency: cop),
        availableHoursPerDay: 8,
        warehouseId: 2,
      ),
    );
    final routingId = await MrpRoutingService().create(
      MrpRouting(companyId: companyId, name: 'Ruta corte'),
    );
    await MrpOperationService().create(
      MrpOperation(
        companyId: companyId,
        routingId: routingId,
        workstationId: workstationId,
        operationName: 'Corte',
        timeMinutes: 60,
      ),
    );
    final bomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: finishedProductId,
        rawMaterialCost: MoneyValue(minorUnits: 0, currency: cop),
        operatingCost: MoneyValue(minorUnits: 0, currency: cop),
        totalCost: MoneyValue(minorUnits: 0, currency: cop),
        routingId: routingId,
      ),
    );
    await MrpBomService().addItem(
      MrpBomItem(
        companyId: companyId,
        bomId: bomId,
        itemId: rawProductId,
        qty: 2,
        rate: MoneyValue.fromMajorUnits('10', currency: cop),
        amount: MoneyValue.fromMajorUnits('20', currency: cop),
        sourceWarehouseId: 1,
      ),
    );
    final bom = await MrpBomService().recalculate(bomId);
    final workstation = (await MrpWorkstationService().list()).single;
    expect(workstation.availableHoursPerDay, 8);
    expect(bom.rawMaterialCost.minorUnits, 2000);
    expect(bom.operatingCost.minorUnits, 1000);
    expect(bom.totalCost.minorUnits, 3000);

    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: finishedProductId,
        bomId: bomId,
        qtyPlanned: 1,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: bom.operatingCost,
        actualOperatingCost: MoneyValue(minorUnits: 0, currency: cop),
        rawMaterialCost: bom.rawMaterialCost,
        totalCost: bom.totalCost,
      ),
    );
    final orderItems = await MrpWorkOrderService().items(orderId);
    expect(orderItems.single.requiredQty, 2);
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.noIniciada,
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.enProceso,
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.completada,
    );

    final rawAtSource = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [rawProductId, 1],
    );
    final finishedAtFg = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [finishedProductId, 3],
    );
    final movementCount = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM movimientos_inventario WHERE motivo LIKE 'MRP WO#%' OR motivo LIKE 'TRASLADO #%'",
    );
    final transferCount = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM traslados_bodega WHERE observacion LIKE 'MRP WO#%'",
    );
    final order = (await MrpWorkOrderService().list()).single;
    expect(rawAtSource.single['cantidad'], 8);
    expect(finishedAtFg.single['cantidad'], 1);
    expect(movementCount.single['total'], 6);
    expect(transferCount.single['total'], 2);
    expect(order.status, MrpWorkOrderStatus.completada);
    expect(order.qtyProduced, 1);
    expect(
      (await MrpWorkOrderService().items(order.id!)).single.consumedQty,
      2,
    );
  });

  test('MRP rechaza transiciones de orden no permitidas', () async {
    final boms = await MrpBomService().list();
    final bom = boms.single;
    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: finishedProductId,
        bomId: bom.id!,
        qtyPlanned: 1,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: bom.operatingCost,
        actualOperatingCost: MoneyValue(minorUnits: 0, currency: cop),
        rawMaterialCost: bom.rawMaterialCost,
        totalCost: bom.totalCost,
      ),
    );
    await expectLater(
      () => MrpWorkOrderService().transition(
        orderId,
        MrpWorkOrderStatus.completada,
      ),
      throwsStateError,
    );
  });

  test(
    'MRP bloquea BOM circular directa e indirecta sin guardar la orden',
    () async {
      final productA = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Subensamble A',
        'unidad_base': 'UND',
        'stock': 0,
        'costo': 0,
        'precio': 0,
        'impuesto_pct': 0,
      });
      final productB = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Subensamble B',
        'unidad_base': 'UND',
        'stock': 0,
        'costo': 0,
        'precio': 0,
        'impuesto_pct': 0,
      });
      final zero = MoneyValue(minorUnits: 0, currency: cop);
      final bomA = await MrpBomService().create(
        MrpBom(
          companyId: companyId,
          itemId: productA,
          rawMaterialCost: zero,
          operatingCost: zero,
          totalCost: zero,
        ),
      );
      final bomB = await MrpBomService().create(
        MrpBom(
          companyId: companyId,
          itemId: productB,
          rawMaterialCost: zero,
          operatingCost: zero,
          totalCost: zero,
        ),
      );
      await MrpBomService().addItem(
        MrpBomItem(
          companyId: companyId,
          bomId: bomA,
          itemId: productB,
          qty: 1,
          rate: zero,
          amount: zero,
          isSubAssemblyItem: true,
        ),
      );
      await MrpBomService().addItem(
        MrpBomItem(
          companyId: companyId,
          bomId: bomB,
          itemId: productA,
          qty: 1,
          rate: zero,
          amount: zero,
          isSubAssemblyItem: true,
        ),
      );
      final before = (await db.query('mrp_work_orders')).length;
      await expectLater(
        () => MrpWorkOrderService().create(
          draft: MrpWorkOrder(
            companyId: companyId,
            productionItemId: productA,
            bomId: bomA,
            qtyPlanned: 1,
            wipWarehouseId: 2,
            fgWarehouseId: 3,
            plannedOperatingCost: zero,
            actualOperatingCost: zero,
            rawMaterialCost: zero,
            totalCost: zero,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect((await db.query('mrp_work_orders')).length, before);
    },
  );

  test('MRP calcula y explota BOM multinivel en todos sus niveles', () async {
    final subAssembly = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Subensamble costeado',
      'unidad_base': 'UND',
      'stock': 0,
      'costo': 0,
      'precio': 0,
      'impuesto_pct': 0,
    });
    final zero = MoneyValue(minorUnits: 0, currency: cop);
    final childCost = MoneyValue.fromMajorUnits('10', currency: cop);
    final childBomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: subAssembly,
        rawMaterialCost: zero,
        operatingCost: zero,
        totalCost: zero,
      ),
    );
    await MrpBomService().addItem(
      MrpBomItem(
        companyId: companyId,
        bomId: childBomId,
        itemId: rawProductId,
        qty: 2,
        rate: childCost,
        amount: childCost.multiplyDecimal('2'),
        sourceWarehouseId: 1,
      ),
    );
    final parentBomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: finishedProductId,
        rawMaterialCost: zero,
        operatingCost: zero,
        totalCost: zero,
      ),
    );
    await MrpBomService().addItem(
      MrpBomItem(
        companyId: companyId,
        bomId: parentBomId,
        itemId: subAssembly,
        qty: 2,
        rate: zero,
        amount: zero,
        isSubAssemblyItem: true,
      ),
    );
    final parent = await MrpBomService().recalculate(parentBomId);
    expect(parent.rawMaterialCost.minorUnits, 4000);
    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: finishedProductId,
        bomId: parentBomId,
        qtyPlanned: 1,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: zero,
        actualOperatingCost: zero,
        rawMaterialCost: parent.rawMaterialCost,
        totalCost: parent.totalCost,
      ),
    );
    expect((await MrpWorkOrderService().items(orderId)).single.requiredQty, 4);
  });

  test(
    'MRP bloquea iniciar una orden si falta stock sin transferencias parciales',
    () async {
      final scarceProduct = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Material escaso',
        'unidad_base': 'UND',
        'stock': 0,
        'costo': 1000,
        'precio': 1000,
        'impuesto_pct': 0,
      });
      final zero = MoneyValue(minorUnits: 0, currency: cop);
      final bomId = await MrpBomService().create(
        MrpBom(
          companyId: companyId,
          itemId: finishedProductId,
          rawMaterialCost: zero,
          operatingCost: zero,
          totalCost: zero,
        ),
      );
      await MrpBomService().addItem(
        MrpBomItem(
          companyId: companyId,
          bomId: bomId,
          itemId: scarceProduct,
          qty: 1,
          rate: MoneyValue.fromMajorUnits('10', currency: cop),
          amount: MoneyValue.fromMajorUnits('10', currency: cop),
          sourceWarehouseId: 1,
        ),
      );
      final orderId = await MrpWorkOrderService().create(
        draft: MrpWorkOrder(
          companyId: companyId,
          productionItemId: finishedProductId,
          bomId: bomId,
          qtyPlanned: 1,
          wipWarehouseId: 2,
          fgWarehouseId: 3,
          plannedOperatingCost: zero,
          actualOperatingCost: zero,
          rawMaterialCost: zero,
          totalCost: zero,
        ),
      );
      await MrpWorkOrderService().transition(
        orderId,
        MrpWorkOrderStatus.noIniciada,
      );
      await expectLater(
        () => MrpWorkOrderService().transition(
          orderId,
          MrpWorkOrderStatus.enProceso,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await MrpWorkOrderService().list())
            .singleWhere((o) => o.id == orderId)
            .status,
        MrpWorkOrderStatus.noIniciada,
      );
      expect(
        (await db.query(
          'traslados_bodega',
          where: 'observacion LIKE ?',
          whereArgs: ['MRP WO#$orderId%'],
        )),
        isEmpty,
      );
    },
  );

  test('MRP revierte material WIP al cancelar una orden en proceso', () async {
    final zero = MoneyValue(minorUnits: 0, currency: cop);
    final bomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: finishedProductId,
        rawMaterialCost: zero,
        operatingCost: zero,
        totalCost: zero,
      ),
    );
    await MrpBomService().addItem(
      MrpBomItem(
        companyId: companyId,
        bomId: bomId,
        itemId: rawProductId,
        qty: 1,
        rate: zero,
        amount: zero,
        sourceWarehouseId: 1,
      ),
    );
    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: finishedProductId,
        bomId: bomId,
        qtyPlanned: 1,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: zero,
        actualOperatingCost: zero,
        rawMaterialCost: zero,
        totalCost: zero,
      ),
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.noIniciada,
    );
    final wipBeforeCancel = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [rawProductId, 2],
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.enProceso,
    );
    final beforeCancel = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [rawProductId, 1],
    );
    expect(beforeCancel.single['cantidad'], 7);
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.cancelada,
    );
    final source = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [rawProductId, 1],
    );
    final wip = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [rawProductId, 2],
    );
    expect(source.single['cantidad'], 8);
    expect(wip.single['cantidad'], wipBeforeCancel.single['cantidad'] as num);
    expect(
      (await MrpWorkOrderService().list())
          .singleWhere((o) => o.id == orderId)
          .status,
      MrpWorkOrderStatus.cancelada,
    );
    expect(
      (await MrpWorkOrderService().items(orderId)).single.transferredQty,
      0,
    );
  });

  test('MRP no permite cambiar una BOM usada por una orden activa', () async {
    final zero = MoneyValue(minorUnits: 0, currency: cop);
    final bomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: finishedProductId,
        rawMaterialCost: zero,
        operatingCost: zero,
        totalCost: zero,
      ),
    );
    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: finishedProductId,
        bomId: bomId,
        qtyPlanned: 1,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: zero,
        actualOperatingCost: zero,
        rawMaterialCost: zero,
        totalCost: zero,
      ),
    );
    final bom = (await MrpBomService().list()).firstWhere((b) => b.id == bomId);
    await expectLater(
      () => MrpBomService().create(
        MrpBom(
          id: bom.id,
          companyId: companyId,
          itemId: bom.itemId,
          quantity: bom.quantity,
          rawMaterialCost: zero,
          operatingCost: zero,
          totalCost: zero,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await MrpWorkOrderService().list())
          .singleWhere((o) => o.id == orderId)
          .status,
      MrpWorkOrderStatus.borrador,
    );
  });

  test('MRP permite cerrar una orden con produccion parcial', () async {
    final zero = MoneyValue(minorUnits: 0, currency: cop);
    final partialProduct = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto parcial',
      'unidad_base': 'UND',
      'stock': 0,
      'costo': 0,
      'precio': 0,
      'impuesto_pct': 0,
    });
    for (final warehouseId in [1, 2, 3]) {
      await db.insert('stock_bodega', {
        'company_id': companyId,
        'producto_id': partialProduct,
        'bodega_id': warehouseId,
        'cantidad': 0,
        'costo': 0,
        'actualizado_en': DateTime.now().toIso8601String(),
      });
    }
    final partialBomId = await MrpBomService().create(
      MrpBom(
        companyId: companyId,
        itemId: partialProduct,
        rawMaterialCost: zero,
        operatingCost: zero,
        totalCost: zero,
      ),
    );
    final orderId = await MrpWorkOrderService().create(
      draft: MrpWorkOrder(
        companyId: companyId,
        productionItemId: partialProduct,
        bomId: partialBomId,
        qtyPlanned: 10,
        wipWarehouseId: 2,
        fgWarehouseId: 3,
        plannedOperatingCost: zero,
        actualOperatingCost: zero,
        rawMaterialCost: zero,
        totalCost: zero,
      ),
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.noIniciada,
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.enProceso,
    );
    await MrpWorkOrderService().transition(
      orderId,
      MrpWorkOrderStatus.completada,
      producedQty: 6,
    );

    final order = (await MrpWorkOrderService().list()).singleWhere(
      (item) => item.id == orderId,
    );
    final finished = await db.query(
      'stock_bodega',
      where: 'producto_id = ? AND bodega_id = ?',
      whereArgs: [partialProduct, 3],
    );
    expect(order.status, MrpWorkOrderStatus.completada);
    expect(order.qtyProduced, 6);
    expect(finished.single['cantidad'], 6);
  });
}
