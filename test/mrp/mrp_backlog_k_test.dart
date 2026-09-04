import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/mrp/application/mrp_services.dart';
import 'package:merka_erp/mrp/database/schema_mrp.dart';
import 'package:merka_erp/mrp/domain/mrp_operation.dart';
import 'package:merka_erp/mrp/domain/mrp_routing.dart';
import 'package:merka_erp/mrp/domain/mrp_work_order.dart';
import 'package:merka_erp/mrp/domain/mrp_workstation.dart';
import 'package:merka_erp/mrp/domain/mrp_workstation_shift.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    dir = await Directory.systemTemp.createTemp('merkaerp_mrp_k_');
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
      'nombre': 'Materia prima K',
      'unidad_base': 'UND',
      'stock': 10,
      'costo': 1000,
      'precio': 1000,
      'impuesto_pct': 0,
    });
    finishedProductId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto K',
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

  test(
    'MRP selecciona ruta default, suma subcontratacion y valida turnos',
    () async {
      final workstationId = await MrpWorkstationService().create(
        MrpWorkstation(
          companyId: companyId,
          name: 'Corte K',
          hourRate: MoneyValue.fromMajorUnits('10', currency: cop),
          availableHoursPerDay: 8,
          warehouseId: 2,
        ),
      );
      final supplierId = await db.insert('proveedores', {
        'company_id': companyId,
        'nombre': 'Taller tercero',
        'estado': 'activo',
        'fecha': DateTime(2026, 8, 14).toIso8601String(),
      });
      await MrpRoutingService().create(
        MrpRouting(
          companyId: companyId,
          itemId: finishedProductId,
          name: 'Ruta interna lenta',
          priority: 2,
          isDefault: false,
        ),
      );
      final defaultRoutingId = await MrpRoutingService().create(
        MrpRouting(
          companyId: companyId,
          itemId: finishedProductId,
          name: 'Ruta mixta default',
          priority: 1,
          isDefault: true,
          selectionCriteria: 'menor_costo',
        ),
      );
      await MrpOperationService().create(
        MrpOperation(
          companyId: companyId,
          routingId: defaultRoutingId,
          workstationId: workstationId,
          operationName: 'Corte interno',
          sequenceOrder: 1,
          timeMinutes: 60,
        ),
      );
      await MrpOperationService().create(
        MrpOperation(
          companyId: companyId,
          routingId: defaultRoutingId,
          workstationId: workstationId,
          operationName: 'Pintura tercerizada',
          sequenceOrder: 2,
          timeMinutes: 120,
          isSubcontracted: true,
          supplierId: supplierId,
          subcontractCost: MoneyValue.fromMajorUnits('30', currency: cop),
          leadTimeDays: 2,
        ),
      );

      final bomId = await MrpBomService().createDraft(
        itemId: finishedProductId,
        quantity: 1,
      );
      final draftBom = (await db.query(
        'mrp_boms',
        where: 'id = ?',
        whereArgs: [bomId],
      )).single;
      expect(draftBom['routing_id'], defaultRoutingId);

      final recalculated = await MrpBomService().recalculate(bomId);
      expect(recalculated.operatingCost.minorUnits, 4000);
      expect(recalculated.totalCost.minorUnits, 4000);

      await MrpWorkstationShiftService().create(
        MrpWorkstationShift(
          companyId: companyId,
          workstationId: workstationId,
          weekday: DateTime.monday,
          shiftName: 'Manana',
          startTime: '08:00',
          endTime: '09:00',
          availableHours: 1,
        ),
      );

      final monday = DateTime(2026, 8, 17);
      await expectLater(
        () => MrpWorkOrderService().create(
          draft: MrpWorkOrder(
            companyId: companyId,
            productionItemId: finishedProductId,
            bomId: bomId,
            qtyPlanned: 2,
            wipWarehouseId: 2,
            fgWarehouseId: 3,
            plannedStartDate: monday,
            plannedOperatingCost: recalculated.operatingCost,
            actualOperatingCost: MoneyValue(minorUnits: 0, currency: cop),
            rawMaterialCost: recalculated.rawMaterialCost,
            totalCost: recalculated.totalCost,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      await MrpWorkstationShiftService().create(
        MrpWorkstationShift(
          companyId: companyId,
          workstationId: workstationId,
          weekday: DateTime.monday,
          shiftName: 'Tarde',
          startTime: '09:00',
          endTime: '11:00',
          availableHours: 2,
        ),
      );
      final orderId = await MrpWorkOrderService().create(
        draft: MrpWorkOrder(
          companyId: companyId,
          productionItemId: finishedProductId,
          bomId: bomId,
          qtyPlanned: 2,
          wipWarehouseId: 2,
          fgWarehouseId: 3,
          plannedStartDate: monday,
          plannedOperatingCost: recalculated.operatingCost,
          actualOperatingCost: MoneyValue(minorUnits: 0, currency: cop),
          rawMaterialCost: recalculated.rawMaterialCost,
          totalCost: recalculated.totalCost,
        ),
      );
      expect(orderId, greaterThan(0));
      expect(
        await MrpWorkstationShiftService().availableHoursForDate(
          workstationId: workstationId,
          date: monday,
        ),
        3,
      );
    },
  );

  test('v104 agrega rutas alternativas, subcontratacion y turnos', () async {
    final legacyDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(legacyDb.close);
    await legacyDb.execute('''
      CREATE TABLE mrp_routings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');
    await legacyDb.execute('''
      CREATE TABLE mrp_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        routing_id INTEGER NOT NULL,
        workstation_id INTEGER NOT NULL,
        operation_name TEXT NOT NULL,
        sequence_order INTEGER NOT NULL DEFAULT 1,
        time_minutes REAL NOT NULL DEFAULT 0
      )
    ''');
    await legacyDb.insert('mrp_routings', {
      'id': 1,
      'company_id': 1,
      'name': 'Ruta legacy',
    });

    await DatabaseHelper.instance.migrarDBForTesting(legacyDb, 103, 104);

    final routingColumns = await legacyDb.rawQuery(
      'PRAGMA table_info(mrp_routings)',
    );
    final operationColumns = await legacyDb.rawQuery(
      'PRAGMA table_info(mrp_operations)',
    );
    expect(routingColumns.any((column) => column['name'] == 'item_id'), isTrue);
    expect(
      operationColumns.any((column) => column['name'] == 'subcontract_cost'),
      isTrue,
    );
    expect(
      await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'mrp_workstation_shifts'",
      ),
      hasLength(1),
    );
    expect(
      (await legacyDb.query('mrp_routings')).single['name'],
      'Ruta legacy',
    );
  });
}
