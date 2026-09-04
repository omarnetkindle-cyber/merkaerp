import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class CrmOpportunityItem {
  const CrmOpportunityItem({
    this.id,
    required this.companyId,
    required this.opportunityId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.uom = 'UND',
    this.createdAt,
    this.modifiedAt,
  });

  final int? id;
  final int? companyId;
  final String opportunityId;
  final int productId;
  final double quantity;
  final MoneyValue unitPrice;
  final String uom;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  MoneyValue get amount => unitPrice.multiplyDecimal(_decimalText(quantity));

  Map<String, Object?> toPersistenceMap({int? companyIdOverride}) => {
    'company_id': companyIdOverride ?? companyId,
    'opportunity_id': opportunityId,
    'product_id': productId,
    'quantity': quantity,
    'uom': uom,
    'unit_price': unitPrice.toSql(),
    'amount': amount.toSql(),
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'modified_at': modifiedAt?.toIso8601String(),
  };

  factory CrmOpportunityItem.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) => CrmOpportunityItem(
    id: (map['id'] as num?)?.toInt(),
    companyId: (map['company_id'] as num?)?.toInt(),
    opportunityId: map['opportunity_id'].toString(),
    productId: (map['product_id'] as num).toInt(),
    quantity: (map['quantity'] as num).toDouble(),
    unitPrice: MoneyValue.fromSql(
      map['unit_price'],
      currency: currency,
      nullableAsZero: true,
    ),
    uom: map['uom']?.toString() ?? 'UND',
    createdAt: _itemDate(map['created_at']),
    modifiedAt: _itemDate(map['modified_at']),
  );
}

String _decimalText(double value) {
  if (!value.isFinite) throw ArgumentError('La cantidad debe ser finita.');
  return value.toString();
}

DateTime? _itemDate(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}
