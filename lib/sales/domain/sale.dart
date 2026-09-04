import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class Sale {
  const Sale({
    this.id,
    this.companyId,
    required this.product,
    required this.quantity,
    required this.subtotal,
    required this.taxRate,
    required this.taxTotal,
    required this.total,
    required this.date,
    required this.paymentMethodId,
    this.clientId,
    required this.client,
    required this.status,
  });

  final int? id;
  final int? companyId;
  final String product;
  final double quantity;
  final MoneyValue subtotal;
  final double taxRate;
  final MoneyValue taxTotal;
  final MoneyValue total;
  final String date;
  final int paymentMethodId;
  final int? clientId;
  final String client;
  final String status;

  bool get isCanceled => status == 'anulada';

  factory Sale.fromMap(Map<String, dynamic> map, {required Currency currency}) {
    return Sale(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      product: map['producto']?.toString() ?? 'Factura POS',
      quantity: (map['cantidad'] as num?)?.toDouble() ?? 0,
      subtotal: MoneyValue.fromSql(
        map['subtotal'],
        currency: currency,
        nullableAsZero: true,
      ),
      taxRate: (map['impuesto_pct'] as num?)?.toDouble() ?? 0,
      taxTotal: MoneyValue.fromSql(
        map['impuesto_total'],
        currency: currency,
        nullableAsZero: true,
      ),
      total: MoneyValue.fromSql(
        map['total'],
        currency: currency,
        nullableAsZero: true,
      ),
      date: map['fecha']?.toString() ?? '',
      paymentMethodId: (map['metodo_pago_id'] as num?)?.toInt() ?? 1,
      clientId: (map['cliente_id'] as num?)?.toInt(),
      client: map['cliente']?.toString() ?? 'Cliente general',
      status: map['estado']?.toString() ?? 'emitida',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      'producto': product,
      'cantidad': quantity,
      'subtotal': subtotal,
      'impuesto_pct': taxRate,
      'impuesto_total': taxTotal,
      'total': total,
      'fecha': date,
      'metodo_pago_id': paymentMethodId,
      'cliente_id': clientId,
      'cliente': client,
      'estado': status,
    };
  }

  Map<String, Object?> toWireMap() => {
    ...toMap(),
    'subtotal': _wire(subtotal),
    'impuesto_total': _wire(taxTotal),
    'total': _wire(total),
  };
}

class SaleLine {
  const SaleLine({
    this.id,
    required this.saleId,
    required this.productId,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.unit,
    this.barcode,
  });

  final int? id;
  final int saleId;
  final int productId;
  final String product;
  final double quantity;
  final MoneyValue unitPrice;
  final MoneyValue subtotal;
  final String? unit;
  final String? barcode;

  factory SaleLine.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return SaleLine(
      id: (map['id'] as num?)?.toInt(),
      saleId: (map['venta_id'] as num?)?.toInt() ?? 0,
      productId: (map['producto_id'] as num?)?.toInt() ?? 0,
      product: map['producto']?.toString() ?? '',
      quantity: (map['cantidad'] as num?)?.toDouble() ?? 0,
      unitPrice: MoneyValue.fromSql(
        map['precio_unitario'],
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
    'venta_id': saleId,
    'producto_id': productId,
    'producto': product,
    'cantidad': quantity,
    'precio_unitario': unitPrice,
    'subtotal': subtotal,
    'unidad_base': unit,
    'codigo_barras': barcode,
  };

  Map<String, Object?> toWireMap() => {
    ...toMap(),
    'precio_unitario': _wire(unitPrice),
    'subtotal': _wire(subtotal),
  };
}

Map<String, Object> _wire(MoneyValue value) => {
  'minor_units': value.minorUnits,
  'currency': value.currencyCode,
  'scale': value.decimalPlaces,
};
