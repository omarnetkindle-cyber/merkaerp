import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class OrderLine {
  final int? id;
  final int companyId;
  final int orderId;
  final int productId;
  final String productName;
  final double quantity;
  final MoneyValue unitPrice;
  final MoneyValue unitCost;
  final MoneyValue discountAmount;
  final double taxPercentage;
  final MoneyValue taxAmount;
  final MoneyValue subtotal;
  final MoneyValue total;
  final String? notes;
  final DateTime createdAt;

  OrderLine({
    this.id,
    required this.companyId,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.discountAmount,
    this.taxPercentage = 0,
    required this.taxAmount,
    required this.subtotal,
    required this.total,
    this.notes,
    required this.createdAt,
  });

  OrderLine copyWith({
    int? id,
    int? companyId,
    int? orderId,
    int? productId,
    String? productName,
    double? quantity,
    MoneyValue? unitPrice,
    MoneyValue? unitCost,
    MoneyValue? discountAmount,
    double? taxPercentage,
    MoneyValue? taxAmount,
    MoneyValue? subtotal,
    MoneyValue? total,
    String? notes,
    DateTime? createdAt,
  }) {
    return OrderLine(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      unitCost: unitCost ?? this.unitCost,
      discountAmount: discountAmount ?? this.discountAmount,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      taxAmount: taxAmount ?? this.taxAmount,
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'company_id': companyId,
    'order_id': orderId,
    'product_id': productId,
    'product_name': productName,
    'quantity': quantity,
    'unit_price': unitPrice.toSql(),
    'unit_cost': unitCost.toSql(),
    'discount_amount': discountAmount.toSql(),
    'tax_percentage': taxPercentage,
    'tax_amount': taxAmount.toSql(),
    'subtotal': subtotal.toSql(),
    'total': total.toSql(),
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  factory OrderLine.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return OrderLine(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      orderId: map['order_id'] as int,
      productId: map['product_id'] as int,
      productName: map['product_name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: MoneyValue.fromSql(map['unit_price'], currency: currency),
      unitCost: MoneyValue.fromSql(map['unit_cost'], currency: currency),
      discountAmount: MoneyValue.fromSql(
        map['discount_amount'],
        currency: currency,
        nullableAsZero: true,
      ),
      taxPercentage: (map['tax_percentage'] as num?)?.toDouble() ?? 0,
      taxAmount: MoneyValue.fromSql(
        map['tax_amount'],
        currency: currency,
        nullableAsZero: true,
      ),
      subtotal: MoneyValue.fromSql(map['subtotal'], currency: currency),
      total: MoneyValue.fromSql(map['total'], currency: currency),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static OrderLine calculate({
    required int companyId,
    required int orderId,
    required int productId,
    required String productName,
    required double quantity,
    required MoneyValue unitPrice,
    required MoneyValue unitCost,
    MoneyValue? discountAmount,
    double taxPercentage = 0,
    String? notes,
  }) {
    final lineSubtotal = unitPrice.multiplyDecimal(quantity.toString());
    final lineDiscount =
        discountAmount ??
        MoneyValue(minorUnits: 0, currency: unitPrice.currency);
    final taxableAmount = lineSubtotal - lineDiscount;
    final lineTax = taxableAmount.percent(taxPercentage.toString());
    final lineTotal = taxableAmount + lineTax;

    return OrderLine(
      companyId: companyId,
      orderId: orderId,
      productId: productId,
      productName: productName,
      quantity: quantity,
      unitPrice: unitPrice,
      unitCost: unitCost,
      discountAmount: lineDiscount,
      taxPercentage: taxPercentage,
      taxAmount: lineTax,
      subtotal: lineSubtotal,
      total: lineTotal,
      notes: notes,
      createdAt: DateTime.now(),
    );
  }
}
