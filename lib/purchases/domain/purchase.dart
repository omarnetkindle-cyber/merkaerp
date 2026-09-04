import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class Purchase {
  const Purchase({
    this.id,
    this.companyId,
    this.supplierId,
    required this.supplier,
    this.invoiceNumber,
    this.invoiceDate,
    this.observation,
    required this.subtotal,
    required this.taxRate,
    required this.taxTotal,
    required this.total,
    required this.cashPayment,
    required this.bankPayment,
    required this.credit,
    required this.date,
    required this.paymentMethodId,
    required this.status,
  });

  final int? id;
  final int? companyId;
  final int? supplierId;
  final String supplier;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? observation;
  final MoneyValue subtotal;
  final double taxRate;
  final MoneyValue taxTotal;
  final MoneyValue total;
  final MoneyValue cashPayment;
  final MoneyValue bankPayment;
  final MoneyValue credit;
  final String date;
  final int paymentMethodId;
  final String status;

  bool get isCanceled => status == 'anulada';
  bool get hasCredit => credit.minorUnits > 0;

  factory Purchase.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    MoneyValue money(String key) =>
        MoneyValue.fromSql(map[key], currency: currency, nullableAsZero: true);
    return Purchase(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      supplierId: (map['proveedor_id'] as num?)?.toInt(),
      supplier: map['proveedor']?.toString() ?? 'Sin proveedor',
      invoiceNumber: map['numero_factura']?.toString(),
      invoiceDate: map['fecha_factura']?.toString(),
      observation: map['observacion']?.toString(),
      subtotal: money('subtotal'),
      taxRate: (map['impuesto_pct'] as num?)?.toDouble() ?? 0,
      taxTotal: money('impuesto_total'),
      total: money('total'),
      cashPayment: money('efectivo'),
      bankPayment: money('transferencia'),
      credit: money('credito'),
      date: map['fecha']?.toString() ?? '',
      paymentMethodId: (map['metodo_pago_id'] as num?)?.toInt() ?? 1,
      status: map['estado']?.toString() ?? 'pagada',
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    if (companyId != null) 'company_id': companyId,
    'proveedor_id': supplierId,
    'proveedor': supplier,
    'numero_factura': invoiceNumber,
    'fecha_factura': invoiceDate,
    'observacion': observation,
    'subtotal': subtotal,
    'impuesto_pct': taxRate,
    'impuesto_total': taxTotal,
    'total': total,
    'efectivo': cashPayment,
    'transferencia': bankPayment,
    'credito': credit,
    'fecha': date,
    'metodo_pago_id': paymentMethodId,
    'estado': status,
  };
}

class PurchaseLine {
  const PurchaseLine({
    this.id,
    required this.purchaseId,
    required this.productId,
    required this.product,
    required this.quantity,
    required this.unitCost,
    required this.subtotal,
    this.unit,
    this.barcode,
  });

  final int? id;
  final int purchaseId;
  final int productId;
  final String product;
  final double quantity;
  final MoneyValue unitCost;
  final MoneyValue subtotal;
  final String? unit;
  final String? barcode;

  factory PurchaseLine.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return PurchaseLine(
      id: (map['id'] as num?)?.toInt(),
      purchaseId: (map['compra_id'] as num?)?.toInt() ?? 0,
      productId: (map['producto_id'] as num?)?.toInt() ?? 0,
      product: map['producto']?.toString() ?? '',
      quantity: (map['cantidad'] as num?)?.toDouble() ?? 0,
      unitCost: MoneyValue.fromSql(
        map['costo_unitario'],
        currency: currency,
        nullableAsZero: true,
      ),
      subtotal: MoneyValue.fromSql(
        map['subtotal'],
        currency: currency,
        nullableAsZero: true,
      ),
      unit: map['unidad_base']?.toString(),
      barcode: map['codigo_barras']?.toString(),
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'compra_id': purchaseId,
    'producto_id': productId,
    'producto': product,
    'cantidad': quantity,
    'costo_unitario': unitCost,
    'subtotal': subtotal,
    'unidad_base': unit,
    'codigo_barras': barcode,
  };
}
