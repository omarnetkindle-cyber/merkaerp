// ============================================================
// inventory_reservation.dart
// Modelo para reservas de inventario
// ============================================================

class InventoryReservation {
  final int? id;
  final int companyId;
  final int productId;
  final String? lotId;
  final String documentType; // order, sale, transfer
  final String documentId;
  final double reservedQuantity;
  final double fulfilledQuantity;
  final String status; // pending, partial, fulfilled, cancelled
  final DateTime reservedAt;
  final DateTime? fulfilledAt;
  final DateTime? cancelledAt;
  final String? notes;

  InventoryReservation({
    this.id,
    required this.companyId,
    required this.productId,
    this.lotId,
    required this.documentType,
    required this.documentId,
    required this.reservedQuantity,
    this.fulfilledQuantity = 0,
    this.status = 'pending',
    required this.reservedAt,
    this.fulfilledAt,
    this.cancelledAt,
    this.notes,
  });

  double get pendingQuantity => reservedQuantity - fulfilledQuantity;
  bool get isFulfilled => fulfilledQuantity >= reservedQuantity;
  bool get isPending => status == 'pending';
  bool get isCancelled => status == 'cancelled';
  bool get isPartial => status == 'partial';

  InventoryReservation copyWith({
    int? id,
    int? companyId,
    int? productId,
    String? lotId,
    String? documentType,
    String? documentId,
    double? reservedQuantity,
    double? fulfilledQuantity,
    String? status,
    DateTime? reservedAt,
    DateTime? fulfilledAt,
    DateTime? cancelledAt,
    String? notes,
  }) {
    return InventoryReservation(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      productId: productId ?? this.productId,
      lotId: lotId ?? this.lotId,
      documentType: documentType ?? this.documentType,
      documentId: documentId ?? this.documentId,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      fulfilledQuantity: fulfilledQuantity ?? this.fulfilledQuantity,
      status: status ?? this.status,
      reservedAt: reservedAt ?? this.reservedAt,
      fulfilledAt: fulfilledAt ?? this.fulfilledAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'product_id': productId,
      'lot_id': lotId,
      'document_type': documentType,
      'document_id': documentId,
      'reserved_quantity': reservedQuantity,
      'fulfilled_quantity': fulfilledQuantity,
      'status': status,
      'reserved_at': reservedAt.toIso8601String(),
      'fulfilled_at': fulfilledAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'notes': notes,
    };
  }

  factory InventoryReservation.fromMap(Map<String, dynamic> map) {
    return InventoryReservation(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      productId: map['product_id'] as int,
      lotId: map['lot_id'] as String?,
      documentType: map['document_type'] as String,
      documentId: map['document_id'] as String,
      reservedQuantity: (map['reserved_quantity'] as num).toDouble(),
      fulfilledQuantity: (map['fulfilled_quantity'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'pending',
      reservedAt: DateTime.parse(map['reserved_at'] as String),
      fulfilledAt: map['fulfilled_at'] != null 
          ? DateTime.parse(map['fulfilled_at'] as String) 
          : null,
      cancelledAt: map['cancelled_at'] != null 
          ? DateTime.parse(map['cancelled_at'] as String) 
          : null,
      notes: map['notes'] as String?,
    );
  }
}
