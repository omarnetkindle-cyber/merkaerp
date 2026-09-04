import '../../core/currency/money_value.dart';
import '../../inventory/application/warehouse_stock_service.dart';
import '../data/mrp_repositories.dart';
import '../domain/mrp_bom.dart';
import '../domain/mrp_bom_item.dart';
import '../domain/mrp_operation.dart';
import '../domain/mrp_routing.dart';
import '../domain/mrp_work_order.dart';
import '../domain/mrp_work_order_item.dart';
import '../domain/mrp_workstation.dart';
import '../domain/mrp_workstation_shift.dart';

class MrpWorkstationService {
  MrpWorkstationService({MrpWorkstationRepository? repository})
    : _repository = repository ?? MrpWorkstationRepository();
  final MrpWorkstationRepository _repository;
  Future<int> create(MrpWorkstation value) {
    if (value.name.trim().isEmpty) {
      throw ArgumentError('La estación de trabajo requiere un nombre.');
    }
    if (value.hourRate.minorUnits < 0 ||
        (value.availableHoursPerDay != null &&
            value.availableHoursPerDay! <= 0) ||
        (value.warehouseId != null && value.warehouseId! <= 0)) {
      throw ArgumentError('La estación debe tener tarifa y bodega válidas.');
    }
    return _repository.save(value);
  }

  Future<List<MrpWorkstation>> list() => _repository.list();
}

class MrpRoutingService {
  MrpRoutingService({MrpRoutingRepository? repository})
    : _repository = repository ?? MrpRoutingRepository();
  final MrpRoutingRepository _repository;
  Future<int> create(MrpRouting value) {
    if (value.name.trim().isEmpty) {
      throw ArgumentError('La ruta de fabricación requiere un nombre.');
    }
    if (value.itemId != null && value.itemId! <= 0) {
      throw ArgumentError('La ruta alternativa requiere producto válido.');
    }
    if (value.priority <= 0) {
      throw ArgumentError('La prioridad de ruta debe ser positiva.');
    }
    return _saveAndNormalizeDefault(value);
  }

  Future<List<MrpRouting>> list() => _repository.list();

  Future<List<MrpRouting>> listForProduct(int itemId) {
    if (itemId <= 0) {
      throw ArgumentError('El producto de ruta debe ser válido.');
    }
    return _repository.listForProduct(itemId);
  }

  Future<MrpRouting?> defaultForProduct(int itemId) {
    if (itemId <= 0) {
      throw ArgumentError('El producto de ruta debe ser válido.');
    }
    return _repository.defaultForProduct(itemId);
  }

  Future<int> _saveAndNormalizeDefault(MrpRouting value) async {
    final id = await _repository.save(value);
    if (value.itemId != null && value.isDefault) {
      await _repository.clearDefaultForProduct(value.itemId!, id);
    }
    return id;
  }
}

class MrpOperationService {
  MrpOperationService({MrpOperationRepository? repository})
    : _repository = repository ?? MrpOperationRepository();
  final MrpOperationRepository _repository;
  Future<int> create(MrpOperation value) {
    if (value.routingId <= 0 || value.workstationId <= 0) {
      throw ArgumentError('La operación requiere ruta y estación válidas.');
    }
    if (value.operationName.trim().isEmpty || value.timeMinutes < 0) {
      throw ArgumentError('La operación requiere nombre y tiempo válidos.');
    }
    if (value.isSubcontracted) {
      if (value.supplierId == null || value.supplierId! <= 0) {
        throw ArgumentError('La operación subcontratada requiere proveedor.');
      }
      if (value.subcontractCost == null ||
          value.subcontractCost!.minorUnits < 0 ||
          value.leadTimeDays < 0) {
        throw ArgumentError(
          'La operación subcontratada requiere costo y plazo válidos.',
        );
      }
    }
    return _repository.save(value);
  }

  Future<List<MrpOperation>> listForRouting(int routingId) =>
      _repository.listForRouting(routingId);
}

class MrpWorkstationShiftService {
  MrpWorkstationShiftService({
    MrpWorkstationShiftRepository? repository,
    MrpWorkstationRepository? workstations,
  }) : _repository = repository ?? MrpWorkstationShiftRepository(),
       _workstations = workstations ?? MrpWorkstationRepository();

  final MrpWorkstationShiftRepository _repository;
  final MrpWorkstationRepository _workstations;

  Future<int> create(MrpWorkstationShift value) async {
    if (value.workstationId <= 0 ||
        value.weekday < DateTime.monday ||
        value.weekday > DateTime.sunday ||
        value.shiftName.trim().isEmpty ||
        value.availableHours <= 0) {
      throw ArgumentError('El turno MRP requiere estación, día y horas.');
    }
    return _repository.save(value);
  }

  Future<List<MrpWorkstationShift>> listForWorkstation(int workstationId) {
    if (workstationId <= 0) {
      throw ArgumentError('La estación de trabajo debe ser válida.');
    }
    return _repository.listForWorkstation(workstationId);
  }

  Future<double?> availableHoursForDate({
    required int workstationId,
    required DateTime date,
  }) async {
    final shifts = await _repository.listForWorkstationAndWeekday(
      workstationId,
      date.weekday,
    );
    if (shifts.isNotEmpty) {
      return shifts.fold<double>(
        0,
        (total, shift) => total + shift.availableHours,
      );
    }
    final workstations = await _workstations.list();
    return workstations
        .where((workstation) => workstation.id == workstationId)
        .firstOrNull
        ?.availableHoursPerDay;
  }
}

class MrpBomService {
  MrpBomService({
    MrpBomRepository? boms,
    MrpBomItemRepository? items,
    MrpOperationRepository? operations,
    MrpRoutingRepository? routings,
    MrpWorkstationRepository? workstations,
    MrpRepositoryContext? context,
  }) : _context = context ?? MrpRepositoryContext(),
       _boms = boms ?? MrpBomRepository(context: context),
       _items = items ?? MrpBomItemRepository(context: context),
       _operations = operations ?? MrpOperationRepository(context: context),
       _routings = routings ?? MrpRoutingRepository(context: context),
       _workstations =
           workstations ?? MrpWorkstationRepository(context: context);
  final MrpRepositoryContext _context;
  final MrpBomRepository _boms;
  final MrpBomItemRepository _items;
  final MrpOperationRepository _operations;
  final MrpRoutingRepository _routings;
  final MrpWorkstationRepository _workstations;
  Future<int> create(MrpBom value) async {
    _validateBom(value);
    await _ensureBomEditable(value.id);
    return _boms.save(value);
  }

  Future<int> createDraft({
    required int itemId,
    required double quantity,
  }) async {
    final currency = await _context.currency;
    final defaultRouting = await _routings.defaultForProduct(itemId);
    return create(
      MrpBom(
        companyId: await _context.companyId,
        itemId: itemId,
        quantity: quantity,
        routingId: defaultRouting?.id,
        rawMaterialCost: MoneyValue(minorUnits: 0, currency: currency),
        operatingCost: MoneyValue(minorUnits: 0, currency: currency),
        totalCost: MoneyValue(minorUnits: 0, currency: currency),
      ),
    );
  }

  Future<int> addItem(MrpBomItem value) async {
    if (value.bomId <= 0 || value.itemId <= 0 || value.qty <= 0) {
      throw ArgumentError(
        'La línea de BOM requiere producto y cantidad válidos.',
      );
    }
    if (value.rate.minorUnits < 0 || value.amount.minorUnits < 0) {
      throw ArgumentError('La línea de BOM no puede tener costos negativos.');
    }
    final bom = await _boms.findById(value.bomId);
    if (bom == null) throw StateError('BOM no encontrada.');
    if (value.isSubAssemblyItem && value.itemId == bom.itemId) {
      throw StateError('Una BOM no puede referenciarse a sí misma.');
    }
    await _ensureBomEditable(value.bomId);
    return _items.save(value);
  }

  Future<List<MrpBom>> list() => _boms.list();
  Future<List<MrpBomItem>> items(int bomId) => _items.listForBom(bomId);

  Future<MrpBom> recalculate(int bomId) async {
    final bom = await _boms.findById(bomId);
    if (bom == null) throw StateError('BOM no encontrada.');
    await _ensureBomEditable(bomId);
    final costs = await _calculateCosts(bom, <int>{});
    final raw = costs.raw;
    final operating = costs.operating;
    final updated = MrpBom(
      id: bom.id,
      companyId: bom.companyId,
      itemId: bom.itemId,
      quantity: bom.quantity,
      uom: bom.uom,
      isActive: bom.isActive,
      isDefault: bom.isDefault,
      routingId: bom.routingId,
      rawMaterialCost: raw,
      operatingCost: operating,
      totalCost: raw + operating,
      entityType: bom.entityType,
    );
    await _boms.save(updated);
    return updated;
  }

  void _validateBom(MrpBom value) {
    if (value.itemId <= 0 || value.quantity <= 0) {
      throw ArgumentError('La BOM requiere producto y cantidad válidos.');
    }
    if (value.rawMaterialCost.minorUnits < 0 ||
        value.operatingCost.minorUnits < 0 ||
        value.totalCost.minorUnits < 0) {
      throw ArgumentError('La BOM no puede tener costos negativos.');
    }
  }

  Future<void> _ensureBomEditable(int? bomId) async {
    if (bomId == null) return;
    final db = await _context.db;
    final companyId = await _context.companyId;
    final active = await db.query(
      'mrp_work_orders',
      columns: ['id'],
      where: 'company_id = ? AND bom_id = ? AND status IN (?, ?, ?)',
      whereArgs: [companyId, bomId, 'borrador', 'no_iniciada', 'en_proceso'],
      limit: 1,
    );
    if (active.isNotEmpty) {
      throw StateError(
        'No se puede cambiar la BOM mientras la orden #${active.single['id']} esté activa.',
      );
    }
  }

  Future<_MrpCostBreakdown> _calculateCosts(
    MrpBom bom,
    Set<int> visited,
  ) async {
    if (bom.id != null && !visited.add(bom.id!)) {
      throw StateError('La BOM contiene un ciclo multinivel.');
    }
    var raw = MoneyValue(minorUnits: 0, currency: bom.totalCost.currency);
    var operating = MoneyValue(minorUnits: 0, currency: bom.totalCost.currency);
    final boms = await _boms.list();
    for (final item in await _items.listForBom(bom.id!)) {
      final child = item.isSubAssemblyItem
          ? boms.where((b) => b.itemId == item.itemId && b.isActive).firstOrNull
          : null;
      if (item.isSubAssemblyItem && child == null) {
        throw StateError(
          'La sub-ensamble #${item.itemId} no tiene una BOM activa.',
        );
      }
      if (child != null) {
        final childCosts = await _calculateCosts(child, {...visited});
        final factor = (item.qty / child.quantity).toString();
        raw += childCosts.raw.multiplyDecimal(factor);
        operating += childCosts.operating.multiplyDecimal(factor);
      } else {
        raw += item.rate.multiplyDecimal(item.qty.toString());
      }
    }
    if (bom.routingId != null) {
      final workstations = {
        for (final ws in await _workstations.list()) ws.id: ws,
      };
      for (final operation in await _operations.listForRouting(
        bom.routingId!,
      )) {
        final workstation = workstations[operation.workstationId];
        if (operation.isSubcontracted) {
          operating +=
              operation.subcontractCost ??
              MoneyValue(minorUnits: 0, currency: operating.currency);
        } else if (workstation != null) {
          operating += workstation.hourRate.multiplyDecimal(
            (operation.timeMinutes / 60).toString(),
          );
        }
      }
    }
    return _MrpCostBreakdown(raw: raw, operating: operating);
  }
}

class _MrpCostBreakdown {
  const _MrpCostBreakdown({required this.raw, required this.operating});
  final MoneyValue raw;
  final MoneyValue operating;
}

class MrpWorkOrderService {
  MrpWorkOrderService({
    MrpWorkOrderRepository? orders,
    MrpWorkOrderItemRepository? items,
    MrpBomRepository? boms,
    MrpBomItemRepository? bomItems,
    MrpOperationRepository? operations,
    MrpWorkstationShiftRepository? shifts,
    MrpWorkstationRepository? workstations,
    WarehouseStockService? stock,
  }) : _orders = orders ?? MrpWorkOrderRepository(),
       _items = items ?? MrpWorkOrderItemRepository(),
       _boms = boms ?? MrpBomRepository(),
       _bomItems = bomItems ?? MrpBomItemRepository(),
       _operations = operations ?? MrpOperationRepository(),
       _shifts = shifts ?? MrpWorkstationShiftRepository(),
       _workstations = workstations ?? MrpWorkstationRepository(),
       _stock = stock ?? WarehouseStockService();
  final MrpWorkOrderRepository _orders;
  final MrpWorkOrderItemRepository _items;
  final MrpBomRepository _boms;
  final MrpBomItemRepository _bomItems;
  final MrpOperationRepository _operations;
  final MrpWorkstationShiftRepository _shifts;
  final MrpWorkstationRepository _workstations;
  final WarehouseStockService _stock;

  Future<int> create({required MrpWorkOrder draft}) async {
    if (draft.qtyPlanned <= 0 ||
        draft.wipWarehouseId <= 0 ||
        draft.fgWarehouseId <= 0) {
      throw ArgumentError('La orden requiere cantidad y bodegas válidas.');
    }
    final bom = await _boms.findById(draft.bomId);
    if (bom == null || bom.itemId != draft.productionItemId) {
      throw StateError(
        'La BOM no existe o no corresponde al producto terminado.',
      );
    }
    if (draft.plannedStartDate != null && bom.routingId != null) {
      await _ensureCapacityForPlannedStart(
        routingId: bom.routingId!,
        qtyPlanned: draft.qtyPlanned,
        plannedStartDate: draft.plannedStartDate!,
      );
    }
    final exploded = await _explode(draft.bomId, draft.qtyPlanned, <int>{});
    final id = await _orders.save(draft);
    for (final item in exploded) {
      await _items.save(
        MrpWorkOrderItem(
          companyId: draft.companyId,
          workOrderId: id,
          itemId: item.itemId,
          requiredQty: item.requiredQty,
          sourceWarehouseId: item.sourceWarehouseId,
        ),
      );
    }
    return id;
  }

  Future<List<MrpWorkOrder>> list() => _orders.list();
  Future<List<MrpWorkOrderItem>> items(int orderId) =>
      _items.listForOrder(orderId);

  Future<bool> hasSufficientStock(int orderId) async {
    final orderItems = await _items.listForOrder(orderId);
    try {
      await _ensureStockAvailable(orderItems);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> transition(
    int orderId,
    MrpWorkOrderStatus target, {
    double? producedQty,
  }) async {
    final order = await _orders.findById(orderId);
    if (order == null) throw StateError('Orden de produccion no encontrada.');
    if (!_allowed(order.status, target)) {
      throw StateError(
        'Transicion ${order.status.name} -> ${target.name} no permitida.',
      );
    }
    final now = DateTime.now();
    if (target == MrpWorkOrderStatus.enProceso) {
      final orderItems = await _items.listForOrder(orderId);
      await _ensureStockAvailable(orderItems);
      for (final item in orderItems) {
        if (item.transferredQty >= item.requiredQty) continue;
        await _stock.transfer(
          productId: item.itemId,
          fromWarehouseId: item.sourceWarehouseId ?? 1,
          toWarehouseId: order.wipWarehouseId,
          quantity: item.requiredQty - item.transferredQty,
          reason: 'MRP WO#$orderId materia prima',
        );
        await _items.save(
          MrpWorkOrderItem(
            id: item.id,
            companyId: item.companyId,
            workOrderId: item.workOrderId,
            itemId: item.itemId,
            requiredQty: item.requiredQty,
            transferredQty: item.requiredQty,
            consumedQty: item.consumedQty,
            sourceWarehouseId: item.sourceWarehouseId,
          ),
        );
      }
    }
    if (target == MrpWorkOrderStatus.cancelada &&
        order.status == MrpWorkOrderStatus.enProceso) {
      final orderItems = await _items.listForOrder(orderId);
      if (orderItems.any((item) => item.consumedQty > 0)) {
        throw StateError(
          'No se puede cancelar una orden con material ya consumido; requiere ajuste manual.',
        );
      }
      await _reverseTransferredMaterial(orderItems, order.wipWarehouseId);
    }
    final completedQuantity = producedQty ?? order.qtyPlanned;
    if (target == MrpWorkOrderStatus.completada) {
      if (completedQuantity <= 0 || completedQuantity > order.qtyPlanned) {
        throw ArgumentError(
          'La cantidad producida debe ser mayor que cero y no superar la planificada.',
        );
      }
      final orderItems = await _items.listForOrder(orderId);
      final completionFactor = completedQuantity / order.qtyPlanned;
      final pendingConsumption = <MrpWorkOrderItem, double>{};
      for (final item in orderItems) {
        final targetConsumption = item.requiredQty * completionFactor;
        final pending = targetConsumption - item.consumedQty;
        if (pending > 0) {
          final available = await _stock.availableQuantity(
            productId: item.itemId,
            warehouseId: order.wipWarehouseId,
          );
          if (available < pending) {
            throw StateError(
              'No hay suficiente material en WIP para completar la orden: '
              'producto #${item.itemId}, requiere $pending y hay $available.',
            );
          }
          pendingConsumption[item] = pending;
        }
      }
      for (final entry in pendingConsumption.entries) {
        final item = entry.key;
        await _stock.consume(
          productId: item.itemId,
          warehouseId: order.wipWarehouseId,
          quantity: entry.value,
          reason: 'MRP WO#$orderId consumo de materia prima',
        );
        await _items.save(
          MrpWorkOrderItem(
            id: item.id,
            companyId: item.companyId,
            workOrderId: item.workOrderId,
            itemId: item.itemId,
            requiredQty: item.requiredQty,
            transferredQty: item.transferredQty,
            consumedQty: item.consumedQty + entry.value,
            sourceWarehouseId: item.sourceWarehouseId,
          ),
        );
      }
      await _stock.receiveProduction(
        productId: order.productionItemId,
        warehouseId: order.wipWarehouseId,
        quantity: completedQuantity,
        reason: 'MRP WO#$orderId producto terminado',
      );
      await _stock.transfer(
        productId: order.productionItemId,
        fromWarehouseId: order.wipWarehouseId,
        toWarehouseId: order.fgWarehouseId,
        quantity: completedQuantity,
        reason: 'MRP WO#$orderId producto terminado a FG',
      );
    }
    await _orders.save(
      MrpWorkOrder(
        id: order.id,
        companyId: order.companyId,
        productionItemId: order.productionItemId,
        bomId: order.bomId,
        qtyPlanned: order.qtyPlanned,
        qtyProduced: target == MrpWorkOrderStatus.completada
            ? completedQuantity
            : order.qtyProduced,
        status: target,
        wipWarehouseId: order.wipWarehouseId,
        fgWarehouseId: order.fgWarehouseId,
        plannedStartDate: order.plannedStartDate,
        actualStartDate: target == MrpWorkOrderStatus.enProceso
            ? now
            : order.actualStartDate,
        plannedEndDate: order.plannedEndDate,
        actualEndDate: target == MrpWorkOrderStatus.completada
            ? now
            : order.actualEndDate,
        plannedOperatingCost: order.plannedOperatingCost,
        actualOperatingCost: target == MrpWorkOrderStatus.completada
            ? order.plannedOperatingCost
            : order.actualOperatingCost,
        rawMaterialCost: order.rawMaterialCost,
        totalCost: order.totalCost,
      ),
    );
  }

  bool _allowed(
    MrpWorkOrderStatus from,
    MrpWorkOrderStatus to,
  ) => switch (from) {
    MrpWorkOrderStatus.borrador =>
      to == MrpWorkOrderStatus.noIniciada || to == MrpWorkOrderStatus.cancelada,
    MrpWorkOrderStatus.noIniciada =>
      to == MrpWorkOrderStatus.enProceso || to == MrpWorkOrderStatus.cancelada,
    MrpWorkOrderStatus.enProceso =>
      to == MrpWorkOrderStatus.completada || to == MrpWorkOrderStatus.cancelada,
    _ => false,
  };

  Future<List<MrpWorkOrderItem>> _explode(
    int bomId,
    double multiplier,
    Set<int> visited,
  ) async {
    if (!visited.add(bomId)) {
      throw StateError('La BOM contiene un ciclo multinivel.');
    }
    final result = <MrpWorkOrderItem>[];
    for (final item in await _bomItems.listForBom(bomId)) {
      final required = item.qty * multiplier;
      final child = (await _boms.list())
          .where((b) => b.itemId == item.itemId && b.isActive)
          .firstOrNull;
      if (item.isSubAssemblyItem && child == null) {
        throw StateError(
          'La sub-ensamble #${item.itemId} no tiene una BOM activa.',
        );
      }
      if (item.isSubAssemblyItem && child != null) {
        result.addAll(
          await _explode(child.id!, required / child.quantity, {...visited}),
        );
      } else {
        result.add(
          MrpWorkOrderItem(
            companyId: item.companyId,
            workOrderId: 0,
            itemId: item.itemId,
            requiredQty: required,
            sourceWarehouseId: item.sourceWarehouseId,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _ensureStockAvailable(List<MrpWorkOrderItem> orderItems) async {
    final required = <String, double>{};
    final sourceByKey = <String, ({int productId, int warehouseId})>{};
    for (final item in orderItems) {
      final warehouseId = item.sourceWarehouseId ?? 1;
      final key = '${item.itemId}:$warehouseId';
      required[key] =
          (required[key] ?? 0) + (item.requiredQty - item.transferredQty);
      sourceByKey[key] = (productId: item.itemId, warehouseId: warehouseId);
    }
    for (final entry in required.entries) {
      final source = sourceByKey[entry.key]!;
      final available = await _stock.availableQuantity(
        productId: source.productId,
        warehouseId: source.warehouseId,
      );
      if (available < entry.value) {
        throw StateError(
          'Stock insuficiente para producto #${source.productId}: '
          'requiere ${entry.value} y hay $available en la bodega ${source.warehouseId}.',
        );
      }
    }
  }

  Future<void> _ensureCapacityForPlannedStart({
    required int routingId,
    required double qtyPlanned,
    required DateTime plannedStartDate,
  }) async {
    final requiredByWorkstation = <int, double>{};
    for (final operation in await _operations.listForRouting(routingId)) {
      if (operation.isSubcontracted) continue;
      requiredByWorkstation[operation.workstationId] =
          (requiredByWorkstation[operation.workstationId] ?? 0) +
          (operation.timeMinutes / 60 * qtyPlanned);
    }
    if (requiredByWorkstation.isEmpty) return;
    final workstations = {
      for (final workstation in await _workstations.list())
        workstation.id: workstation,
    };
    for (final entry in requiredByWorkstation.entries) {
      final workstation = workstations[entry.key];
      final shifts = await _shifts.listForWorkstationAndWeekday(
        entry.key,
        plannedStartDate.weekday,
      );
      final capacity = shifts.isNotEmpty
          ? shifts.fold<double>(
              0,
              (total, shift) => total + shift.availableHours,
            )
          : workstation?.availableHoursPerDay;
      if (capacity == null) continue;
      if (entry.value > capacity) {
        throw StateError(
          'Capacidad insuficiente en '
          '${workstation?.name ?? 'estacion #${entry.key}'} para '
          '${plannedStartDate.toIso8601String().split('T').first}: '
          'requiere ${entry.value}h y hay ${capacity}h configuradas.',
        );
      }
    }
  }

  Future<void> _reverseTransferredMaterial(
    List<MrpWorkOrderItem> orderItems,
    int wipWarehouseId,
  ) async {
    final required = <String, double>{};
    final sourceByKey = <String, ({int productId, int warehouseId})>{};
    for (final item in orderItems) {
      if (item.transferredQty <= 0) continue;
      final sourceWarehouseId = item.sourceWarehouseId ?? 1;
      final key = '${item.itemId}:$sourceWarehouseId';
      required[key] = (required[key] ?? 0) + item.transferredQty;
      sourceByKey[key] = (
        productId: item.itemId,
        warehouseId: sourceWarehouseId,
      );
    }
    for (final entry in required.entries) {
      final source = sourceByKey[entry.key]!;
      final available = await _stock.availableQuantity(
        productId: source.productId,
        warehouseId: wipWarehouseId,
      );
      if (available < entry.value) {
        throw StateError(
          'No se puede cancelar: faltan ${entry.value - available} '
          'unidades del producto #${source.productId} en WIP.',
        );
      }
    }
    for (final item in orderItems) {
      if (item.transferredQty <= 0) continue;
      await _stock.transfer(
        productId: item.itemId,
        fromWarehouseId: wipWarehouseId,
        toWarehouseId: item.sourceWarehouseId ?? 1,
        quantity: item.transferredQty,
        reason: 'MRP WO#${item.workOrderId} reversión por cancelación',
      );
      await _items.save(
        MrpWorkOrderItem(
          id: item.id,
          companyId: item.companyId,
          workOrderId: item.workOrderId,
          itemId: item.itemId,
          requiredQty: item.requiredQty,
          sourceWarehouseId: item.sourceWarehouseId,
        ),
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
