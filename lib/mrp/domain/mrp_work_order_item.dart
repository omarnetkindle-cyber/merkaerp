class MrpWorkOrderItem {
  const MrpWorkOrderItem({
    this.id,
    required this.companyId,
    required this.workOrderId,
    required this.itemId,
    required this.requiredQty,
    this.transferredQty = 0,
    this.consumedQty = 0,
    this.sourceWarehouseId,
  });
  final int? id;
  final int companyId;
  final int workOrderId;
  final int itemId;
  final double requiredQty;
  final double transferredQty;
  final double consumedQty;
  final int? sourceWarehouseId;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'work_order_id': workOrderId,
    'item_id': itemId,
    'required_qty': requiredQty,
    'transferred_qty': transferredQty,
    'consumed_qty': consumedQty,
    'source_warehouse_id': sourceWarehouseId,
  };
  factory MrpWorkOrderItem.fromMap(Map<String, dynamic> m) => MrpWorkOrderItem(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    workOrderId: (m['work_order_id'] as num).toInt(),
    itemId: (m['item_id'] as num).toInt(),
    requiredQty: (m['required_qty'] as num).toDouble(),
    transferredQty: (m['transferred_qty'] as num?)?.toDouble() ?? 0,
    consumedQty: (m['consumed_qty'] as num?)?.toDouble() ?? 0,
    sourceWarehouseId: (m['source_warehouse_id'] as num?)?.toInt(),
  );
}
