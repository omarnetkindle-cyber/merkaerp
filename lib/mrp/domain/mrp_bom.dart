import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class MrpBom {
  const MrpBom({
    this.id,
    required this.companyId,
    required this.itemId,
    this.quantity = 1,
    this.uom = 'UND',
    this.isActive = true,
    this.isDefault = false,
    this.routingId,
    required this.rawMaterialCost,
    required this.operatingCost,
    required this.totalCost,
    this.entityType = 'comercial',
  });
  final int? id;
  final int companyId;
  final int itemId;
  final double quantity;
  final String uom;
  final bool isActive;
  final bool isDefault;
  final int? routingId;
  final MoneyValue rawMaterialCost;
  final MoneyValue operatingCost;
  final MoneyValue totalCost;
  final String entityType;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'item_id': itemId,
    'quantity': quantity,
    'uom': uom,
    'is_active': isActive ? 1 : 0,
    'is_default': isDefault ? 1 : 0,
    'routing_id': routingId,
    'raw_material_cost': rawMaterialCost.toSql(),
    'operating_cost': operatingCost.toSql(),
    'total_cost': totalCost.toSql(),
    'entity_type': entityType,
  };
  factory MrpBom.fromMap(Map<String, dynamic> m, Currency c) => MrpBom(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    itemId: (m['item_id'] as num).toInt(),
    quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
    uom: m['uom']?.toString() ?? 'UND',
    isActive: m['is_active'] != 0,
    isDefault: m['is_default'] == 1,
    routingId: (m['routing_id'] as num?)?.toInt(),
    rawMaterialCost: MoneyValue.fromSql(
      m['raw_material_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    operatingCost: MoneyValue.fromSql(
      m['operating_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    totalCost: MoneyValue.fromSql(
      m['total_cost'],
      currency: c,
      nullableAsZero: true,
    ),
    entityType: m['entity_type']?.toString() ?? 'comercial',
  );
}
