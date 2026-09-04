import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class InventoryLot {
  final int? id;
  final int companyId;
  final int productId;
  final String lotNumber;
  final DateTime manufacturingDate;
  final DateTime expirationDate;
  final double initialQuantity;
  final double currentQuantity;
  final MoneyValue unitCost;
  final String? supplierId;
  final String? purchaseDocumentId;
  final String? warehouseId;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  InventoryLot({
    this.id,
    required this.companyId,
    required this.productId,
    required this.lotNumber,
    required this.manufacturingDate,
    required this.expirationDate,
    required this.initialQuantity,
    required this.currentQuantity,
    required this.unitCost,
    this.supplierId,
    this.purchaseDocumentId,
    this.warehouseId,
    this.status = 'active',
    required this.createdAt,
    this.updatedAt,
  });

  bool get isExpired => DateTime.now().isAfter(expirationDate);
  bool get isNearExpiry {
    final days = expirationDate.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 30;
  }

  bool get isCriticalExpiry {
    final days = expirationDate.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }

  bool get isDepleted => currentQuantity <= 0;
  int get daysUntilExpiry => expirationDate.difference(DateTime.now()).inDays;

  InventoryLot copyWith({
    int? id,
    int? companyId,
    int? productId,
    String? lotNumber,
    DateTime? manufacturingDate,
    DateTime? expirationDate,
    double? initialQuantity,
    double? currentQuantity,
    MoneyValue? unitCost,
    String? supplierId,
    String? purchaseDocumentId,
    String? warehouseId,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InventoryLot(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    productId: productId ?? this.productId,
    lotNumber: lotNumber ?? this.lotNumber,
    manufacturingDate: manufacturingDate ?? this.manufacturingDate,
    expirationDate: expirationDate ?? this.expirationDate,
    initialQuantity: initialQuantity ?? this.initialQuantity,
    currentQuantity: currentQuantity ?? this.currentQuantity,
    unitCost: unitCost ?? this.unitCost,
    supplierId: supplierId ?? this.supplierId,
    purchaseDocumentId: purchaseDocumentId ?? this.purchaseDocumentId,
    warehouseId: warehouseId ?? this.warehouseId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'company_id': companyId,
    'product_id': productId,
    // Aliases del esquema legacy v1, conservados para instalaciones
    // existentes que todavía crean lotes desde db_helper.dart.
    'quantity': currentQuantity,
    'batch_number': lotNumber,
    'serial_number': null,
    'received_at': createdAt.toIso8601String(),
    'lot_number': lotNumber,
    'manufacturing_date': manufacturingDate.toIso8601String(),
    'expiration_date': expirationDate.toIso8601String(),
    'initial_quantity': initialQuantity,
    'current_quantity': currentQuantity,
    'unit_cost': unitCost.toSql(),
    'supplier_id': supplierId,
    'purchase_document_id': purchaseDocumentId,
    'warehouse_id': warehouseId,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory InventoryLot.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) => InventoryLot(
    id: map['id'] as int?,
    companyId: map['company_id'] as int,
    productId: map['product_id'] as int,
    lotNumber: map['lot_number'] as String,
    manufacturingDate: DateTime.parse(map['manufacturing_date'] as String),
    expirationDate: DateTime.parse(map['expiration_date'] as String),
    initialQuantity: (map['initial_quantity'] as num).toDouble(),
    currentQuantity: (map['current_quantity'] as num).toDouble(),
    unitCost: MoneyValue.fromSql(map['unit_cost'], currency: currency),
    supplierId: map['supplier_id'] as String?,
    purchaseDocumentId: map['purchase_document_id'] as String?,
    warehouseId: map['warehouse_id'] as String?,
    status: map['status'] as String? ?? 'active',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: map['updated_at'] != null
        ? DateTime.parse(map['updated_at'] as String)
        : null,
  );
}
