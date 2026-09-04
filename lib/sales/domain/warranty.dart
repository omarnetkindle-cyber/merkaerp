// ============================================================
// warranty.dart
// Modelo para gestión de garantías
// ============================================================

class Warranty {
  final int? id;
  final int companyId;
  final int? saleId;
  final String? saleNumber;
  final int productId;
  final String productName;
  final int customerId;
  final String customerName;
  final DateTime startDate;
  final DateTime endDate;
  final int durationMonths;
  final String warrantyType; // manufacturer, seller, extended
  final String status; // active, expired, claimed, cancelled
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Warranty({
    this.id,
    required this.companyId,
    this.saleId,
    this.saleNumber,
    required this.productId,
    required this.productName,
    required this.customerId,
    required this.customerName,
    required this.startDate,
    required this.endDate,
    required this.durationMonths,
    required this.warrantyType,
    this.status = 'active',
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';
  bool get isClaimed => status == 'claimed';
  bool get isCancelled => status == 'cancelled';

  /// Verifica si la garantía está vigente
  bool isValid() {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate);
  }

  /// Días restantes de garantía
  int get daysRemaining {
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  Warranty copyWith({
    int? id,
    int? companyId,
    int? saleId,
    String? saleNumber,
    int? productId,
    String? productName,
    int? customerId,
    String? customerName,
    DateTime? startDate,
    DateTime? endDate,
    int? durationMonths,
    String? warrantyType,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Warranty(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      saleId: saleId ?? this.saleId,
      saleNumber: saleNumber ?? this.saleNumber,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      durationMonths: durationMonths ?? this.durationMonths,
      warrantyType: warrantyType ?? this.warrantyType,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'sale_id': saleId,
      'sale_number': saleNumber,
      // Aliases del esquema legacy v51, que conserva columnas NOT NULL.
      'venta_id': saleId,
      'producto_id': productId,
      'numero_serie': null,
      'descripcion_problema': notes ?? 'Garantía registrada',
      'fecha_recepcion': startDate.toIso8601String(),
      'dias_garantia': durationMonths * 30,
      'product_id': productId,
      'product_name': productName,
      'customer_id': customerId,
      'customer_name': customerName,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'duration_months': durationMonths,
      'warranty_type': warrantyType,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Warranty.fromMap(Map<String, dynamic> map) {
    return Warranty(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      saleId: map['sale_id'] as int?,
      saleNumber: map['sale_number'] as String?,
      productId: map['product_id'] as int,
      productName: map['product_name'] as String,
      customerId: map['customer_id'] as int,
      customerName: map['customer_name'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      durationMonths: map['duration_months'] as int,
      warrantyType: map['warranty_type'] as String,
      status: map['status'] as String? ?? 'active',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
