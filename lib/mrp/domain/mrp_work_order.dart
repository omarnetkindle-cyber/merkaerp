import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

enum MrpWorkOrderStatus {
  borrador,
  noIniciada,
  enProceso,
  completada,
  cancelada,
}

String mrpWorkOrderStatusValue(MrpWorkOrderStatus status) => switch (status) {
  MrpWorkOrderStatus.borrador => 'borrador',
  MrpWorkOrderStatus.noIniciada => 'no_iniciada',
  MrpWorkOrderStatus.enProceso => 'en_proceso',
  MrpWorkOrderStatus.completada => 'completada',
  MrpWorkOrderStatus.cancelada => 'cancelada',
};

MrpWorkOrderStatus mrpWorkOrderStatusFromValue(Object? value) =>
    switch (value?.toString()) {
      'no_iniciada' || 'noIniciada' => MrpWorkOrderStatus.noIniciada,
      'en_proceso' || 'enProceso' => MrpWorkOrderStatus.enProceso,
      'completada' => MrpWorkOrderStatus.completada,
      'cancelada' => MrpWorkOrderStatus.cancelada,
      _ => MrpWorkOrderStatus.borrador,
    };

class MrpWorkOrder {
  const MrpWorkOrder({
    this.id,
    required this.companyId,
    required this.productionItemId,
    required this.bomId,
    required this.qtyPlanned,
    this.qtyProduced = 0,
    this.status = MrpWorkOrderStatus.borrador,
    required this.wipWarehouseId,
    required this.fgWarehouseId,
    this.plannedStartDate,
    this.actualStartDate,
    this.plannedEndDate,
    this.actualEndDate,
    required this.plannedOperatingCost,
    required this.actualOperatingCost,
    required this.rawMaterialCost,
    required this.totalCost,
  });
  final int? id;
  final int companyId;
  final int productionItemId;
  final int bomId;
  final double qtyPlanned;
  final double qtyProduced;
  final MrpWorkOrderStatus status;
  final int wipWarehouseId;
  final int fgWarehouseId;
  final DateTime? plannedStartDate;
  final DateTime? actualStartDate;
  final DateTime? plannedEndDate;
  final DateTime? actualEndDate;
  final MoneyValue plannedOperatingCost;
  final MoneyValue actualOperatingCost;
  final MoneyValue rawMaterialCost;
  final MoneyValue totalCost;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'production_item_id': productionItemId,
    'bom_id': bomId,
    'qty_planned': qtyPlanned,
    'qty_produced': qtyProduced,
    'status': mrpWorkOrderStatusValue(status),
    'wip_warehouse_id': wipWarehouseId,
    'fg_warehouse_id': fgWarehouseId,
    'planned_start_date': plannedStartDate?.toIso8601String(),
    'actual_start_date': actualStartDate?.toIso8601String(),
    'planned_end_date': plannedEndDate?.toIso8601String(),
    'actual_end_date': actualEndDate?.toIso8601String(),
    'planned_operating_cost': plannedOperatingCost.toSql(),
    'actual_operating_cost': actualOperatingCost.toSql(),
    'raw_material_cost': rawMaterialCost.toSql(),
    'total_cost': totalCost.toSql(),
  };
  factory MrpWorkOrder.fromMap(
    Map<String, dynamic> m,
    Currency c,
  ) => MrpWorkOrder(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    productionItemId: (m['production_item_id'] as num).toInt(),
    bomId: (m['bom_id'] as num).toInt(),
    qtyPlanned: (m['qty_planned'] as num).toDouble(),
    qtyProduced: (m['qty_produced'] as num?)?.toDouble() ?? 0,
    status: mrpWorkOrderStatusFromValue(m['status']),
    wipWarehouseId: (m['wip_warehouse_id'] as num).toInt(),
    fgWarehouseId: (m['fg_warehouse_id'] as num).toInt(),
    plannedStartDate: DateTime.tryParse(
      m['planned_start_date']?.toString() ?? '',
    ),
    actualStartDate: DateTime.tryParse(
      m['actual_start_date']?.toString() ?? '',
    ),
    plannedEndDate: DateTime.tryParse(m['planned_end_date']?.toString() ?? ''),
    actualEndDate: DateTime.tryParse(m['actual_end_date']?.toString() ?? ''),
    plannedOperatingCost: MoneyValue.fromSql(
      m['planned_operating_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    actualOperatingCost: MoneyValue.fromSql(
      m['actual_operating_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    rawMaterialCost: MoneyValue.fromSql(
      m['raw_material_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    totalCost: MoneyValue.fromSql(
      m['total_cost'],
      currency: c,
      nullableAsZero: true,
    ),
  );
}
