import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class MrpBomItem {
  const MrpBomItem({
    this.id,
    required this.companyId,
    required this.bomId,
    required this.itemId,
    required this.qty,
    this.uom = 'UND',
    required this.rate,
    required this.amount,
    this.sourceWarehouseId,
    this.isSubAssemblyItem = false,
  });
  final int? id;
  final int companyId;
  final int bomId;
  final int itemId;
  final double qty;
  final String uom;
  final MoneyValue rate;
  final MoneyValue amount;
  final int? sourceWarehouseId;
  final bool isSubAssemblyItem;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'bom_id': bomId,
    'item_id': itemId,
    'qty': qty,
    'uom': uom,
    'rate': rate.toSql(),
    'amount': amount.toSql(),
    'source_warehouse_id': sourceWarehouseId,
    'is_sub_assembly_item': isSubAssemblyItem ? 1 : 0,
  };
  factory MrpBomItem.fromMap(Map<String, dynamic> m, Currency c) => MrpBomItem(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    bomId: (m['bom_id'] as num).toInt(),
    itemId: (m['item_id'] as num).toInt(),
    qty: (m['qty'] as num).toDouble(),
    uom: m['uom']?.toString() ?? 'UND',
    rate: MoneyValue.fromSql(m['rate'], currency: c, nullableAsZero: true),
    amount: MoneyValue.fromSql(m['amount'], currency: c, nullableAsZero: true),
    sourceWarehouseId: (m['source_warehouse_id'] as num?)?.toInt(),
    isSubAssemblyItem: m['is_sub_assembly_item'] == 1,
  );
}
