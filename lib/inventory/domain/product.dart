import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class Product {
  Product({
    this.id,
    this.companyId,
    required this.name,
    required this.unit,
    required this.stock,
    required this.cost,
    required this.price,
    required this.taxRate,
    this.barcode = '',
    this.conversionName = '',
    this.conversionQuantity = 0,
    this.itemType = 'producto',
    this.precioIncluyeIva = false,
  });

  final int? id;
  final int? companyId;
  final String name;
  final String unit;
  final double stock;
  final MoneyValue cost;
  final MoneyValue price;
  final double taxRate;
  final String barcode;
  final String conversionName;
  final double conversionQuantity;
  final String itemType;
  final bool precioIncluyeIva;

  bool get isService => itemType == 'servicio';
  bool get isProduct => itemType != 'servicio';

  bool get lowStock => isService ? false : stock <= 5;

  MoneyValue get stockCostValue => isService ? MoneyValue.fromMajorUnits('0', currency: cost.currency) : cost.multiplyDecimal(stock.toString());

  MoneyValue get stockSaleValue => isService ? MoneyValue.fromMajorUnits('0', currency: price.currency) : price.multiplyDecimal(stock.toString());

  Product copyWith({
    int? id,
    int? companyId,
    String? name,
    String? unit,
    double? stock,
    MoneyValue? cost,
    MoneyValue? price,
    double? taxRate,
    String? barcode,
    String? conversionName,
    double? conversionQuantity,
    String? itemType,
    bool? precioIncluyeIva,
  }) {
    return Product(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      stock: stock ?? this.stock,
      cost: cost ?? this.cost,
      price: price ?? this.price,
      taxRate: taxRate ?? this.taxRate,
      barcode: barcode ?? this.barcode,
      conversionName: conversionName ?? this.conversionName,
      conversionQuantity: conversionQuantity ?? this.conversionQuantity,
      itemType: itemType ?? this.itemType,
      precioIncluyeIva: precioIncluyeIva ?? this.precioIncluyeIva,
    );
  }

  factory Product.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return Product(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      name: map['nombre']?.toString() ?? '',
      unit: map['unidad_base']?.toString() ?? 'UND',
      stock: (map['stock'] as num?)?.toDouble() ?? 0,
      cost: MoneyValue.fromSql(
        map['costo'],
        currency: currency,
        nullableAsZero: true,
      ),
      price: MoneyValue.fromSql(
        map['precio'],
        currency: currency,
        nullableAsZero: true,
      ),
      taxRate: (map['impuesto_pct'] as num?)?.toDouble() ?? 0,
      barcode: map['codigo_barras']?.toString() ?? '',
      conversionName: map['conversion_nombre']?.toString() ?? '',
      conversionQuantity: (map['conversion_cantidad'] as num?)?.toDouble() ?? 0,
      itemType: map['tipo_item']?.toString() ?? 'producto',
      precioIncluyeIva: (map['precio_incluye_iva'] as num?)?.toInt() == 1 || map['precio_incluye_iva'] == true,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    if (companyId != null) 'company_id': companyId,
    'nombre': name,
    'unidad_base': unit,
    'stock': stock,
    'costo': cost.toSql(),
    'precio': price.toSql(),
    'impuesto_pct': taxRate,
    'codigo_barras': barcode,
    'conversion_nombre': conversionName,
    'conversion_cantidad': conversionQuantity,
    'tipo_item': itemType,
    'precio_incluye_iva': precioIncluyeIva ? 1 : 0,
  };

  Map<String, Object?> toPersistenceMap() {
    final map = toMap()..remove('id');
    return map;
  }
}
